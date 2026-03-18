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

# ---------------------------------------------------------------------------
# seed-compose.sh  —  Dataspace seed script for Docker Compose deployment
#
# Equivalent to seed-k8s.sh but uses direct localhost:<port> addresses
# instead of the Kubernetes NGINX Ingress paths.
#
# Run from the repository root AFTER "docker compose up -d".
# The script waits automatically for services to be healthy.
#
# Prerequisites: jq, newman (npm install -g newman)
# ---------------------------------------------------------------------------

set -euo pipefail
cd "$(dirname "$0")/../.."   # repo root

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: 'jq' is required but not installed."
  echo "Install with: sudo apt-get install -y jq"
  exit 1
fi

if ! command -v newman >/dev/null 2>&1; then
  echo "ERROR: 'newman' is required but not installed."
  echo "Install with: npm install -g newman"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: 'docker' is required but not installed."
  exit 1
fi

if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
  echo "ERROR: Docker Compose is not available."
  echo "Install docker compose plugin or docker-compose binary."
  exit 1
fi

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
else
  COMPOSE_CMD=(docker-compose)
fi

COMPOSE_WORKDIR="./deployment/compose"

if [[ ! -d "$COMPOSE_WORKDIR" ]]; then
  echo "ERROR: compose directory not found at '$COMPOSE_WORKDIR'."
  exit 1
fi

wait_for_compose_ready() {
  local timeout_seconds="${SEED_WAIT_TIMEOUT_SECONDS:-180}"
  local interval_seconds="${SEED_WAIT_INTERVAL_SECONDS:-5}"
  local elapsed_seconds=0

  echo
  echo "==> Waiting for Compose services to be ready (timeout ${timeout_seconds}s)"

  while true; do
    local ps_output
    if ! ps_output="$(cd "$COMPOSE_WORKDIR" && "${COMPOSE_CMD[@]}" ps 2>/dev/null)"; then
      echo "ERROR: failed to read compose status."
      echo "Ensure the compose stack is running before seeding."
      exit 1
    fi

    if echo "$ps_output" | grep -q 'Up' \
      && ! echo "$ps_output" | grep -Eq 'health: starting|unhealthy|Restarting'; then
      echo " ← Compose services ready"
      return
    fi

    if (( elapsed_seconds >= timeout_seconds )); then
      echo "ERROR: services did not become ready in ${timeout_seconds}s"
      echo "$ps_output"
      exit 1
    fi

    sleep "$interval_seconds"
    elapsed_seconds=$((elapsed_seconds + interval_seconds))
  done
}

wait_for_compose_ready

## ──────────────────────────────────────────────────────────────────────────
## 1. Seed application data to provider connectors
## ──────────────────────────────────────────────────────────────────────────

echo
echo "==> Seeding assets to 'provider-qna' and 'provider-manufacturing'"

for HOST in \
  "http://localhost:8191" \
  "http://localhost:8291"
do
  newman run \
    --folder "Seed" \
    --env-var "HOST=$HOST" \
    ./deployment/postman/MVD.postman_collection.json
done

## ──────────────────────────────────────────────────────────────────────────
## 2. Seed linked catalog assets to the Catalog Server
##    DSP URLs must be Docker-internal service names (not localhost),
##    because the catalog server resolves them from inside the Docker network.
## ──────────────────────────────────────────────────────────────────────────

echo
echo "==> Creating linked assets on the Catalog Server"

newman run \
  --folder "Seed Catalog Server" \
  --env-var "HOST=http://localhost:8091" \
  --env-var "PROVIDER_QNA_DSP_URL=http://provider-qna-controlplane:8082" \
  --env-var "PROVIDER_MF_DSP_URL=http://provider-manufacturing-controlplane:8082" \
  ./deployment/postman/MVD.postman_collection.json

## ──────────────────────────────────────────────────────────────────────────
## 3. Create participant contexts in IdentityHubs
##    Service endpoint URLs (DSP, CredentialService) use Docker-internal names.
## ──────────────────────────────────────────────────────────────────────────

API_KEY="c3VwZXItdXNlcg==.c3VwZXItc2VjcmV0LWtleQo="

post_participant_context() {
  local url="$1"
  local payload="$2"
  local participant_label="$3"

  local response_file
  response_file="$(mktemp)"

  local http_code
  http_code="$(curl -s -o "$response_file" -w "%{http_code}" --location "$url" \
    --header 'Content-Type: application/json' \
    --header "x-api-key: $API_KEY" \
    --data "$payload")"

  if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
    rm -f "$response_file"
    echo " ← $participant_label participant created"
    return
  fi

  if [[ "$http_code" == "409" ]]; then
    rm -f "$response_file"
    echo " ← $participant_label participant already exists (409)"
    return
  fi

  echo "ERROR: failed to create $participant_label participant (HTTP $http_code)"
  cat "$response_file"
  rm -f "$response_file"
  exit 1
}

# ── Consumer ─────────────────────────────────────────────────────────────
echo
echo "==> Creating consumer participant context in IdentityHub"

CONSUMER_DID="did:web:consumer-identityhub%3A7083:consumer"
# base64url of the consumer DID (used as path segment in Credentials API)
CONSUMER_DID_B64="ZGlkOndlYjpjb25zdW1lci1pZGVudGl0eWh1YiUzQTcwODM6Y29uc3VtZXI="
CONSUMER_CONTROLPLANE_DSP="http://consumer-controlplane:8082"
CONSUMER_IH_INTERNAL="http://consumer-identityhub:7082"

DATA_CONSUMER=$(jq -n \
  --arg dsp "$CONSUMER_CONTROLPLANE_DSP" \
  --arg ihurl "$CONSUMER_IH_INTERNAL" \
  --arg b64 "$CONSUMER_DID_B64" \
  --arg did "$CONSUMER_DID" '{
    "roles": [],
    "serviceEndpoints": [
      {
        "type": "CredentialService",
        "serviceEndpoint": "\($ihurl)/api/credentials/v1/participants/\($b64)",
        "id": "consumer-credentialservice-1"
      },
      {
        "type": "ProtocolEndpoint",
        "serviceEndpoint": "\($dsp)/api/dsp",
        "id": "consumer-dsp"
      }
    ],
    "active": true,
    "participantId": $did,
    "did": $did,
    "key": {
      "keyId": "\($did)#key-1",
      "privateKeyAlias": "\($did)#key-1",
      "keyGeneratorParams": {
        "algorithm": "EC"
      }
    }
  }')

post_participant_context \
  "http://localhost:7081/api/identity/v1alpha/participants/" \
  "$DATA_CONSUMER" \
  "consumer"

# ── Provider ─────────────────────────────────────────────────────────────
echo
echo "==> Creating provider participant context in IdentityHub"

PROVIDER_DID="did:web:provider-identityhub%3A7083:provider"
PROVIDER_DID_B64="ZGlkOndlYjpwcm92aWRlci1pZGVudGl0eWh1YiUzQTcwODM6cHJvdmlkZXI="
PROVIDER_CATALOG_DSP="http://provider-catalog-server-controlplane:8082"
PROVIDER_IH_INTERNAL="http://provider-identityhub:7082"

DATA_PROVIDER=$(jq -n \
  --arg dsp "$PROVIDER_CATALOG_DSP" \
  --arg ihurl "$PROVIDER_IH_INTERNAL" \
  --arg b64 "$PROVIDER_DID_B64" \
  --arg did "$PROVIDER_DID" '{
    "roles": [],
    "serviceEndpoints": [
      {
        "type": "CredentialService",
        "serviceEndpoint": "\($ihurl)/api/credentials/v1/participants/\($b64)",
        "id": "provider-credentialservice-1"
      },
      {
        "type": "ProtocolEndpoint",
        "serviceEndpoint": "\($dsp)/api/dsp",
        "id": "provider-dsp"
      }
    ],
    "active": true,
    "participantId": $did,
    "did": $did,
    "key": {
      "keyId": "\($did)#key-1",
      "privateKeyAlias": "\($did)#key-1",
      "keyGeneratorParams": {
        "algorithm": "EC"
      }
    }
  }')

post_participant_context \
  "http://localhost:7091/api/identity/v1alpha/participants/" \
  "$DATA_PROVIDER" \
  "provider"

## ──────────────────────────────────────────────────────────────────────────
## 4. Create issuer participant context in the Dataspace Issuer Service
## ──────────────────────────────────────────────────────────────────────────

echo
echo "==> Creating dataspace issuer participant context"

ISSUER_DID="did:web:dataspace-issuer-service%3A10016:issuer"
ISSUER_DID_B64="ZGlkOndlYjpkYXRhc3BhY2UtaXNzdWVyLXNlcnZpY2UlM0ExMDAxNjppc3N1ZXI="
ISSUER_ISSUANCE_INTERNAL="http://dataspace-issuer-service:10012"

DATA_ISSUER=$(jq -n \
  --arg issuance "$ISSUER_ISSUANCE_INTERNAL" \
  --arg b64 "$ISSUER_DID_B64" \
  --arg did "$ISSUER_DID" '{
    "roles": ["admin"],
    "serviceEndpoints": [
      {
        "type": "IssuerService",
        "serviceEndpoint": "\($issuance)/api/issuance/v1alpha/participants/\($b64)",
        "id": "issuer-service-1"
      }
    ],
    "active": true,
    "participantId": $did,
    "did": $did,
    "key": {
      "keyId": "\($did)#key-1",
      "privateKeyAlias": "key-1",
      "keyGeneratorParams": {
        "algorithm": "EdDSA"
      }
    }
  }')

post_participant_context \
  "http://localhost:10015/api/identity/v1alpha/participants/" \
  "$DATA_ISSUER" \
  "issuer"

## ──────────────────────────────────────────────────────────────────────────
## 5. Seed Issuer SQL data (attestation definitions, etc.)
## ──────────────────────────────────────────────────────────────────────────

echo
echo "==> Seeding Issuer Service admin data"

newman run \
  --folder "Seed Issuer SQL" \
  --env-var "ISSUER_ADMIN_URL=http://localhost:10013" \
  --env-var "CONSUMER_ID=did:web:consumer-identityhub%3A7083:consumer" \
  --env-var "CONSUMER_NAME=MVD Consumer Participant" \
  --env-var "PROVIDER_ID=did:web:provider-identityhub%3A7083:provider" \
  --env-var "PROVIDER_NAME=MVD Provider Participant" \
  ./deployment/postman/MVD.postman_collection.json

echo
echo "==> Seed complete!"
echo
echo "    Use the Postman collection with the 'MVD Compose' environment"
echo "    or set HOST=http://localhost:8081 for consumer management API."
