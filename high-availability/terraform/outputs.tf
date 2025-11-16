output "instance_names" {
  description = "Names of the VM instances in GCP"
  value       = google_compute_instance.example_vm.name
  
}

output "instance_external_ips" {
  description = "External IP addresses of the VM instances in GCP"
  value       = google_compute_instance.example_vm.network_interface[0].access_config[0].nat_ip
}

output "postgresql_instance_ip" {
  description = "IP address of the PostgreSQL instance in GCP"
  value       = google_sql_database_instance.example_db_instance.ip_address
}

output "gcp_project_id" {
  description = "GCP Project ID"
  value       = google_compute_instance.example_vm.project
}