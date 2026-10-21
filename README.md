# SuperPlane Installation with Terraform

Terraform configurations to deploy [SuperPlane](https://github.com/superplanehq/superplane) on
managed Kubernetes clusters. Clone this repository and run Terraform from the
cloud directory that you choose.

## Supported Platforms

| Platform | Directory | Status |
|----------|-----------|--------|
| Google Kubernetes Engine (GKE) | [`gcp/`](./gcp/) | Ready |
| Amazon Elastic Kubernetes Service (EKS) | [`aws/`](./aws/) | Ready |
| Azure Kubernetes Service (AKS) | [`azure/`](./azure/) | Ready |

## Quick Start

```bash
git clone https://github.com/superplanehq/terraform.git
cd terraform
```

### Google Cloud (GKE)

```bash
cd gcp
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars

terraform init
terraform apply
```

See [`gcp/README.md`](./gcp/README.md) for full instructions.

### AWS (EKS)

```bash
cd aws
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars

terraform init
terraform apply
```

See [`aws/README.md`](./aws/README.md) for full instructions.

### Azure (AKS)

```bash
cd azure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars

terraform init
terraform apply
```

See [`azure/README.md`](./azure/README.md) for full instructions.

Each cloud directory includes a Terraform provider lock file. Keep it with
the installer so future runs use the provider versions validated for this
release.

## What Gets Created

Each deployment creates:

- **Kubernetes cluster** (GKE, EKS, or AKS)
- **Managed PostgreSQL database** (Cloud SQL, RDS, or Flexible Server)
- **VPC networking** with private subnets for database
- **Load balancer** for ingress
- **cert-manager** for automatic SSL certificates
- **SuperPlane** application deployment

The AKS stack also creates Azure Blob storage, a runner subnet, and a Compute Gallery.

## Requirements

- Terraform >= 1.5.0
- Cloud provider CLI (gcloud, aws, or az) authenticated
- kubectl

## Checks

Run these commands from the repository root:

```bash
terraform fmt -check -recursive
for cloud in aws gcp azure; do
  terraform -chdir="$cloud" init -backend=false
  terraform -chdir="$cloud" validate
done
```

`terraform init` downloads providers. Validation does not call cloud APIs.

## Architecture

```
                    ┌─────────────────┐
                    │    Internet     │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  Load Balancer  │
                    │  (GCE/ALB/Azure)│
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │        Kubernetes Cluster             │
         │                   │                   │
         │          ┌────────▼────────┐          │
         │          │   SuperPlane    │          │
         │          └────────┬────────┘          │
         │                   │                   │
         └───────────────────┼───────────────────┘
                             │
                    ┌────────▼────────┐
                    │   PostgreSQL    │
                    │ Cloud SQL/RDS/  │
                    │ Flexible Server │
                    └─────────────────┘
```
