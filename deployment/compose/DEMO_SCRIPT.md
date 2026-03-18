# Guion de Demo — MVD con Docker Compose

Este documento está pensado para una demo en vivo de las funcionalidades más destacadas del MVD: `provider`, `consumer`, `federated catalog` e `identity hub`.

## 1) Objetivo y duración

- Duración recomendada: **20–25 minutos**.
- Resultado esperado: mostrar el ciclo completo de intercambio de datos:
  1. Provider publica y expone activos.
  2. Consumer descubre vía catálogo federado.
  3. Consumer negocia contrato y transfiere.
  4. IdentityHub gestiona identidad/DID/credenciales.

## 2) Pre-flight (2–3 min antes de presentar)

Desde la raíz del repositorio:

```bash
cd deployment/compose
docker compose up -d
docker compose ps
cd ../..
./deployment/compose/seed-compose.sh
```

Si quieres validar todo justo antes de la reunión:

```bash
./deployment/compose/smoke-compose.sh
```

## 3) Variables para copiar/pegar en la demo

```bash
export CP_CONSUMER="http://localhost:8081"
export CP_QNA="http://localhost:8191"
export CP_MF="http://localhost:8291"
export CATALOG_QUERY="http://localhost:8084"
export IH_CONSUMER="http://localhost:7081"
export IH_PROVIDER="http://localhost:7091"
export DID_CONSUMER="http://localhost:7083"
export DID_PROVIDER="http://localhost:7093"
export DID_CONSUMER_HOST="consumer-identityhub:7083"
export DID_PROVIDER_HOST="provider-identityhub:7083"
export PROVIDER_PUBLIC_API="http://localhost:12001"
export API_KEY_CP="password"
export API_KEY_IH="c3VwZXItdXNlcg==.c3VwZXItc2VjcmV0LWtleQo="
export PROVIDER_ID="did:web:provider-identityhub%3A7083:provider"
export CATALOG_SERVER_DSP_URL="http://provider-catalog-server-controlplane:8082"
export PROVIDER_DSP_URL="http://provider-qna-controlplane:8082"
```

## 4) Guion principal (20–25 min)

## Bloque A — Estado de la plataforma (2 min)

### Acción

```bash
cd deployment/compose
docker compose ps
cd ../..
```

### Qué contar

- “Aquí levantamos todo localmente con Compose, sin Kubernetes.”
- “Tenemos consumer, provider, catálogo federado, identity hubs y issuer.”

### Resultado esperado

- Servicios `Up`/`healthy`.

---

## Bloque B — Funcionalidades del Provider (4–5 min)

### Acción 1: listar assets del provider QnA

```bash
curl -s -X POST "$CP_QNA/api/management/v3/assets/request" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY_CP" \
  -d '{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"@type":"QuerySpec"}' \
  | jq -r '.[]."@id"'
```

### Acción 2: listar assets del provider Manufacturing

```bash
curl -s -X POST "$CP_MF/api/management/v3/assets/request" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY_CP" \
  -d '{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"@type":"QuerySpec"}' \
  | jq -r '.[]."@id"'
```

### Qué contar

- “Cada provider gestiona sus propios activos y políticas de acceso.”
- “QnA y Manufacturing son dominios distintos, pero luego se federan.”

### Resultado esperado

- Se ven IDs como `asset-1`, `asset-2` en ambos providers.

---

## Bloque C — Federated Catalog (4–5 min)

### Acción 1: forzar pedido de catálogo desde consumer

```bash
curl -s -X POST "$CP_CONSUMER/api/management/v3/catalog/request" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY_CP" \
  -d "{
    \"@context\":[\"https://w3id.org/edc/connector/management/v0.0.1\"],
    \"@type\":\"CatalogRequest\",
    \"counterPartyAddress\":\"$CATALOG_SERVER_DSP_URL/api/dsp\",
    \"counterPartyId\":\"$PROVIDER_ID\",
    \"protocol\":\"dataspace-protocol-http\",
    \"querySpec\":{\"offset\":0,\"limit\":50}
  }" | jq .
```

### Acción 2: consultar caché de catálogo del consumer

```bash
curl -s -X POST "$CATALOG_QUERY/api/catalog/v1alpha/catalog/query" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY_CP" \
  -d '{"@context":["https://w3id.org/edc/connector/management/v0.0.1"],"@type":"QuerySpec"}' \
  | jq -r '
      ..
      | objects
      | .["dcat:dataset"]?
      | if type=="array" then .[] else . end
      | "asset=" + (.[ "@id" ] // "") + " | policy=" + (.["odrl:hasPolicy"]["@id"] // "")
    '
```

```bash
curl -s -X POST "$CATALOG_QUERY/api/catalog/v1alpha/catalog/query" \
curl -s -X POST "$CATALOG_QUERY/api/catalog/v1alpha/catalog/query" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY_CP" \
  -d '{"@context":["https://w3id.org/edc/connector/management/v0.0.1"],"@type":"QuerySpec"}' \
  | jq -r '
    .[]
    | (
        {catalogId: .["@id"],
         endpoint: .["dcat:service"]["dcat:endpointURL"],
         participant: .["dspace:participantId"],
         datasets: (if .["dcat:dataset"] then (if (.["dcat:dataset"]|type)=="array" then .["dcat:dataset"] else [ .["dcat:dataset"] ] end) else [] end)}
      ),
      (
        .["dcat:catalog"][]?
        | {catalogId: .["@id"],
           endpoint: .["dcat:service"]["dcat:endpointURL"],
           participant: .["dspace:participantId"],
           datasets: (if .["dcat:dataset"] then (if (.["dcat:dataset"]|type)=="array" then .["dcat:dataset"] else [ .["dcat:dataset"] ] end) else [] end)}
      )
    | . as $cat
    | $cat.datasets[]
    | "asset=" + (.["@id"] // "")
      + " | endpoint=" + ($cat.endpoint // "")
      + " | participant=" + ($cat.participant // "")
  '
```

### Qué contar

- “El consumer no interroga cada provider por separado; usa el catálogo federado.”
- “Esto desacopla descubrimiento de activos del detalle operativo de cada organización.”

### Resultado esperado

- Aparecen datasets del catálogo federado (incluyendo `asset-1`).

---

## Bloque D — Consumer: negociación + transferencia (6–8 min)

La forma más robusta para demo en vivo es ejecutar el flujo ya validado en la colección Postman vía Newman.

### Acción

```bash
newman run deployment/postman/MVD.postman_collection.json \
  --folder "ControlPlane Management" \
  --env-var "HOST=$CP_CONSUMER" \
  --env-var "CATALOG_SERVER_DSP_URL=$CATALOG_SERVER_DSP_URL" \
  --env-var "PROVIDER_DSP_URL=$PROVIDER_DSP_URL" \
  --env-var "PROVIDER_ID=$PROVIDER_ID" \
  --env-var "CONSUMER_CATALOG_QUERY_URL=$CATALOG_QUERY" \
  --env-var "PROVIDER_PUBLIC_API=$PROVIDER_PUBLIC_API" \
  --delay-request 3000 \
  --timeout-request 120000
```

### Qué contar

- “Aquí se ve el ciclo completo: `catalog -> negotiation -> transfer -> EDR -> download`.”
- “La transferencia final se valida con descarga HTTP del dataplane (`/api/public`).”

### Resultado esperado

- Todas las requests del folder `ControlPlane Management` en verde.
- `Download Data from Public API` con `200 OK`.

---

## Bloque E — IdentityHub: identidad y contexto de participantes (4–5 min)

### Acción 1: listar participantes en consumer IdentityHub

```bash
curl -s "$IH_CONSUMER/api/identity/v1alpha/participants" \
  -H "x-api-key: $API_KEY_IH" \
  | jq -r '.[].participantContextId'
```

### Acción 2: listar participantes en provider IdentityHub

```bash
curl -s "$IH_PROVIDER/api/identity/v1alpha/participants" \
  -H "x-api-key: $API_KEY_IH" \
  | jq -r '.[].participantContextId'
```

### Acción 3: resolver DID documents publicados

```bash
curl -s -H "Host: $DID_CONSUMER_HOST" "$DID_CONSUMER/consumer/did.json" | jq '{id, service}'
curl -s -H "Host: $DID_PROVIDER_HOST" "$DID_PROVIDER/provider/did.json" | jq '{id, service}'
```

### Qué contar

- “IdentityHub administra el contexto del participante, claves y endpoints de servicio.”
- “Los DIDs son la base de confianza para DSP/STS y para el intercambio de credenciales.”

### Resultado esperado

- Se visualizan participantes `did:web:...consumer` y `did:web:...provider`.
- Los DID docs muestran `id` y `service endpoints`.

---

## Bloque F — Cierre (1 min)

### Mensaje final sugerido

- “Hemos mostrado gobierno de activos en providers, descubrimiento federado, intercambio seguro desde consumer e identidad descentralizada con IdentityHub.”
- “Todo ejecutado localmente con Compose, listo para evolucionar a entorno K8s.”

---

## Bloque G (opcional) — Demo adicional: nuevo asset + policy + emisión VC (8–10 min)

Este bloque añade una historia completa de negocio adicional, independiente del `seed`:

1. Crear un asset nuevo en provider QnA.
2. Crear una policy nueva (basada en `MembershipCredential`).
3. Vincular asset+policy en un `ContractDefinition` nuevo.
4. Solicitar una VC al Issuer Service y verla en el IdentityHub del consumer.

> Nota sobre “consumer EU”: en este runtime, el operando `DataAccess.region` no está registrado por defecto en policy-engine.  
> Para demo, se representa “EU” en el claim `membershipType` de la VC emitida (`FoobarCredential`).

Si prefieres ejecución automática, usa este comando:

```bash
./deployment/compose/demo-advanced.sh
```

Si quieres ejecutar el flujo y limpiar automáticamente los recursos creados (`asset/policy/contract definition`):

```bash
./deployment/compose/demo-advanced-clean.sh
```

Opcionalmente puedes sobreescribir IDs para no reutilizar los mismos en varias demos:

```bash
ASSET_ID="asset-membership-demo-2" \
POLICY_ID="require-membership-demo-2" \
DEF_ID="membership-demo-def-2" \
./deployment/compose/demo-advanced.sh
```

```bash
ASSET_ID="asset-membership-demo-2" \
POLICY_ID="require-membership-demo-2" \
DEF_ID="membership-demo-def-2" \
./deployment/compose/demo-advanced-clean.sh
```

### Acción 1: crear asset/policy/contract definition nuevos

```bash
export ASSET_ID="asset-membership-demo-1"
export POLICY_ID="require-membership-demo"
export DEF_ID="membership-demo-def"
```

```bash
curl -s -X POST "$CP_QNA/api/management/v3/assets" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY_CP" \
  -d '{
    "@context": ["https://w3id.org/edc/connector/management/v0.0.1"],
    "@id": "'"$ASSET_ID"'",
    "@type": "Asset",
    "properties": {"description": "Membership demo asset"},
    "dataAddress": {
      "@type": "DataAddress",
      "type": "HttpData",
      "baseUrl": "https://jsonplaceholder.typicode.com/todos",
      "proxyPath": "true",
      "proxyQueryParams": "true"
    }
  }' | jq .
```

```bash
curl -s -X POST "$CP_QNA/api/management/v3/policydefinitions" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY_CP" \
  -d '{
    "@context": ["https://w3id.org/edc/connector/management/v0.0.1"],
    "@type": "PolicyDefinition",
    "@id": "'"$POLICY_ID"'",
    "policy": {
      "@type": "Set",
      "permission": [
        {
          "action": "use",
          "constraint": {
            "leftOperand": "MembershipCredential",
            "operator": "eq",
            "rightOperand": "active"
          }
        }
      ]
    }
  }' | jq .
```

```bash
curl -s -X POST "$CP_QNA/api/management/v3/contractdefinitions" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY_CP" \
  -d '{
    "@context": ["https://w3id.org/edc/connector/management/v0.0.1"],
    "@id": "'"$DEF_ID"'",
    "@type": "ContractDefinition",
    "accessPolicyId": "'"$POLICY_ID"'",
    "contractPolicyId": "'"$POLICY_ID"'",
    "assetsSelector": {
      "@type": "Criterion",
      "operandLeft": "https://w3id.org/edc/v0.0.1/ns/id",
      "operator": "=",
      "operandRight": "'"$ASSET_ID"'"
    }
  }' | jq .
```

### Acción 2: emitir una VC (`FoobarCredential`) para el consumer

```bash
export PARTICIPANT_CONTEXT_B64="ZGlkOndlYjpjb25zdW1lci1pZGVudGl0eWh1YiUzQTcwODM6Y29uc3VtZXI="
export ISSUER_DID="did:web:dataspace-issuer-service%3A10016:issuer"
export REQUEST_ID="cred-demo-$(date +%s)"
```

```bash
curl -s -X POST "$IH_CONSUMER/api/identity/v1alpha/participants/$PARTICIPANT_CONTEXT_B64/credentials/request" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY_IH" \
  -d '{
    "issuerDid": "'"$ISSUER_DID"'",
    "holderPid": "'"$REQUEST_ID"'",
    "credentials": [
      {
        "format": "VC1_0_JWT",
        "type": "FoobarCredential",
        "id": "demo-credential-def-2"
      }
    ]
  }'
```

### Acción 3: esperar estado `ISSUED` y visualizar la VC

```bash
for i in {1..12}; do
  STATUS=$(curl -s "$IH_CONSUMER/api/identity/v1alpha/participants/$PARTICIPANT_CONTEXT_B64/credentials/request/$REQUEST_ID" \
    -H "x-api-key: $API_KEY_IH" | jq -r '.status // empty')
  echo "poll $i status=$STATUS"
  if [ "$STATUS" = "ISSUED" ]; then
    break
  fi
  sleep 2
done
```

```bash
curl -s "$IH_CONSUMER/api/identity/v1alpha/participants/$PARTICIPANT_CONTEXT_B64/credentials?type=FoobarCredential" \
  -H "x-api-key: $API_KEY_IH" \
  | jq '.[0].verifiableCredential.credential.credentialSubject[0]'
```

### Qué contar

- “Hemos añadido un activo y una policy nuevos sin tocar el seed base.”
- “La emisión de VC se ejecuta on-demand vía DCP (`credentials/request`).”
- “El claim `membershipType` en la credencial emitida es la evidencia que usamos para el caso ‘consumer EU’ en esta demo.”

### Resultado esperado

- `asset-membership-demo-1`, `require-membership-demo`, `membership-demo-def` creados.
- El `request status` pasa por `CREATED/REQUESTED` y llega a `ISSUED`.
- Se visualiza una `FoobarCredential` en el consumer IdentityHub.

## 5) Modo express (7–10 min)

Si vas justo de tiempo, usa solo esto:

```bash
./deployment/compose/seed-compose.sh
./deployment/compose/smoke-compose.sh
curl -s -H "Host: consumer-identityhub:7083" http://localhost:7083/consumer/did.json | jq '{id, service}'
curl -s -H "Host: provider-identityhub:7083" http://localhost:7093/provider/did.json | jq '{id, service}'
```

Narrativa express:

1. “Seed configura assets, políticas y participantes.”
2. “Smoke ejecuta el flujo E2E completo y valida la descarga final.”
3. “Cerramos con identidad y DIDs en IdentityHub.”

## 6) Plan de contingencia (si algo falla en vivo)

### Error típico: `catalog/request` devuelve `502` o `invalid_client`

```bash
cd deployment/compose
docker compose down -v
docker compose up -d
cd ../..
./deployment/compose/seed-compose.sh
./deployment/compose/smoke-compose.sh
```

### Error típico: servicios tardan en arrancar

```bash
SEED_WAIT_TIMEOUT_SECONDS=300 ./deployment/compose/seed-compose.sh
```

### Error típico: DID endpoint devuelve `204 No Content`

Con `did:web`, IdentityHub resuelve por `Host`. En local debes forzar el host correcto:

```bash
curl -s -H "Host: consumer-identityhub:7083" http://localhost:7083/consumer/did.json | jq '{id, service}'
curl -s -H "Host: provider-identityhub:7083" http://localhost:7093/provider/did.json | jq '{id, service}'
```

### Error típico: credential request queda en `ERROR`

Verifica que el payload use `type` e `id` dentro de `credentials` (no `credentialType`):

```bash
"credentials": [{
  "format": "VC1_0_JWT",
  "type": "FoobarCredential",
  "id": "demo-credential-def-2"
}]
```

Además, usa un `holderPid` simple (por ejemplo `cred-demo-<timestamp>`) para que el
`requestId` no tenga caracteres problemáticos al consultar estado.

### Error típico: puerto ocupado

```bash
cd deployment/compose
docker compose ps
docker compose logs --tail=100 <service>
```
