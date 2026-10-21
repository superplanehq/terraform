# Architecture

Each Terraform installer creates infrastructure for SuperPlane on a managed
Kubernetes cluster. The load balancer routes traffic to SuperPlane. SuperPlane
uses a managed PostgreSQL database outside the cluster.

```text
                    ┌─────────────────┐
                    │    Internet     │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  Load Balancer  │
                    │  (GCE/NLB/Azure)│
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │        Kubernetes Cluster             │
         │                   │                   │
         │          ┌────────▼────────┐          │
         │          │   SuperPlane    │          │
         │          └────────┬────────┘          │
         └───────────────────┼───────────────────┘
                             │
                    ┌────────▼────────┐
                    │   PostgreSQL    │
                    │ Cloud SQL/RDS/  │
                    │ Flexible Server │
                    └─────────────────┘
```

Each installer creates:

- A Kubernetes cluster (GKE, EKS, or AKS)
- A managed PostgreSQL database (Cloud SQL, RDS, or Flexible Server)
- Private network access to the database
- A load balancer for ingress
- cert-manager for TLS certificates
- A SuperPlane application deployment

The AKS installer also creates Azure Blob storage, a runner subnet, and a
Compute Gallery.
