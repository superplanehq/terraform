resource "google_compute_network" "superplane" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "gke" {
  name                     = "${var.cluster_name}-gke"
  region                   = var.region
  network                  = google_compute_network.superplane.id
  ip_cidr_range            = var.gke_subnet_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "${var.cluster_name}-pods"
    ip_cidr_range = var.gke_pods_cidr
  }

  secondary_ip_range {
    range_name    = "${var.cluster_name}-services"
    ip_cidr_range = var.gke_services_cidr
  }
}
