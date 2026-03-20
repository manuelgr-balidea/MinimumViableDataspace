# DSP Advanced Guide (Compose)

Este documento explica, de forma didactica, el flujo de la demo avanzada de Compose para que una tercera persona pueda entender que ocurre y por que.

No cambia ni reemplaza los scripts existentes. Solo los traduce a una ejecucion manual comentada.

## 1. Que cubre esta guia

Flujo funcional:
1. Crear un asset nuevo en Provider QnA.
2. Crear una policy de acceso basada en `MembershipCredential`.
3. Crear una policy contractual basada en `DataAccess.level=processing`.
4. Crear un `ContractDefinition` que vincula asset + policies.
5. Solicitar una VC al Issuer Service desde el IdentityHub del consumer.
6. Esperar a estado `ISSUED`.
7. Verificar la credencial emitida.
8. Limpiar recursos de demo (opcional).

Este flujo es equivalente al comportamiento de:
- `deployment/compose/demo-advanced.sh`
- `deployment/compose/demo-advanced-clean.sh`

## 2. Prerequisitos

Desde la raiz del repositorio:

```bash
cd deployment/compose
docker compose up -d
cd ../..
./deployment/compose/seed-compose.sh
```

Dependencias locales:
- `curl`
- `jq`

## 3. Variables de entorno

```bash
export CP_QNA="${CP_QNA:-http://localhost:8191}"
export IH_CONSUMER="${IH_CONSUMER:-http://localhost:7081}"

export API_KEY_CP="${API_KEY_CP:-password}"
export API_KEY_IH="${API_KEY_IH:-c3VwZXItdXNlcg==.c3VwZXItc2VjcmV0LWtleQo=}"

export PARTICIPANT_CONTEXT_B64="${PARTICIPANT_CONTEXT_B64:-ZGlkOndlYjpjb25zdW1lci1pZGVudGl0eWh1YiUzQTcwODM6Y29uc3VtZXI=}"
export ISSUER_DID="${ISSUER_DID:-did:web:dataspace-issuer-service%3A10016:issuer}"

export ASSET_ID="${ASSET_ID:-asset-membership-demo-1}"
export ACCESS_POLICY_ID="${ACCESS_POLICY_ID:-require-membership-demo}"
export CONTRACT_POLICY_ID="${CONTRACT_POLICY_ID:-require-dataprocessor-demo}"
export DEF_ID="${DEF_ID:-membership-demo-def}"

export CREDENTIAL_TYPE="${CREDENTIAL_TYPE:-FoobarCredential}"
export CREDENTIAL_DEF_ID="${CREDENTIAL_DEF_ID:-demo-credential-def-2}"
export REQUEST_ID="${REQUEST_ID:-cred-demo-$(date +%s)}"

export POLL_ATTEMPTS="${POLL_ATTEMPTS:-12}"
export POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-2}"
```

## 4. Flujo completo explicado

## Paso 1. Crear asset

En este paso se crea un asset de demo en el provider QnA. El `dataAddress` apunta a una API HTTP publica para simplificar la prueba.

```bash
curl -i -s -X POST "$CP_QNA/api/management/v3/assets" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY_CP" \
  -d '{
    "@context": ["https://w3id.org/edc/connector/management/v0.0.1"],
    "@id": "'"$ASSET_ID"'",
    "@type": "Asset",
    "properties": {
      "description": "Membership demo asset"
    },
    "dataAddress": {
      "@type": "DataAddress",
      "type": "HttpData",
      "baseUrl": "https://jsonplaceholder.typicode.com/todos",
      "proxyPath": "true",
      "proxyQueryParams": "true"
    }
  }'
```

HTTP esperado: `200`, `201`, `204` o `409` (si ya existia).

## Paso 2. Crear policies de acceso y contrato

La policy de acceso define visibilidad por membresia (`MembershipCredential == active`).
La policy contractual replica el comportamiento de `asset-1` y exige `DataAccess.level == processing`.

```bash
curl -i -s -X POST "$CP_QNA/api/management/v3/policydefinitions" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY_CP" \
  -d '{
    "@context": ["https://w3id.org/edc/connector/management/v0.0.1"],
    "@type": "PolicyDefinition",
    "@id": "'"$ACCESS_POLICY_ID"'",
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
  }'

curl -i -s -X POST "$CP_QNA/api/management/v3/policydefinitions" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY_CP" \
  -d '{
    "@context": ["https://w3id.org/edc/connector/management/v0.0.1"],
    "@type": "PolicyDefinition",
    "@id": "'"$CONTRACT_POLICY_ID"'",
    "policy": {
      "@type": "Set",
      "obligation": [
        {
          "action": "use",
          "constraint": {
            "leftOperand": "DataAccess.level",
            "operator": "eq",
            "rightOperand": "processing"
          }
        }
      ]
    }
  }'
```

HTTP esperado: `200`, `201`, `204` o `409`.

## Paso 3. Crear contract definition

Este paso conecta asset y policy para que el provider pueda ofrecer el asset bajo esas condiciones.

```bash
curl -i -s -X POST "$CP_QNA/api/management/v3/contractdefinitions" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY_CP" \
  -d '{
    "@context": ["https://w3id.org/edc/connector/management/v0.0.1"],
    "@id": "'"$DEF_ID"'",
    "@type": "ContractDefinition",
    "accessPolicyId": "'"$ACCESS_POLICY_ID"'",
    "contractPolicyId": "'"$CONTRACT_POLICY_ID"'",
    "assetsSelector": {
      "@type": "Criterion",
      "operandLeft": "https://w3id.org/edc/v0.0.1/ns/id",
      "operator": "=",
      "operandRight": "'"$ASSET_ID"'"
    }
  }'
```

HTTP esperado: `200`, `201`, `204` o `409`.

## Paso 4. Solicitar credencial verificable

La solicitud se envia al IdentityHub del consumer. Se guarda cabecera `Location` para recuperar el `requestId` si el servicio lo devuelve ahi.

```bash
REQUEST_HEADERS="$(mktemp)"
REQUEST_BODY="$(mktemp)"

REQUEST_HTTP_CODE="$(curl -s -D "$REQUEST_HEADERS" -o "$REQUEST_BODY" -w "%{http_code}" -X POST \
  "$IH_CONSUMER/api/identity/v1alpha/participants/$PARTICIPANT_CONTEXT_B64/credentials/request" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY_IH" \
  -d '{
    "issuerDid": "'"$ISSUER_DID"'",
    "holderPid": "'"$REQUEST_ID"'",
    "credentials": [
      {
        "format": "VC1_0_JWT",
        "type": "'"$CREDENTIAL_TYPE"'",
        "id": "'"$CREDENTIAL_DEF_ID"'"
      }
    ]
  }')"

echo "HTTP credential request: $REQUEST_HTTP_CODE"
cat "$REQUEST_BODY" | jq .

LOCATION_HEADER="$(grep -i '^Location:' "$REQUEST_HEADERS" | tr -d '\r' | awk '{print $2}')"
if [ -n "$LOCATION_HEADER" ]; then
  REQUEST_ID="$(basename "$LOCATION_HEADER")"
fi

echo "REQUEST_ID final: $REQUEST_ID"
rm -f "$REQUEST_HEADERS" "$REQUEST_BODY"
```

HTTP esperado: `200`, `201` o `204`.

## Paso 5. Polling hasta estado ISSUED

La emision de credencial es asincrona. Se consulta el estado hasta llegar a `ISSUED`.

```bash
FINAL_STATUS=""
for ((i=1; i<=POLL_ATTEMPTS; i++)); do
  STATUS_RESPONSE="$(curl -s \
    "$IH_CONSUMER/api/identity/v1alpha/participants/$PARTICIPANT_CONTEXT_B64/credentials/request/$REQUEST_ID" \
    -H "x-api-key: $API_KEY_IH")"

  FINAL_STATUS="$(echo "$STATUS_RESPONSE" | jq -r '.status // empty' 2>/dev/null || true)"
  echo "poll $i/$POLL_ATTEMPTS status=${FINAL_STATUS:-unknown}"

  if [ "$FINAL_STATUS" = "ISSUED" ]; then
    break
  fi

  if [ "$FINAL_STATUS" = "ERROR" ]; then
    echo "$STATUS_RESPONSE" | jq .
    break
  fi

  sleep "$POLL_INTERVAL_SECONDS"
done
```

## Paso 6. Verificar credencial emitida

Se consulta el almacenamiento de credenciales del participante para ver el `credentialSubject` emitido.

```bash
curl -s "$IH_CONSUMER/api/identity/v1alpha/participants/$PARTICIPANT_CONTEXT_B64/credentials?type=$CREDENTIAL_TYPE" \
  -H "x-api-key: $API_KEY_IH" \
  | jq '.[0].verifiableCredential.credential.credentialSubject[0]'
```

## Paso 7. Limpieza opcional

Para repetir la demo sin residuos, borra en este orden: contract definition, policy, asset.

```bash
curl -i -s -X DELETE "$CP_QNA/api/management/v3/contractdefinitions/$DEF_ID" \
  -H "x-api-key: $API_KEY_CP"

curl -i -s -X DELETE "$CP_QNA/api/management/v3/policydefinitions/$CONTRACT_POLICY_ID" \
  -H "x-api-key: $API_KEY_CP"

curl -i -s -X DELETE "$CP_QNA/api/management/v3/policydefinitions/$ACCESS_POLICY_ID" \
  -H "x-api-key: $API_KEY_CP"

curl -i -s -X DELETE "$CP_QNA/api/management/v3/assets/$ASSET_ID" \
  -H "x-api-key: $API_KEY_CP"
```

HTTP esperado para DELETE: `200`, `204` o `404`.


## 5. Troubleshooting rapido

Caso: `REQUEST_ID` invalido o vacio.
- Revisa respuesta del Paso 4.
- Repite Paso 4 con `REQUEST_ID` nuevo.

Caso: estado no llega a `ISSUED`.
- Aumenta espera: `POLL_ATTEMPTS=30`.
- Revisa logs:

```bash
cd deployment/compose
docker compose logs --tail=120 consumer-identityhub dataspace-issuer-service
```

Caso: estado `ERROR` en polling.
- Inspecciona el JSON completo impreso en Paso 5.
- Verifica que `issuerDid`, `type` y `id` en la solicitud coincidan con el entorno seed.

Caso: no aparece credencial en Paso 6.
- Confirma `CREDENTIAL_TYPE` correcto.
- Repite consulta tras unos segundos.

Caso: la negociacion de este asset se queda en `REQUESTED`.
- Verifica que este asset se haya creado con `CONTRACT_POLICY_ID=require-dataprocessor-demo`.
- Verifica que tu `ContractRequest` incluya constraint `DataAccess.level=processing` (como en `asset-1`).

## 7. Referencias y equivalencia automatica

Ejecucion automatica del mismo flujo:

```bash
./deployment/compose/demo-advanced.sh
```

Ejecucion automatica con limpieza:

```bash
./deployment/compose/demo-advanced-clean.sh
```

Si necesitas centrarte solo en negociacion + transferencia DSP, consulta:
- `deployment/compose/README_DSP_NEGOTIATION.md`
