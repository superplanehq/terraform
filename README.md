# SuperPlane Installation with Terraform

Terraform configurations to deploy [SuperPlane](https://github.com/superplanehq/superplane) on
managed Kubernetes clusters. Choose a platform and follow its installation guide.

## Supported Platforms

| Platform | Installation guide |
|----------|--------------------|
| Google Kubernetes Engine (GKE) | [Google Cloud](./gcp/README.md) |
| Amazon Elastic Kubernetes Service (EKS) | [AWS](./aws/README.md) |
| Azure Kubernetes Service (AKS) | [Azure](./azure/README.md) |

See the [architecture overview](./docs/architecture.md) for the resources that
these installers create.

## Requirements

- Terraform >= 1.5.0
- Cloud provider CLI (gcloud, aws, or az) authenticated
- kubectl

Each cloud directory includes a Terraform provider lock file. Keep it with
the installer so future runs use the provider versions validated for this
release.
