#!/usr/bin/env bash

create_oidc_token_file() {
  : "${SEMAPHORE_OIDC_TOKEN:?Semaphore OIDC token is required}"

  local token_file
  token_file=$(mktemp)
  chmod 600 "$token_file"
  printf '%s' "$SEMAPHORE_OIDC_TOKEN" > "$token_file"
  printf '%s\n' "$token_file"
}

configure_aws_credentials() {
  : "${AWS_INSTALLER_ROLE_ARN:?Set AWS_INSTALLER_ROLE_ARN}"
  local token_file
  token_file=$(create_oidc_token_file)

  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE
  export AWS_ROLE_ARN="$AWS_INSTALLER_ROLE_ARN"
  export AWS_WEB_IDENTITY_TOKEN_FILE="$token_file"
  export AWS_DEFAULT_REGION="${AWS_REGION:-us-east-1}"
}

configure_gcp_credentials() {
  : "${GCP_WORKLOAD_IDENTITY_PROVIDER:?Set GCP_WORKLOAD_IDENTITY_PROVIDER}"
  : "${GCP_INSTALLER_SERVICE_ACCOUNT:?Set GCP_INSTALLER_SERVICE_ACCOUNT}"
  local token_file credentials_file
  token_file=$(create_oidc_token_file)

  credentials_file=$(mktemp)
  chmod 600 "$credentials_file"
  gcloud iam workload-identity-pools create-cred-config "$GCP_WORKLOAD_IDENTITY_PROVIDER" \
    --service-account="$GCP_INSTALLER_SERVICE_ACCOUNT" \
    --credential-source-file="$token_file" \
    --credential-source-type=text \
    --output-file="$credentials_file" >/dev/null
  export GOOGLE_APPLICATION_CREDENTIALS="$credentials_file"
  gcloud auth login --cred-file="$credentials_file" --quiet >/dev/null
}
