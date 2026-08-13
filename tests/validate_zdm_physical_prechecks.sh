#!/bin/bash
# Pre-checks script to run on the ZDM VM for Physical Migrations (Data Guard)

echo "=== ZDM Physical Migration Connectivity Pre-checks ==="

# 1. Verify ZDM Home Environment
if [ -z "$ZDM_HOME" ] || [ -z "$ZDM_BASE" ]; then
  echo "❌ ERROR: ZDM_HOME or ZDM_BASE is not defined. Ensure you run as zdmuser."
  exit 1
fi
echo "✓ ZDM Environment detected: ZDM_HOME=$ZDM_HOME"

# 2. Check ZDM Service Daemon
if ! $ZDM_HOME/bin/zdmservice status | grep -q "active"; then
  echo "❌ ERROR: ZDM Daemon service is not running. Start with: zdmservice start"
  exit 1
fi
echo "✓ ZDM service is active."

# 3. Check TCP/IP listeners (Port 1521)
# Usage: ./validate_zdm_physical_prechecks.sh <source_ip> <target_ip>
SOURCE_IP=$1
TARGET_IP=$2

if [ -z "$SOURCE_IP" ] || [ -z "$TARGET_IP" ]; then
  echo "⚠️ WARNING: Source/Target IPs not provided. Skipping TCP socket tests."
  echo "   Usage: $0 <source_db_ip> <target_db_ip> <gcs_bucket>"
  exit 1
fi

GCS_BUCKET=$3

echo "Testing network connectivity on port 1521 (SQL*Net)..."
if timeout 3 bash -c "cat < /dev/tcp/$SOURCE_IP/1521" &>/dev/null; then
  echo "✓ Network connection to Source Database $SOURCE_IP:1521 is OPEN."
else
  echo "❌ ERROR: Cannot reach Source Database on $SOURCE_IP:1521."
  exit 1
fi

if timeout 3 bash -c "cat < /dev/tcp/$TARGET_IP/1521" &>/dev/null; then
  echo "✓ Network connection to Target Database $TARGET_IP:1521 is OPEN."
else
  echo "❌ ERROR: Cannot reach Target Database on $TARGET_IP:1521."
  exit 1
fi

# 4. Verify SSH Connection
echo "Testing passwordless SSH key connections..."
if ssh -o BatchMode=yes -o ConnectTimeout=3 oracle@$SOURCE_IP "echo '✓ Connection successful'" &>/dev/null; then
  echo "✓ SSH access to Source DB server (oracle@$SOURCE_IP) is working."
else
  echo "❌ ERROR: Passwordless SSH connection to oracle@$SOURCE_IP failed."
  exit 1
fi

if ssh -o BatchMode=yes -o ConnectTimeout=3 oracle@$TARGET_IP "echo '✓ Connection successful'" &>/dev/null; then
  echo "✓ SSH access to Target DB server (oracle@$TARGET_IP) is working."
else
  echo "❌ ERROR: Passwordless SSH connection to oracle@$TARGET_IP failed."
  exit 1
fi

# 5. Check GCS Storage Access
if [ -n "$GCS_BUCKET" ]; then
  echo "Testing Cloud Storage access (gsutil)..."
  if gsutil ls "$GCS_BUCKET" &>/dev/null; then
    echo "✓ Cloud Storage bucket access to $GCS_BUCKET is successful."
  else
    echo "❌ ERROR: Cannot access GCS bucket $GCS_BUCKET. Check IAM credentials."
    exit 1
  fi
fi

echo "=== All Connectivity Pre-checks Passed Successfully ==="
exit 0
