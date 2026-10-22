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
      : "${AWS_DOMAIN_NAME:?Set AWS_DOMAIN_NAME}"
      : "${LETSENCRYPT_EMAIL:?Set LETSENCRYPT_EMAIL}"
      configure_aws_credentials
      actual_account=$(aws sts get-caller-identity --query Account --output text)
      [[ "$actual_account" == "$AWS_ACCOUNT_ID" ]] || { echo "AWS account mismatch" >&2; exit 1; }
      export TF_VAR_region="${AWS_REGION:-us-east-1}"
      export TF_VAR_domain_name="$AWS_DOMAIN_NAME"
      export TF_VAR_letsencrypt_email="$LETSENCRYPT_EMAIL"
      export TF_VAR_rds_deletion_protection=false
      export TF_VAR_rds_skip_final_snapshot=true
      export TF_VAR_blob_bucket_force_destroy=true
      # Use the newest public runner AMI for each architecture in this region.
      for architecture in x86_64 arm64; do
        image_id=$(aws ec2 describe-images \
          --region "$TF_VAR_region" \
          --owners 802589444644 \
          --filters 'Name=name,Values=superplane-runner-*' 'Name=is-public,Values=true' 'Name=state,Values=available' "Name=architecture,Values=$architecture" \
          --query 'sort_by(Images,&CreationDate)[-1].ImageId' \
          --output text)
        if [[ ! "$image_id" =~ ^ami-[0-9a-f]+$ ]]; then
          echo "No public SuperPlane runner AMI for $architecture in $TF_VAR_region" >&2
          exit 1
        fi
        case "$architecture" in
          x86_64) export TF_VAR_runner_image_amd64="$image_id" ;;
          arm64) export TF_VAR_runner_image_arm64="$image_id" ;;
        esac
      done
      echo "Runner AMIs: amd64=$TF_VAR_runner_image_amd64 arm64=$TF_VAR_runner_image_arm64"
      ;;
    gcp)
      : "${GCP_PROJECT_ID:?Set GCP_PROJECT_ID}"
      : "${GCP_DOMAIN_NAME:?Set GCP_DOMAIN_NAME}"
      : "${GCP_STATIC_IP_NAME:?Set GCP_STATIC_IP_NAME}"
      : "${LETSENCRYPT_EMAIL:?Set LETSENCRYPT_EMAIL}"
      configure_gcp_credentials
      gcloud config set project "$GCP_PROJECT_ID" --quiet >/dev/null
      export TF_VAR_project_id="$GCP_PROJECT_ID"
      export TF_VAR_zone="${GCP_ZONE:-us-central1-a}"
      export TF_VAR_domain_name="$GCP_DOMAIN_NAME"
      export TF_VAR_static_ip_name="$GCP_STATIC_IP_NAME"
      export TF_VAR_letsencrypt_email="$LETSENCRYPT_EMAIL"
      export TF_VAR_gke_deletion_protection=false
      export TF_VAR_sql_deletion_protection=false
      export TF_VAR_blob_bucket_force_destroy=true
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
trap save_state EXIT

# A state already in the project store belongs to an existing test install.
# Do not start from an empty local state and risk creating a second install.
if artifact pull project "$state_artifact" --destination existing.tfstate 2>artifact-error.log; then
  echo "State already exists for $cloud. Destroy it before installing again." >&2
  exit 1
elif ! grep -Eiq 'not found|404' artifact-error.log; then
  cat artifact-error.log >&2
  echo "Cannot check project state artifact for $cloud" >&2
  exit 1
fi

/tmp/terraform init -input=false -no-color
/tmp/terraform apply -auto-approve -input=false -no-color
save_state
trap - EXIT

echo
echo "Terraform state: Semaphore project artifact $state_artifact"
case "$cloud" in
  aws)
    echo "Cluster: $(/tmp/terraform output -raw cluster_name)"
    echo "Region: $TF_VAR_region"
    echo "Domain: $AWS_DOMAIN_NAME"
    ;;
  gcp)
    echo "Cluster: $(/tmp/terraform output -raw cluster_name)"
    echo "Project: $GCP_PROJECT_ID"
    echo "Zone: $TF_VAR_zone"
    echo "App URL: $(/tmp/terraform output -raw superplane_url)"
    ;;
esac
echo "Next steps: https://github.com/superplanehq/terraform/blob/main/docs/ephemeral-environments.md#$cloud"
