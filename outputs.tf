output "app_url" { value = "http://${azurerm_traffic_manager_profile.lab.fqdn}" }
output "aws_ip" { value = aws_eip.lab.public_ip }
output "azure_ip" { value = azurerm_public_ip.lab.ip_address }
output "gcp_ip" { value = google_compute_address.lab.address }
output "monitoring_tunnel" {
  value = "ssh -i ~/.ssh/multicloud-lab -L 3000:127.0.0.1:3000 -L 9090:127.0.0.1:9090 -L 9093:127.0.0.1:9093 labadmin@${google_compute_address.lab.address} -N"
}
