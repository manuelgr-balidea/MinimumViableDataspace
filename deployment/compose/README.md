# MVD — Docker Compose Deployment

This directory contains a fully-functional Docker Compose deployment of the
Minimum Viable Dataspace (MVD). It is functionally equivalent to the Kubernetes
deployment described in [the main README](../../README.md) but requires only
Docker and Docker Compose — no KinD, Terraform or `kubectl` needed.

<!-- TOC -->
* [1. Prerequisites](#1-prerequisites)
* [2. Architecture overview](#2-architecture-overview)
* [3. How to run](#3-how-to-run)
  * [3.1 Build the images](#31-build-the-images)
  * [3.2 Start the dataspace](#32-start-the-dataspace)
  * [3.3 Seed the dataspace](#33-seed-the-dataspace)
  * [3.4 Verify everything is up](#34-verify-everything-is-up)
  * [3.5 Run an end-to-end smoke test](#35-run-an-end-to-end-smoke-test)
* [4. Port reference](#4-port-reference)
* [5. Executing REST requests](#5-executing-rest-requests)
* [6. Stopping and cleaning up](#6-stopping-and-cleaning-up)
* [7. Key design decisions](#7-key-design-decisions)
  * [7.1 Service names mirror K8s service names](#71-service-names-mirror-k8s-service-names)
  * [7.2 Vault in dev mode](#72-vault-in-dev-mode)
  * [7.3 PostgreSQL persistence](#73-postgresql-persistence)
  * [7.4 No Ingress — direct port mapping](#74-no-ingress--direct-port-mapping)
* [8. Troubleshooting](#8-troubleshooting)
<!-- TOC -->

---

## 1. Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Docker | ≥ 24 | with Compose plugin v2 |
| JDK | 17 + | to build the runtime images |
| `newman` | latest | `npm install -g newman` — runs Postman collections |
| `jq` | any | used by `seed-compose.sh` |
| Postman | optional | for interactive REST calls |

If `docker compose` is not available in your environment, use `docker-compose`
instead (or install the Docker Compose plugin).

All commands below are executed **from the repository root** unless noted
otherwise.

---

## 2. Architecture overview

```
┌──────────────────────────────────────────────────────────────────┐
│  Docker network: mvd-net                                         │
│                                                                  │
│  dataspace-issuer (nginx)    ← did:web:dataspace-issuer          │
│                                                                  │
│  ┌─── Consumer Corp ───────────────────────────────────────┐    │
│  │  consumer-postgres   consumer-vault                      │    │
│  │  consumer-identityhub   ← did:web:consumer-identityhub  │    │
│  │                             %3A7083:consumer             │    │
│  │  consumer-controlplane  consumer-dataplane               │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─── Provider Corp ───────────────────────────────────────┐    │
│  │  provider-postgres   provider-vault                      │    │
│  │  provider-identityhub   ← did:web:provider-identityhub  │    │
│  │                             %3A7083:provider             │    │
│  │  provider-catalog-server-controlplane                    │    │
│  │  provider-qna-controlplane   provider-qna-dataplane      │    │
│  │  provider-manufacturing-controlplane                     │    │
│  │  provider-manufacturing-dataplane                        │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─── Dataspace Issuer Service ────────────────────────────┐    │
│  │  issuer-postgres                                         │    │
│  │  dataspace-issuer-service                                │    │
│  │    ← did:web:dataspace-issuer-service%3A10016:issuer     │    │
│  └──────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

Total: **16 containers** (3 postgres, 2 vault, 1 nginx, 2 IdentityHubs,
1 catalog server, 2 full connectors × controlplane + dataplane, 1 issuer service).

---

## 3. How to run

### 3.1 Build the images

Run the following from the **repository root**.  
The `-Ppersistence=true` flag is **mandatory** — it adds the HashiCorp Vault
and PostgreSQL modules to the classpath.

```bash
./gradlew build
./gradlew -Ppersistence=true dockerize
```

This produces the following images in the local Docker cache:

| Image | Description |
|-------|-------------|
| `controlplane:latest` | EDC Control Plane |
| `dataplane:latest` | EDC Data Plane |
| `catalog-server:latest` | Federated Catalog Server |
| `identity-hub:latest` | IdentityHub (DID + STS + Credentials) |
| `issuerservice:latest` | Dataspace Issuer Service |

### 3.2 Start the dataspace

```bash
cd deployment/compose
docker compose up -d
```

If your Docker CLI does not support `docker compose`, use:

```bash
cd deployment/compose
docker-compose up -d
```

Docker Compose starts all 16 containers in dependency order:
1. postgres and vault instances come up first (healthchecks)
2. IdentityHubs start once their databases and vaults are healthy
3. Connectors / catalog server start once the IdentityHub is available
4. Dataplanes start after their respective controlplanes

Wait until all containers are healthy / running:

```bash
docker compose ps
```

Expected output (all `Up` or `healthy`):

```
NAME                                     STATUS
consumer-controlplane                    Up
consumer-dataplane                       Up
consumer-identityhub                     Up
consumer-postgres                        Up (healthy)
consumer-vault                           Up (healthy)
dataspace-issuer                         Up (healthy)
dataspace-issuer-service                 Up
issuer-postgres                          Up (healthy)
provider-catalog-server-controlplane     Up
provider-identityhub                     Up
provider-manufacturing-controlplane      Up
provider-manufacturing-dataplane         Up
provider-postgres                        Up (healthy)
provider-qna-controlplane                Up
provider-qna-dataplane                   Up
provider-vault                           Up (healthy)
```

> **Tip:** EDC JVM services take 30–60 s to become fully responsive.  
> If a container shows `Restarting`, wait — it will retry once its
> dependencies (vault, postgres) are stable.

### 3.3 Seed the dataspace

Run the seed script from the **repository root** after all services are up:

```bash
./deployment/compose/seed-compose.sh
```

The script now waits automatically for Compose readiness before seeding.
You can tune the wait behavior with:
- `SEED_WAIT_TIMEOUT_SECONDS` (default: `180`)
- `SEED_WAIT_INTERVAL_SECONDS` (default: `5`)

Example:
```bash
SEED_WAIT_TIMEOUT_SECONDS=300 ./deployment/compose/seed-compose.sh
```

The script:
1. Seeds assets and policies to `provider-qna` and `provider-manufacturing`
2. Creates linked catalog assets on the `provider-catalog-server`
3. Creates participant contexts in both IdentityHubs (generates key pairs,
   stores private keys in vault)
4. Creates the issuer participant context in the Issuer Service
5. Seeds attestation definitions for credential issuance via the admin API

The script is safe to re-run: participant context creation accepts `409 Conflict`
for already existing participants and continues.

> **Important:** The seed must be executed **every time** the vault containers
> are re-created (vault uses in-memory storage in dev mode — secrets are lost
> on restart).  
> PostgreSQL data is persisted in named volumes and survives restarts.

### 3.4 Verify everything is up

Check the consumer's federated catalog — it should contain assets from both
provider connectors:

```bash
curl -s -X POST http://localhost:8081/api/management/v3/catalog/request \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{"protocol": "dataspace-protocol-http"}' | jq .
```

### 3.5 Run an end-to-end smoke test

Run the full exchange flow (catalog -> negotiation -> transfer -> download) with Newman:

```bash
./deployment/compose/smoke-compose.sh
```

Equivalent raw command:

```bash
newman run deployment/postman/MVD.postman_collection.json \
  --folder "ControlPlane Management" \
  --env-var "HOST=http://localhost:8081" \
  --env-var "CATALOG_SERVER_DSP_URL=http://provider-catalog-server-controlplane:8082" \
  --env-var "PROVIDER_DSP_URL=http://provider-qna-controlplane:8082" \
  --env-var "PROVIDER_ID=did:web:provider-identityhub%3A7083:provider" \
  --env-var "CONSUMER_CATALOG_QUERY_URL=http://localhost:8084" \
  --env-var "PROVIDER_PUBLIC_API=http://localhost:12001" \
  --delay-request 4000 \
  --timeout-request 120000
```

Expected result:
- all requests in `ControlPlane Management` pass,
- no assertion failures,
- data download from `http://localhost:12001/api/public` returns `200`.

---

## 4. Port reference

All ports below are **host** ports (accessible from `localhost`).  
Internal service-to-service communication uses Docker DNS (service names).

### Consumer Corp

| Service | Port | API |
|---------|------|-----|
| `consumer-identityhub` | 7081 | Identity (seed / admin) |
| `consumer-identityhub` | 7082 | Credentials |
| `consumer-identityhub` | 7083 | DID resolution |
| `consumer-identityhub` | 7084 | STS token |
| `consumer-controlplane` | 8080 | Health |
| `consumer-controlplane` | **8081** | **Management API** (Postman) |
| `consumer-controlplane` | 8082 | DSP / Protocol |
| `consumer-controlplane` | 8083 | Control |
| `consumer-controlplane` | 8084 | Catalog |
| `consumer-dataplane` | 11002 | Public (data transfer) |
| `consumer-postgres` | 5432 | PostgreSQL |
| `consumer-vault` | 18200 | Vault UI / API |

### Provider Corp

| Service | Port | API |
|---------|------|-----|
| `provider-identityhub` | 7091 | Identity (seed / admin) |
| `provider-identityhub` | 7092 | Credentials |
| `provider-identityhub` | 7093 | DID resolution |
| `provider-identityhub` | 7094 | STS token |
| `provider-catalog-server-controlplane` | 8091 | Management API (seed) |
| `provider-catalog-server-controlplane` | 8092 | DSP / Protocol |
| `provider-qna-controlplane` | **8191** | **Management API** (seed) |
| `provider-qna-controlplane` | 8192 | DSP / Protocol |
| `provider-qna-dataplane` | 12001 | Public (data transfer) |
| `provider-manufacturing-controlplane` | **8291** | **Management API** (seed) |
| `provider-manufacturing-controlplane` | 8292 | DSP / Protocol |
| `provider-manufacturing-dataplane` | 12002 | Public (data transfer) |
| `provider-postgres` | 5433 | PostgreSQL |
| `provider-vault` | 18201 | Vault UI / API |

### Dataspace Issuer Service

| Service | Port | API |
|---------|------|-----|
| `dataspace-issuer` (nginx) | 9876 | DID document (`did:web:dataspace-issuer`) |
| `dataspace-issuer-service` | 10010 | Health |
| `dataspace-issuer-service` | 10012 | Issuance |
| `dataspace-issuer-service` | **10013** | **Admin API** (seed) |
| `dataspace-issuer-service` | 10015 | Identity (seed) |
| `dataspace-issuer-service` | 10016 | DID resolution |
| `issuer-postgres` | 5434 | PostgreSQL |

---

## 5. Executing REST requests

If you want a focused, step-by-step explanation of contract negotiation only (catalog -> offer -> contract negotiation -> agreement id), see [`README_DSP_NEGOTIATION.md`](./README_DSP_NEGOTIATION.md).

Use the existing Postman collection at
[`deployment/postman/MVD.postman_collection.json`](../postman/MVD.postman_collection.json).

Create a new **Compose** environment in Postman (or duplicate the existing
`MVD Local Development` environment) and set:

| Variable | Value |
|----------|-------|
| `CONSUMER_MANAGEMENT_URL` | `http://localhost:8081/api/management` |
| `PROVIDER_QNA_MANAGEMENT_URL` | `http://localhost:8191/api/management` |
| `PROVIDER_MF_MANAGEMENT_URL` | `http://localhost:8291/api/management` |
| `CONSUMER_AUTH_KEY` | `password` |
| `PROVIDER_AUTH_KEY` | `password` |

Alternatively, use `curl` with the host ports listed in [section 4](#4-port-reference).

---

## 6. Stopping and cleaning up

Stop all containers (data is preserved in volumes):

```bash
docker compose down
```

Stop and **remove all volumes** (full reset — next `up` will re-init databases):

```bash
docker compose down -v
```

Remove the built images:

```bash
docker rmi controlplane:latest dataplane:latest catalog-server:latest \
            identity-hub:latest issuerservice:latest
```

---

## 7. Key design decisions

### 7.1 Service names mirror K8s service names

The Compose service names are **identical** to the Kubernetes service names.
This is critical because:

- `did:web` DIDs encode the hostname and port, e.g.  
  `did:web:consumer-identityhub%3A7083:consumer` → `http://consumer-identityhub:7083/consumer/did.json`
- DSP callback addresses reference the controlplane service name, e.g.  
  `EDC_DSP_CALLBACK_ADDRESS=http://consumer-controlplane:8082/api/dsp`
- The STS token URL references the IdentityHub service name, e.g.  
  `http://consumer-identityhub:7084/api/sts/token`

As a result, the **same credential files** (`deployment/assets/credentials/k8s/`),
the **same participants list** (`participants.k8s.json`), and the **same DID
documents** (`did.k8s.json`) used in K8s are reused without modification.

### 7.2 Vault in dev mode

Both `consumer-vault` and `provider-vault` run in Vault dev mode:
- Root token is `root`
- Key-value store is enabled at `secret/` (KV v1)
- Storage is **in-memory** — secrets are lost when the container stops

The private signing keys are generated by IdentityHub when the participant
contexts are created during the seed step. If vault is restarted, re-run
`seed-compose.sh` to regenerate the keys.

The Hashicorp Vault containers are accessible from the host for inspection:
- consumer-vault: `http://localhost:18200` (token: `root`)
- provider-vault: `http://localhost:18201` (token: `root`)

### 7.3 PostgreSQL persistence

Named Docker volumes persist the database schemas and data across container
restarts:

| Volume | Content |
|--------|---------|
| `consumer-postgres-data` | Consumer connector DB |
| `provider-postgres-data` | Catalog server, qna, manufacturing, identity hub DBs |
| `issuer-postgres-data` | Issuer service DB (includes membership attestations) |

Init SQL scripts run only on **first creation** (when the volume is empty).

### 7.4 No Ingress — direct port mapping

The Kubernetes deployment routes external traffic through an NGINX Ingress
at `127.0.0.1` with path-based routing (e.g., `/consumer/cp`). The Compose
deployment eliminates the ingress layer and maps each service's Management API
and Protocol ports directly to unique host ports (see [section 4](#4-port-reference)).

Internal service-to-service communication (DSP, STS, Credentials API) uses
Docker bridge networking — containers resolve each other by service name.

---

## 8. Troubleshooting

**Container keeps restarting**  
EDC JVMs need vault and postgres to be healthy before making DCP calls.
`restart: on-failure` handles transient startup failures. Wait 60 s and
check `docker compose logs <service>`.

**`seed-compose.sh` fails with connection refused**  
Ensure the compose stack is running: `docker compose up -d` and check
`docker compose ps`. If startup takes longer than expected, increase
`SEED_WAIT_TIMEOUT_SECONDS` and run the seed script again.

**`unknown shorthand flag: 'd' in -d` when running compose**  
Your Docker CLI does not have the compose plugin. Use `docker-compose up -d`
or install the compose plugin and retry.

**`newman: command not found` during seed**  
Install Newman and retry:
```bash
npm install -g newman
```

**`Bind for 0.0.0.0:<port> failed: port is already allocated`**  
Another process is already using one of the host ports from [section 4](#4-port-reference).
Free the port or change the host-side mapping in `docker-compose.yml`, then restart the affected service:
```bash
docker compose up -d --force-recreate <service>
```

**`vault status` shows sealed / not initialized**  
Vault is in dev mode and should auto-initialize. If the vault container
crashed, restart it: `docker compose restart consumer-vault provider-vault`.
Then re-run the seed.

**DID resolution errors in connector logs**  
Check that the `dataspace-issuer` nginx container is running and serving the
DID document:
```bash
curl http://localhost:9876/.well-known/did.json
```

**Catalog returns empty results after seeding**  
The federated catalog crawls every 10 s (`EDC_CATALOG_CACHE_EXECUTION_PERIOD_SECONDS=10`).
Wait a few seconds after seeding and retry the catalog request.

**`invalid_client` in controlplane logs / catalog request returns `502`**  
This indicates STS credentials are out of sync (typically after partial restarts
of identity-related services). Execute a full clean reset and reseed:
```bash
cd deployment/compose
docker compose down -v
docker compose up -d
cd ../..
./deployment/compose/seed-compose.sh
./deployment/compose/smoke-compose.sh
```

**Postgres init SQL not applied**  
The init SQL only runs when the data directory is empty. If you previously
ran `docker compose up` with a different SQL script, remove the volumes:
```bash
docker compose down -v
docker compose up -d
```
