# -----------------------------------------------------------------------------
# Runners
# -----------------------------------------------------------------------------

locals {
  fleet_manager_service_account_name = "superplane-fleet-manager"
  runner_network_tag                 = "superplane-runner"
  runner_zones                       = length(var.runner_zones) > 0 ? var.runner_zones : [var.zone]
}

resource "google_compute_subnetwork" "runners" {
  name                     = "${var.cluster_name}-runners"
  region                   = var.region
  network                  = google_compute_network.superplane.id
  ip_cidr_range            = var.runner_subnet_cidr
  private_ip_google_access = true

  lifecycle {
    precondition {
      condition     = trimspace(var.runner_image_amd64) != ""
      error_message = "Set runner_image_amd64 to a Packer-built image (projects/PROJECT/global/images/IMAGE_NAME)."
    }
  }
}

# Runner VMs have no external IP. With private nodes, the cluster NAT already
# covers all subnetworks in the region.
resource "google_compute_router" "runners" {
  count   = var.enable_private_nodes ? 0 : 1
  name    = "${var.cluster_name}-runners-router"
  region  = var.region
  network = google_compute_network.superplane.id
}

resource "google_compute_router_nat" "runners" {
  count                              = var.enable_private_nodes ? 0 : 1
  name                               = "${var.cluster_name}-runners-nat"
  router                             = google_compute_router.runners[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.runners.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Runners only make outbound connections. This rule takes priority over
# any future ingress rules for the installation VPC.
resource "google_compute_firewall" "runners_deny_ingress" {
  name        = "${var.cluster_name}-runners-deny-ingress"
  network     = google_compute_network.superplane.id
  direction   = "INGRESS"
  priority    = 900
  target_tags = [local.runner_network_tag]

  source_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }
}

resource "google_service_account" "fleet_manager" {
  account_id   = "${local.service_account_prefix}-fleet-mgr"
  display_name = "SuperPlane Fleet Manager"
}

resource "google_project_iam_member" "fleet_manager_instance_admin" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.fleet_manager.email}"
}

resource "google_service_account_iam_member" "fleet_manager_workload_identity" {
  service_account_id = google_service_account.fleet_manager.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.superplane_namespace}/${local.fleet_manager_service_account_name}]"

  # The workload identity pool exists only after the cluster exists.
  depends_on = [google_container_cluster.superplane]
}

moved {
  from = google_compute_subnetwork.runners[0]
  to   = google_compute_subnetwork.runners
}

moved {
  from = google_compute_firewall.runners_deny_ingress[0]
  to   = google_compute_firewall.runners_deny_ingress
}

moved {
  from = google_service_account.fleet_manager[0]
  to   = google_service_account.fleet_manager
}

moved {
  from = google_project_iam_member.fleet_manager_instance_admin[0]
  to   = google_project_iam_member.fleet_manager_instance_admin
}

moved {
  from = google_service_account_iam_member.fleet_manager_workload_identity[0]
  to   = google_service_account_iam_member.fleet_manager_workload_identity
}
