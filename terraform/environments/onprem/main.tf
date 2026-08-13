terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# 1. GCP Networking Setup for Hybrid Connectivity
module "networking" {
  source            = "../../modules/networking"
  project_id        = var.project_id
  region            = var.region
  create_networking = var.create_networking
  network_name      = "zdm-onprem-hybrid-vpc"
  subnet_name       = "zdm-onprem-hybrid-subnet"
  subnet_cidr       = "10.160.0.0/20"
  source_db_ips     = concat(var.source_db_ips, [var.onprem_zdm_ip], var.deploy_goldengate ? [var.onprem_ogg_ip] : [])
  create_odb_subnet = var.target_type != "gce" ? true : false
  odb_subnet_cidr   = var.odb_subnet_cidr

  target_db_ips = (
    var.target_type == "exacs" ? var.exacs_target_node_ips :
    var.target_type == "dbcs" ? var.dbcs_target_db_ips :
    var.target_db_ips
  )
}

# 2. Service Account & Workload Identity Federation for On-Premises Node Keyless Authentication
resource "google_service_account" "onprem_zdm_sa" {
  count        = var.create_service_accounts ? 1 : 0
  account_id   = "zdm-onprem-sa"
  display_name = "Service Account for On-Premises ZDM and GoldenGate Nodes"
  project      = var.project_id
}

# Pillar 2: GCP Workload Identity Pool for Keyless On-Premises Access
resource "google_iam_workload_identity_pool" "onprem_pool" {
  count                     = var.create_service_accounts ? 1 : 0
  workload_identity_pool_id = "zdm-onprem-wif-pool"
  display_name              = "On-Premises ZDM & OGG Workload Identity Pool"
  description               = "Identity pool for keyless authentication of on-premises migration nodes to GCS"
  project                   = var.project_id
}

resource "google_iam_workload_identity_pool_provider" "onprem_provider" {
  count                              = var.create_service_accounts ? 1 : 0
  workload_identity_pool_id          = google_iam_workload_identity_pool.onprem_pool[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "zdm-onprem-oidc-provider"
  display_name                       = "On-Premises OIDC Identity Provider"
  project                            = var.project_id
  attribute_mapping = {
    "google.subject" = "assertion.sub"
    "attribute.aud"  = "assertion.aud"
  }
  oidc {
    issuer_uri = "https://accounts.google.com"
  }
}

module "storage" {
  source                    = "../../modules/storage"
  project_id                = var.project_id
  region                    = var.region
  bucket_name               = var.bucket_name
  create_bucket             = var.create_bucket
  zdm_service_account_email = var.create_service_accounts ? google_service_account.onprem_zdm_sa[0].email : "zdm-onprem-sa@${var.project_id}.iam.gserviceaccount.com"
}

# Generate Service Account Key for On-Premises Authentication (Fallback)
resource "google_service_account_key" "onprem_sa_key" {
  count              = var.create_service_accounts ? 1 : 0
  service_account_id = google_service_account.onprem_zdm_sa[0].name
}

# 3. Generate On-Premises VM Bootstrap Setup Script
resource "local_file" "onprem_setup_script" {
  filename = "${path.module}/setup_onprem_zdm_ogg.sh"
  content  = <<EOF
#!/usr/bin/env bash
# On-Premises ZDM & GoldenGate VM Bootstrap Setup Script
# Generated automatically by Terraform for Project: ${var.project_id}

set -euo pipefail

echo "================================================================="
echo "=== Setting up On-Premises ZDM & GoldenGate Hub (${var.onprem_zdm_ip}) ==="
echo "================================================================="

# 1. Install Prerequisites (Docker / Podman / gcloud CLI)
sudo yum update -y || sudo apt-get update -y
sudo yum install -y curl unzip wget python3 podman || sudo apt-get install -y curl unzip wget python3 podman

# 2. Configure GCP Service Account Credentials
mkdir -p /u01/zdm/config /u01/zdm/zdmbase
cat <<'KEYEOF' > /u01/zdm/config/gcp_sa_key.json
${var.create_service_accounts ? base64decode(google_service_account_key.onprem_sa_key[0].private_key) : "{}"}
KEYEOF

chmod 600 /u01/zdm/config/gcp_sa_key.json
export GOOGLE_APPLICATION_CREDENTIALS=/u01/zdm/config/gcp_sa_key.json

# 3. Configure GCS Bucket Access
echo "Target GCS Bucket: gs://${var.bucket_name}"

# 4. GoldenGate Setup (if enabled)
if [ "${var.deploy_goldengate}" == "true" ]; then
  echo "Setting up On-Premises GoldenGate Microservices Container..."
  podman run -d --name ogg23ai \
    -p 9011:9011 -p 9012:9012 -p 9013:9013 \
    -v /u01/goldengate/deployments:/u01/app/ogg/deployments \
    -e OGG_ADMIN_USER=oggadmin \
    -e OGG_ADMIN_PWD=SecretPassword123# \
    container-registry.oracle.com/database/goldengate:latest || true
fi

echo "✓ On-Premises ZDM and GoldenGate environment initialized."
EOF
}

# 4. Optional Oracle Database@Google Cloud Infrastructure Modules
module "gcp_odb_network" {
  count           = var.create_odb_infrastructure ? 1 : 0
  source          = "../../modules/gcp_odb_network"
  network_name    = module.networking.network_name
  vpc_project     = var.project_id
  odb_network_id  = var.odb_network_id
  location        = var.region
  gcp_oracle_zone = var.zone
}

module "gcp_odb_client_subnet" {
  count             = var.create_odb_infrastructure ? 1 : 0
  source            = "../../modules/gcp_odb_subnet"
  odb_subnet_id     = var.odb_client_subnet_id
  location          = var.region
  vpc_project       = var.project_id
  odb_network_id    = var.create_odb_infrastructure ? module.gcp_odb_network[0].odb_network_id : var.odb_network_id
  subnet_cidr_range = var.odb_client_subnet_cidr
  subnet_purpose    = "CLIENT_SUBNET"
}

module "gcp_odb_backup_subnet" {
  count             = (var.create_odb_infrastructure && var.create_target_exadata) ? 1 : 0
  source            = "../../modules/gcp_odb_subnet"
  odb_subnet_id     = var.odb_backup_subnet_id
  location          = var.region
  vpc_project       = var.project_id
  odb_network_id    = var.create_odb_infrastructure ? module.gcp_odb_network[0].odb_network_id : var.odb_network_id
  subnet_cidr_range = var.odb_backup_subnet_cidr
  subnet_purpose    = "BACKUP_SUBNET"
}

module "gcp_dbsystem" {
  count            = (var.target_type == "dbcs" && var.create_target_dbsystem) ? 1 : 0
  source           = "../../modules/gcp_dbsystem"
  db_system_id     = var.db_system_id
  location         = var.region
  gcp_oracle_zone  = var.zone
  dbsystem_project = var.project_id
  vpc_project      = var.project_id
  odb_network_id   = var.create_odb_infrastructure ? module.gcp_odb_network[0].odb_network_id : var.odb_network_id
  odb_subnet_id    = var.create_odb_infrastructure ? module.gcp_odb_client_subnet[0].odb_subnet_id : var.odb_client_subnet_id
  ssh_public_keys  = ["ssh-rsa MOCK_KEY"]
  hostname_prefix  = "dbcs-tgt"
  admin_pw         = var.db_admin_pw
  tde_pw           = var.tde_pw
}

module "gcp_exadata_infra" {
  count                           = (var.target_type == "exacs" && var.create_target_exadata) ? 1 : 0
  source                          = "../../modules/gcp_exadata_infra"
  location                        = var.region
  exa_infra_project               = var.project_id
  cloud_exadata_infrastructure_id = var.cloud_exadata_infrastructure_id
  gcp_oracle_zone                 = var.zone
}

module "gcp_exadata_vmcluster" {
  count                           = (var.target_type == "exacs" && var.create_target_exadata) ? 1 : 0
  source                          = "../../modules/gcp_exadata_vmcluster"
  location                        = var.region
  exa_infra_project               = var.project_id
  exa_vm_project                  = var.project_id
  vpc_project                     = var.project_id
  cloud_exadata_infrastructure_id = var.create_target_exadata ? module.gcp_exadata_infra[0].exadata_infrastructure_id : var.cloud_exadata_infrastructure_id
  cloud_vm_cluster_id             = var.cloud_vm_cluster_id
  odb_network_id                  = var.create_odb_infrastructure ? module.gcp_odb_network[0].odb_network_id : var.odb_network_id
  odb_client_subnet_id            = var.create_odb_infrastructure ? module.gcp_odb_client_subnet[0].odb_subnet_id : var.odb_client_subnet_id
  odb_backup_subnet_id            = (var.create_odb_infrastructure && var.create_target_exadata) ? module.gcp_odb_backup_subnet[0].odb_subnet_id : var.odb_backup_subnet_id
  ssh_public_keys                 = ["ssh-rsa MOCK_KEY"]
  hostname_prefix                 = "exacs-tgt"
}

module "gcp_adb" {
  count                  = (var.target_type == "adb" && var.create_target_adb) ? 1 : 0
  source                 = "../../modules/gcp_adb"
  autonomous_database_id = var.autonomous_database_id
  location               = var.region
  adb_project            = var.project_id
  adb_admin_pw           = var.adb_admin_pw
  vpc_project            = var.project_id
  odb_network_id         = var.create_odb_infrastructure ? module.gcp_odb_network[0].odb_network_id : var.odb_network_id
  odb_subnet_id          = var.create_odb_infrastructure ? module.gcp_odb_client_subnet[0].odb_subnet_id : var.odb_client_subnet_id
}
