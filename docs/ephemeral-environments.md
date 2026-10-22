# Continue a Semaphore installation

The **Ephemeral Environments - Start** promotion runs Terraform under CI credentials. Each job prints its cluster details and saves its state as a Semaphore project artifact: `aws.tfstate` or `gcp.tfstate`.

From the repository root, download the state for the cloud you are using:

```bash
SEMAPHORE_PROJECT_ID=$(sem-ai project show terraform | jq -er '.metadata.id')

# AWS
sem-ai artifact get --scope projects --id "$SEMAPHORE_PROJECT_ID" \
  --path aws.tfstate --output aws/terraform.tfstate

# GCP
sem-ai artifact get --scope projects --id "$SEMAPHORE_PROJECT_ID" \
  --path gcp.tfstate --output gcp/terraform.tfstate
```

Run only the download command for your cloud. The state contains installation secrets, so keep it private. It lets you use the `terraform output` commands in the regular installation guide.

## AWS

The CI role created EKS, so your local IAM role does not automatically have Kubernetes access. Set your AWS profile, the region printed by the job, and your **IAM role ARN** (not an STS assumed-role session ARN):

```bash
export AWS_PROFILE=YOUR_AWS_PROFILE
export AWS_REGION=YOUR_AWS_REGION
export EKS_CLUSTER=superplane
export EKS_ROLE_ARN=arn:aws:iam::YOUR_ACCOUNT_ID:role/YOUR_ROLE_NAME
```

The installer creates EKS in `CONFIG_MAP` authentication mode. Enable access entries, then grant your role access:

```bash
aws eks update-cluster-config --region "$AWS_REGION" --name "$EKS_CLUSTER" \
  --access-config authenticationMode=API_AND_CONFIG_MAP
aws eks wait cluster-active --region "$AWS_REGION" --name "$EKS_CLUSTER"
aws eks create-access-entry --region "$AWS_REGION" --cluster-name "$EKS_CLUSTER" \
  --principal-arn "$EKS_ROLE_ARN" --type STANDARD
aws eks associate-access-policy --region "$AWS_REGION" --cluster-name "$EKS_CLUSTER" \
  --principal-arn "$EKS_ROLE_ARN" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

Then follow [Configure kubectl, DNS, and verification in the AWS installation guide](../aws/README.md#4-configure-kubectl). The AWS domain is printed by the promotion; create its CNAME using the Traefik hostname from that guide.

## GCP

The reserved static IP and DNS record are already configured for this test installation. Use the project and zone printed by the job, then continue at [Verify in the GCP installation guide](../gcp/README.md#verify).
