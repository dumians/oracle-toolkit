output "onprem_zdm_ip" {
  description = "The IP address of the On-Premises ZDM node VM"
  value       = var.onprem_zdm_ip
}

output "onprem_ogg_ip" {
  description = "The IP address of the On-Premises GoldenGate Hub VM"
  value       = var.onprem_ogg_ip
}

output "gcs_bucket_name" {
  description = "The name of the GCS bucket for hybrid backups"
  value       = module.storage.bucket_name
}

output "onprem_service_account_email" {
  description = "The Service Account email used by the On-Premises ZDM VM"
  value       = var.create_service_accounts ? google_service_account.onprem_zdm_sa[0].email : "zdm-onprem-sa@${var.project_id}.iam.gserviceaccount.com"
}

output "odb_network_id" {
  description = "The ID of the provisioned Oracle Database@Google Cloud ODB Network"
  value       = var.create_odb_infrastructure ? module.gcp_odb_network[0].odb_network_id : ""
}

output "odb_db_system_id" {
  description = "The ID of the provisioned Base DB System (DBCS)"
  value       = (var.target_type == "dbcs" && var.create_target_dbsystem) ? module.gcp_dbsystem[0].db_system_id : ""
}

output "odb_exadata_vm_cluster_id" {
  description = "The ID of the provisioned Exadata VM Cluster"
  value       = (var.target_type == "exacs" && var.create_target_exadata) ? module.gcp_exadata_vmcluster[0].vm_cluster_id : ""
}

output "odb_autonomous_database_id" {
  description = "The ID of the provisioned Autonomous Database"
  value       = (var.target_type == "adb" && var.create_target_adb) ? module.gcp_adb[0].autonomous_database_id : ""
}
