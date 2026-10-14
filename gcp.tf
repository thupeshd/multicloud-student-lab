resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}
resource "google_compute_network" "lab" {
  name                    = "${var.name}-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.compute]
}
resource "google_compute_subnetwork" "lab" {
  name          = "${var.name}-subnet"
  ip_cidr_range = "10.30.1.0/24"
  network       = google_compute_network.lab.id
}
resource "google_compute_address" "lab" {
  name       = "${var.name}-ip"
  depends_on = [google_project_service.compute]
}
resource "google_compute_firewall" "http" {
  name          = "${var.name}-http"
  network       = google_compute_network.lab.name
  source_ranges = ["0.0.0.0/0"]
  target_tags   = [var.name]
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}
resource "google_compute_firewall" "ssh" {
  name          = "${var.name}-ssh"
  network       = google_compute_network.lab.name
  source_ranges = [var.admin_cidr]
  target_tags   = [var.name]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
resource "google_compute_instance" "lab" {
  name         = "${var.name}-gcp"
  machine_type = var.gcp_machine_type
  tags         = [var.name]
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = 10
      type  = "pd-standard"
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.lab.id
    access_config { nat_ip = google_compute_address.lab.address }
  }
  metadata = {
    ssh-keys               = "labadmin:${local.ssh_key}"
    block-project-ssh-keys = "true"
    enable-oslogin         = "FALSE"
  }
  metadata_startup_script = join("\n", [local.app_gcp, templatefile("${path.module}/templates/monitoring.sh.tftpl", {
    aws_ip   = aws_eip.lab.public_ip
    azure_ip = azurerm_public_ip.lab.ip_address
  })])
  labels     = { project = var.name, purpose = "student-lab" }
  depends_on = [google_compute_firewall.http, google_compute_firewall.ssh]
}
