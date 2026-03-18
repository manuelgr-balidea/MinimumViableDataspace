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

cd "$(dirname "$0")/../.."   # repository root

if ! command -v newman >/dev/null 2>&1; then
  echo "ERROR: 'newman' is required but not installed."
  echo "Install with: npm install -g newman"
  exit 1
fi

HOST="${HOST:-http://localhost:8081}"
CATALOG_SERVER_DSP_URL="${CATALOG_SERVER_DSP_URL:-http://provider-catalog-server-controlplane:8082}"
PROVIDER_DSP_URL="${PROVIDER_DSP_URL:-http://provider-qna-controlplane:8082}"
PROVIDER_ID="${PROVIDER_ID:-did:web:provider-identityhub%3A7083:provider}"
CONSUMER_CATALOG_QUERY_URL="${CONSUMER_CATALOG_QUERY_URL:-http://localhost:8084}"
PROVIDER_PUBLIC_API="${PROVIDER_PUBLIC_API:-http://localhost:12001}"
DELAY_REQUEST_MS="${DELAY_REQUEST_MS:-4000}"
TIMEOUT_REQUEST_MS="${TIMEOUT_REQUEST_MS:-120000}"
NEWMAN_RETRIES="${NEWMAN_RETRIES:-3}"
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-5}"

attempt=1
while [ "$attempt" -le "$NEWMAN_RETRIES" ]; do
  echo "Running smoke test (attempt $attempt/$NEWMAN_RETRIES)..."

  if newman run deployment/postman/MVD.postman_collection.json \
    --folder "ControlPlane Management" \
    --env-var "HOST=$HOST" \
    --env-var "CATALOG_SERVER_DSP_URL=$CATALOG_SERVER_DSP_URL" \
    --env-var "PROVIDER_DSP_URL=$PROVIDER_DSP_URL" \
    --env-var "PROVIDER_ID=$PROVIDER_ID" \
    --env-var "CONSUMER_CATALOG_QUERY_URL=$CONSUMER_CATALOG_QUERY_URL" \
    --env-var "PROVIDER_PUBLIC_API=$PROVIDER_PUBLIC_API" \
    --delay-request "$DELAY_REQUEST_MS" \
    --timeout-request "$TIMEOUT_REQUEST_MS"; then
    echo "Smoke test passed on attempt $attempt."
    exit 0
  fi

  if [ "$attempt" -lt "$NEWMAN_RETRIES" ]; then
    echo "Smoke test attempt $attempt failed. Retrying in ${RETRY_DELAY_SECONDS}s..."
    sleep "$RETRY_DELAY_SECONDS"
  fi

  attempt=$((attempt + 1))
done

echo "Smoke test failed after $NEWMAN_RETRIES attempts."
exit 1
