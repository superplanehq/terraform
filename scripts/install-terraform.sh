#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/terraform-auth.sh"

cloud=${1:?cloud is required}
case "$cloud" in aws|gcp) ;; *) echo "Unsupported cloud: $cloud" >&2; exit 2 ;; esac
state_artifact="terraform-install-tests/$cloud.tfstate"

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
      export TF_VAR_enable_gcs_blob_storage=true
      export TF_VAR_enable_runners=true
      ;;
  esac
}

save_state() {
  if [[ -s terraform.tfstate ]]; then
    mkdir -p terraform-install-tests
    cp terraform.tfstate "terraform-install-tests/$cloud.tfstate"
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
