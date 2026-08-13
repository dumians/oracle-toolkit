#!/bin/bash
# Pre-checks script to run on the ZDM VM for Logical Migrations (Data Pump + GoldenGate)

echo "=== ZDM Logical Migration Connectivity Pre-checks ==="

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

# 3. Check TCP/IP Connection parameters
# Usage: ./validate_zdm_logical_prechecks.sh <source_ip> <target_adb_endpoint> <wallet_path> <gcs_bucket>
SOURCE_IP=$1
TARGET_ADB=$2
WALLET_PATH=$3
GCS_BUCKET=$4

if [ -z "$SOURCE_IP" ] || [ -z "$TARGET_ADB" ]; then
  echo "⚠️ WARNING: Connection endpoints not provided. Skipping TCP socket tests."
  echo "   Usage: $0 <source_db_ip> <target_adb_endpoint_or_ip> <wallet_directory_path> <gcs_bucket>"
  exit 1
fi

echo "Testing network connectivity on port 1521 (Source SQL*Net)..."
if timeout 3 bash -c "cat < /dev/tcp/$SOURCE_IP/1521" &>/dev/null; then
  echo "✓ Network connection to Source Database $SOURCE_IP:1521 is OPEN."
else
  echo "❌ ERROR: Cannot reach Source Database on $SOURCE_IP:1521."
  exit 1
fi

echo "Testing network connectivity on port 1522 (Target TCPS SQL*Net)..."
if timeout 3 bash -c "cat < /dev/tcp/$TARGET_ADB/1522" &>/dev/null; then
  echo "✓ Network connection to Target Autonomous DB on $TARGET_ADB:1522 is OPEN."
else
  echo "❌ ERROR: Cannot reach Target Database on $TARGET_ADB:1522. Ensure egress and interconnect rules allow TCPS."
  exit 1
fi

# 4. Check target mTLS credentials wallet
if [ -n "$WALLET_PATH" ]; then
  echo "Checking Client Credentials Wallet..."
  if [ -f "$WALLET_PATH/cwallet.sso" ]; then
    echo "✓ Target database wallet (cwallet.sso) found in $WALLET_PATH."
  else
    echo "❌ ERROR: Wallet file cwallet.sso not found in directory $WALLET_PATH."
    exit 1
  fi
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
