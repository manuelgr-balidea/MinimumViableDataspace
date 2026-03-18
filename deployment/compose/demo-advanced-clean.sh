#!/bin/bash

#
#  Copyright (c) 2024 Contributors to the Eclipse Foundation
#
#  See the NOTICE file(s) distributed with this work for additional
#  information regarding copyright ownership.
#
#  This program and the accompanying materials are made available under the
#  terms of the Apache License, Version 2.0 which is available at
#  https://www.apache.org/licenses/LICENSE-2.0
#
#  SPDX-License-Identifier: Apache-2.0
#

set -euo pipefail

cd "$(dirname "$0")/../.."

for cmd in bash curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: '$cmd' is required but not installed."
    exit 1
  fi
done

CP_QNA="${CP_QNA:-http://localhost:8191}"
IH_CONSUMER="${IH_CONSUMER:-http://localhost:7081}"
API_KEY_CP="${API_KEY_CP:-password}"
API_KEY_IH="${API_KEY_IH:-c3VwZXItdXNlcg==.c3VwZXItc2VjcmV0LWtleQo=}"

PARTICIPANT_CONTEXT_B64="${PARTICIPANT_CONTEXT_B64:-ZGlkOndlYjpjb25zdW1lci1pZGVudGl0eWh1YiUzQTcwODM6Y29uc3VtZXI=}"
ISSUER_DID="${ISSUER_DID:-did:web:dataspace-issuer-service%3A10016:issuer}"

ASSET_ID="${ASSET_ID:-asset-membership-demo-1}"
POLICY_ID="${POLICY_ID:-require-membership-demo}"
DEF_ID="${DEF_ID:-membership-demo-def}"

CREDENTIAL_TYPE="${CREDENTIAL_TYPE:-FoobarCredential}"
CREDENTIAL_DEF_ID="${CREDENTIAL_DEF_ID:-demo-credential-def-2}"
REQUEST_ID="${REQUEST_ID:-cred-demo-$(date +%s)}"

POLL_ATTEMPTS="${POLL_ATTEMPTS:-12}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-2}"

SKIP_CLEANUP="${SKIP_CLEANUP:-false}"

delete_resource() {
  local path="$1"
  local label="$2"

  local response_file
  response_file="$(mktemp)"

  local http_code
  http_code="$(curl -s -o "$response_file" -w "%{http_code}" -X DELETE \
    "$CP_QNA/api/management/v3/$path" \
    -H "x-api-key: $API_KEY_CP")"

  case "$http_code" in
    200|204|404)
      echo "[OK] $label (HTTP $http_code)"
      ;;
    409)
      echo "[WARN] $label not deleted due to conflict (HTTP 409)"
      cat "$response_file"
      ;;
    *)
      echo "[ERROR] $label delete failed (HTTP $http_code)"
      cat "$response_file"
      rm -f "$response_file"
      return 1
      ;;
  esac

  rm -f "$response_file"
}

echo
echo "==> Running advanced demo flow"

set +e
CP_QNA="$CP_QNA" \
IH_CONSUMER="$IH_CONSUMER" \
API_KEY_CP="$API_KEY_CP" \
API_KEY_IH="$API_KEY_IH" \
PARTICIPANT_CONTEXT_B64="$PARTICIPANT_CONTEXT_B64" \
ISSUER_DID="$ISSUER_DID" \
ASSET_ID="$ASSET_ID" \
POLICY_ID="$POLICY_ID" \
DEF_ID="$DEF_ID" \
CREDENTIAL_TYPE="$CREDENTIAL_TYPE" \
CREDENTIAL_DEF_ID="$CREDENTIAL_DEF_ID" \
REQUEST_ID="$REQUEST_ID" \
POLL_ATTEMPTS="$POLL_ATTEMPTS" \
POLL_INTERVAL_SECONDS="$POLL_INTERVAL_SECONDS" \
bash ./deployment/compose/demo-advanced.sh
DEMO_EXIT="$?"
set -e

if [[ "$DEMO_EXIT" -ne 0 ]]; then
  echo "[WARN] Advanced demo flow failed with exit code $DEMO_EXIT. Cleanup will still run."
fi

CLEANUP_EXIT=0

if [[ "$SKIP_CLEANUP" == "true" ]]; then
  echo "==> Cleanup skipped (SKIP_CLEANUP=true)"
else
  echo
  echo "==> Cleaning up advanced demo resources"

  delete_resource "contractdefinitions/$DEF_ID" "Delete contract definition '$DEF_ID'" || CLEANUP_EXIT=1
  delete_resource "policydefinitions/$POLICY_ID" "Delete policy '$POLICY_ID'" || CLEANUP_EXIT=1
  delete_resource "assets/$ASSET_ID" "Delete asset '$ASSET_ID'" || CLEANUP_EXIT=1
fi

echo
if [[ "$DEMO_EXIT" -ne 0 ]]; then
  echo "[ERROR] Advanced demo failed. Cleanup attempted."
  exit "$DEMO_EXIT"
fi

if [[ "$CLEANUP_EXIT" -ne 0 ]]; then
  echo "[ERROR] Cleanup failed for one or more resources."
  exit "$CLEANUP_EXIT"
fi

echo "Advanced demo + cleanup completed successfully."
