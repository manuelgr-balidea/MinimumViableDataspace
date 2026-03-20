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

for cmd in curl jq; do
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
ACCESS_POLICY_ID="${ACCESS_POLICY_ID:-${POLICY_ID:-require-membership-demo}}"
CONTRACT_POLICY_ID="${CONTRACT_POLICY_ID:-${POLICY_ID_CONTRACT:-require-dataprocessor-demo}}"
DEF_ID="${DEF_ID:-membership-demo-def}"

CREDENTIAL_TYPE="${CREDENTIAL_TYPE:-FoobarCredential}"
CREDENTIAL_DEF_ID="${CREDENTIAL_DEF_ID:-demo-credential-def-2}"
REQUEST_ID="${REQUEST_ID:-cred-demo-$(date +%s)}"

POLL_ATTEMPTS="${POLL_ATTEMPTS:-12}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-2}"

post_json_accept_conflict() {
  local url="$1"
  local key="$2"
  local payload="$3"
  local label="$4"

  local response_file
  response_file="$(mktemp)"

  local http_code
  http_code="$(curl -s -o "$response_file" -w "%{http_code}" -X POST "$url" \
    -H 'Content-Type: application/json' \
    -H "x-api-key: $key" \
    -d "$payload")"

  if [[ "$http_code" == "200" || "$http_code" == "201" || "$http_code" == "204" || "$http_code" == "409" ]]; then
    echo "[OK] $label (HTTP $http_code)"
    rm -f "$response_file"
    return
  fi

  echo "[ERROR] $label (HTTP $http_code)"
  cat "$response_file"
  rm -f "$response_file"
  exit 1
}

echo
echo "==> [1/3] Creating demo asset/policies/contract definition"

post_json_accept_conflict \
  "$CP_QNA/api/management/v3/assets" \
  "$API_KEY_CP" \
  "{\"@context\":[\"https://w3id.org/edc/connector/management/v0.0.1\"],\"@id\":\"$ASSET_ID\",\"@type\":\"Asset\",\"properties\":{\"description\":\"Membership demo asset\"},\"dataAddress\":{\"@type\":\"DataAddress\",\"type\":\"HttpData\",\"baseUrl\":\"https://jsonplaceholder.typicode.com/todos\",\"proxyPath\":\"true\",\"proxyQueryParams\":\"true\"}}" \
  "Create asset '$ASSET_ID'"

post_json_accept_conflict \
  "$CP_QNA/api/management/v3/policydefinitions" \
  "$API_KEY_CP" \
  "{\"@context\":[\"https://w3id.org/edc/connector/management/v0.0.1\"],\"@type\":\"PolicyDefinition\",\"@id\":\"$ACCESS_POLICY_ID\",\"policy\":{\"@type\":\"Set\",\"permission\":[{\"action\":\"use\",\"constraint\":{\"leftOperand\":\"MembershipCredential\",\"operator\":\"eq\",\"rightOperand\":\"active\"}}]}}" \
  "Create access policy '$ACCESS_POLICY_ID'"

post_json_accept_conflict \
  "$CP_QNA/api/management/v3/policydefinitions" \
  "$API_KEY_CP" \
  "{\"@context\":[\"https://w3id.org/edc/connector/management/v0.0.1\"],\"@type\":\"PolicyDefinition\",\"@id\":\"$CONTRACT_POLICY_ID\",\"policy\":{\"@type\":\"Set\",\"obligation\":[{\"action\":\"use\",\"constraint\":{\"leftOperand\":\"DataAccess.level\",\"operator\":\"eq\",\"rightOperand\":\"processing\"}}]}}" \
  "Create contract policy '$CONTRACT_POLICY_ID'"

post_json_accept_conflict \
  "$CP_QNA/api/management/v3/contractdefinitions" \
  "$API_KEY_CP" \
  "{\"@context\":[\"https://w3id.org/edc/connector/management/v0.0.1\"],\"@id\":\"$DEF_ID\",\"@type\":\"ContractDefinition\",\"accessPolicyId\":\"$ACCESS_POLICY_ID\",\"contractPolicyId\":\"$CONTRACT_POLICY_ID\",\"assetsSelector\":{\"@type\":\"Criterion\",\"operandLeft\":\"https://w3id.org/edc/v0.0.1/ns/id\",\"operator\":\"=\",\"operandRight\":\"$ASSET_ID\"}}" \
  "Create contract definition '$DEF_ID'"

echo
echo "==> [2/3] Requesting verifiable credential '$CREDENTIAL_TYPE'"

REQUEST_HEADERS="$(mktemp)"
REQUEST_BODY="$(mktemp)"

REQUEST_HTTP_CODE="$(curl -s -D "$REQUEST_HEADERS" -o "$REQUEST_BODY" -w "%{http_code}" -X POST \
  "$IH_CONSUMER/api/identity/v1alpha/participants/$PARTICIPANT_CONTEXT_B64/credentials/request" \
  -H 'Content-Type: application/json' \
  -H "x-api-key: $API_KEY_IH" \
  -d "{\"issuerDid\":\"$ISSUER_DID\",\"holderPid\":\"$REQUEST_ID\",\"credentials\":[{\"format\":\"VC1_0_JWT\",\"type\":\"$CREDENTIAL_TYPE\",\"id\":\"$CREDENTIAL_DEF_ID\"}]}")"

if [[ "$REQUEST_HTTP_CODE" != "200" && "$REQUEST_HTTP_CODE" != "201" && "$REQUEST_HTTP_CODE" != "204" ]]; then
  echo "[ERROR] Credential request failed (HTTP $REQUEST_HTTP_CODE)"
  cat "$REQUEST_BODY"
  rm -f "$REQUEST_HEADERS" "$REQUEST_BODY"
  exit 1
fi

LOCATION_HEADER="$(grep -i '^Location:' "$REQUEST_HEADERS" | tr -d '\r' | awk '{print $2}')"
if [[ -n "$LOCATION_HEADER" ]]; then
  REQUEST_ID="$(basename "$LOCATION_HEADER")"
fi

echo "[OK] Credential request accepted (HTTP $REQUEST_HTTP_CODE, requestId=$REQUEST_ID)"

rm -f "$REQUEST_HEADERS" "$REQUEST_BODY"

echo
echo "==> [3/3] Polling request status and querying issued credentials"

FINAL_STATUS=""
for ((i=1; i<=POLL_ATTEMPTS; i++)); do
  STATUS_RESPONSE="$(curl -s \
    "$IH_CONSUMER/api/identity/v1alpha/participants/$PARTICIPANT_CONTEXT_B64/credentials/request/$REQUEST_ID" \
    -H "x-api-key: $API_KEY_IH")"

  FINAL_STATUS="$(echo "$STATUS_RESPONSE" | jq -r '.status // empty' 2>/dev/null || true)"
  echo "poll $i/$POLL_ATTEMPTS status=${FINAL_STATUS:-unknown}"

  if [[ "$FINAL_STATUS" == "ISSUED" ]]; then
    break
  fi

  if [[ "$FINAL_STATUS" == "ERROR" ]]; then
    echo "$STATUS_RESPONSE" | jq .
    echo "[ERROR] Credential request ended in ERROR"
    exit 1
  fi

  sleep "$POLL_INTERVAL_SECONDS"
done

if [[ "$FINAL_STATUS" != "ISSUED" ]]; then
  echo "[ERROR] Timed out waiting for ISSUED state"
  exit 1
fi

echo
echo "Issued credential subject (first FoobarCredential):"
curl -s "$IH_CONSUMER/api/identity/v1alpha/participants/$PARTICIPANT_CONTEXT_B64/credentials?type=$CREDENTIAL_TYPE" \
  -H "x-api-key: $API_KEY_IH" \
  | jq '.[0].verifiableCredential.credential.credentialSubject[0]'

echo
echo "Advanced demo completed successfully."
