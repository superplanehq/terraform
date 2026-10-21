#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/terraform-auth.sh"

cloud=${1:?cloud is required}
case "$cloud" in aws|gcp) ;; *) echo "Unsupported cloud: $cloud" >&2; exit 2 ;; esac
state_artifact="$cloud.tfstate"

setup_cloud() {
  case "$cloud" in
    aws)
      : "${AWS_ACCOUNT_ID:?Set AWS_ACCOUNT_ID}"
      configure_aws_credentials
      actual_account=$(aws sts get-caller-identity --query Account --output text)
      [[ "$actual_account" == "$AWS_ACCOUNT_ID" ]] || { echo "AWS account mismatch" >&2; exit 1; }
      export TF_VAR_region="${AWS_REGION:-us-east-1}"
      export TF_VAR_domain_name="${AWS_DOMAIN_NAME:?Set AWS_DOMAIN_NAME}"
      export TF_VAR_letsencrypt_email="${LETSENCRYPT_EMAIL:?Set LETSENCRYPT_EMAIL}"
      export TF_VAR_rds_deletion_protection=false
      export TF_VAR_rds_skip_final_snapshot=true
      export TF_VAR_blob_bucket_force_destroy=true
      ;;
    gcp)
      : "${GCP_PROJECT_ID:?Set GCP_PROJECT_ID}"
      configure_gcp_credentials
      gcloud config set project "$GCP_PROJECT_ID" --quiet >/dev/null
      export TF_VAR_project_id="$GCP_PROJECT_ID"
      export TF_VAR_zone="${GCP_ZONE:-us-central1-a}"
      export TF_VAR_domain_name="${GCP_DOMAIN_NAME:?Set GCP_DOMAIN_NAME}"
      export TF_VAR_static_ip_name="${GCP_STATIC_IP_NAME:?Set GCP_STATIC_IP_NAME}"
      export TF_VAR_letsencrypt_email="${LETSENCRYPT_EMAIL:?Set LETSENCRYPT_EMAIL}"
      export TF_VAR_gke_deletion_protection=false
      export TF_VAR_sql_deletion_protection=false
      export TF_VAR_blob_bucket_force_destroy=true
      export TF_VAR_enable_gcs_blob_storage=true
      export TF_VAR_enable_runners=true
      ;;
  esac
}

save_state() {
  if [[ -s terraform.tfstate ]]; then
    cp terraform.tfstate "$state_artifact"
    artifact push project "$state_artifact" --force
  fi
}

setup_cloud
cd "$cloud"
if artifact pull project "$state_artifact" --destination terraform.tfstate 2>artifact-error.log; then
  :
elif grep -Eiq 'not found|404' artifact-error.log; then
  echo "No saved state for $cloud; nothing to destroy."
  exit 0
else
  cat artifact-error.log >&2
  echo "Cannot load project state artifact for $cloud" >&2
  exit 1
fi
trap save_state EXIT

/tmp/terraform init -input=false -no-color
# A failed apply may save a cluster resource before Terraform creates outputs.
if /tmp/terraform state list | grep -Eq '^(aws_eks_cluster|google_container_cluster)\.superplane$'; then
  cluster=$(/tmp/terraform output -raw cluster_name)
  namespace=$(/tmp/terraform output -raw superplane_namespace)
  if [[ -z "$cluster" || -z "$namespace" ]]; then
    echo "Cluster outputs are unavailable; skipping Fleet Manager cleanup."
  else
    cluster_available=true
    case "$cloud" in
      aws)
        if ! cluster_error=$(aws eks describe-cluster --name "$cluster" --region "$TF_VAR_region" 2>&1); then
          case "$cluster_error" in
            *ResourceNotFoundException*|*"Cluster not found"*) cluster_available=false ;;
            *) echo "$cluster_error" >&2; exit 1 ;;
          esac
        fi
        if [[ "$cluster_available" == true ]]; then
          aws eks update-kubeconfig --name "$cluster" --region "$TF_VAR_region" >/dev/null
        fi
        ;;
      gcp)
        if ! cluster_error=$(gcloud container clusters describe "$cluster" --zone "$TF_VAR_zone" --project "$GCP_PROJECT_ID" --quiet 2>&1); then
          case "$cluster_error" in
            *NOT_FOUND*|*"not found"*) cluster_available=false ;;
            *) echo "$cluster_error" >&2; exit 1 ;;
          esac
        fi
        if [[ "$cluster_available" == true ]]; then
          gcloud container clusters get-credentials "$cluster" --zone "$TF_VAR_zone" --project "$GCP_PROJECT_ID" --quiet >/dev/null
        fi
        ;;
    esac

    if [[ "$cluster_available" == true ]] && helm status fleet-manager --namespace "$namespace" >/dev/null 2>&1; then
      manager_id=$(helm get values fleet-manager --namespace "$namespace" --all --output json | jq -er '.manager.id')
      helm uninstall fleet-manager --namespace "$namespace" --wait
      case "$cloud" in
        aws)
          profile=$(/tmp/terraform output -raw runner_instance_profile_name)
          profile_arn=$(aws iam get-instance-profile --instance-profile-name "$profile" --query 'InstanceProfile.Arn' --output text)
          ids=$(aws ec2 describe-instances --filters "Name=tag:superplane_fleet_manager_id,Values=$manager_id" "Name=iam-instance-profile.arn,Values=$profile_arn" 'Name=instance-state-name,Values=pending,running,stopping,stopped' --query 'Reservations[].Instances[].InstanceId' --output text)
          if [[ -n "$ids" ]]; then
            read -r -a instance_ids <<< "$ids"
            aws ec2 terminate-instances --instance-ids "${instance_ids[@]}" >/dev/null
            aws ec2 wait instance-terminated --instance-ids "${instance_ids[@]}"
          fi
          ;;
        gcp)
          instances=$(gcloud compute instances list --project "$GCP_PROJECT_ID" --filter="labels.superplane_fleet_manager_id=$manager_id" --format='value(name,zone.basename())')
          while read -r name zone; do
            [[ -n "$name" ]] || continue
            gcloud compute instances delete "$name" --zone="$zone" --project "$GCP_PROJECT_ID" --quiet
          done <<< "$instances"
          ;;
      esac
    fi
  fi
fi

/tmp/terraform destroy -auto-approve -input=false -no-color
# Keep the project artifact until the destroy has completed successfully.
trap - EXIT
artifact yank project "$state_artifact" >/dev/null
