variable "name" {
  type        = string
  description = "Unique lowercase project name; also the public Traffic Manager DNS label."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{5,23}$", var.name))
    error_message = "Use 6-24 lowercase letters, digits or hyphens, starting with a letter."
  }
}
variable "admin_cidr" {
  type        = string
  description = "Your current public IPv4 address with /32."
  validation {
    condition     = can(cidrnetmask(var.admin_cidr)) && endswith(var.admin_cidr, "/32")
    error_message = "Specify one valid public IPv4 address with /32."
  }
}
variable "ssh_public_key_path" { type = string }
variable "azure_subscription_id" { type = string }
variable "gcp_project_id" { type = string }
variable "aws_region" { default = "us-east-1" }
variable "azure_location" { default = "eastus" }
variable "gcp_region" { default = "us-central1" }
variable "gcp_zone" { default = "us-central1-a" }
variable "aws_instance_type" { default = "t3.micro" }
variable "azure_vm_size" { default = "Standard_B1s" }
variable "gcp_machine_type" { default = "e2-small" }
variable "routing_method" {
  default = "Priority"
  validation {
    condition     = contains(["Priority", "Weighted"], var.routing_method)
    error_message = "Choose Priority or Weighted."
  }
}
locals {
  ssh_key   = trimspace(file(pathexpand(var.ssh_public_key_path)))
  tags      = { Project = var.name, Purpose = "student-lab" }
  app_aws   = templatefile("${path.module}/templates/app.sh.tftpl", { cloud = "AWS" })
  app_azure = templatefile("${path.module}/templates/app.sh.tftpl", { cloud = "Azure" })
  app_gcp   = templatefile("${path.module}/templates/app.sh.tftpl", { cloud = "GCP" })
}
