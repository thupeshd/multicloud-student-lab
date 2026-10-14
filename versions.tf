terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    google  = { source = "hashicorp/google", version = "~> 7.0" }
  }
}
provider "aws" { region = var.aws_region }
provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}
provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  zone    = var.gcp_zone
}
