#!/bin/bash
set -e

echo "=== Starting Terraform Code Validation ==="

ENV_DIRS=(
  "environments/gce"
  "environments/gke"
  "environments/onprem"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

for env in "${ENV_DIRS[@]}"; do
  echo "--------------------------------------------------"
  echo "Validating environment: $env"
  echo "--------------------------------------------------"
  cd "$ROOT_DIR/$env"
  
  # Initialize Terraform in read-only / no-backend mode
  terraform init -backend=false
  
  # Run validation check
  terraform validate
  
  # Run a dry-run plan using the mock tfvars
  echo "Running plan dry-run check..."
  if [ "$env" == "environments/gce" ]; then
    terraform plan -var-file="$ROOT_DIR/tests/mock.tfvars" -var="target_type=gce" -refresh=false > /dev/null
  elif [ "$env" == "environments/gke" ]; then
    terraform plan -var-file="$ROOT_DIR/tests/mock.tfvars" -var="target_type=adb-s" -refresh=false > /dev/null
  elif [ "$env" == "environments/onprem" ]; then
    terraform plan -var-file="$ROOT_DIR/tests/mock.tfvars" -var="target_type=dbcs" -refresh=false > /dev/null
  fi
  
  echo "  [✓] $env is valid."
done

echo "=================================================="
echo "=== All Terraform environments validated successfully! ==="
echo "=================================================="
