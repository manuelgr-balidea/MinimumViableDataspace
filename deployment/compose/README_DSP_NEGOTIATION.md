# Negociacion DSP en MVD Compose (Guia Manual)

Este README esta enfocado en explicar la negociacion de contrato y la transferencia entre Consumer y Provider en el MVD con Docker Compose.
Para una prueba completa, se recomienda crear primero el asset en `README_DSP_ADVANCED.md` y despues continuar aqui.

Objetivo:
- descubrir una oferta en catalogo
- iniciar la contract negotiation
- esperar a estado `FINALIZED`
- obtener el `contractAgreementId`
- iniciar la transferencia de datos
- obtener el token EDR
- descargar datos con ese token

## 1. Que se negocia exactamente

En este flujo no se negocia el dato directamente, se negocia el acuerdo de uso del asset.

Piezas clave:
- `odrl:hasPolicy.@id`: identificador de la oferta publicada por el provider para un asset.
- `ContractRequest`: solicitud que envia el consumer usando ese `policy.@id`.
- `state`: estado de la negociacion (la meta es `FINALIZED`).
- `contractAgreementId`: resultado final para poder iniciar transferencias.

## 2. Pre-requisitos

Desde la raiz del repo:

```bash
cd deployment/compose
docker compose up -d
cd ../..
./deployment/compose/seed-compose.sh
```

Dependencias locales:
- `curl`
- `jq`

## 3. Variables de entorno para negociacion

```bash
export CP_CONSUMER="${CP_CONSUMER:-http://localhost:8081}"
export CP_QNA="${CP_QNA:-http://localhost:8191}"
export CATALOG_QUERY="${CATALOG_QUERY:-http://localhost:8084}"
export CATALOG_SERVER_DSP_URL="${CATALOG_SERVER_DSP_URL:-http://provider-catalog-server-controlplane:8082}"
export PROVIDER_DSP_URL="${PROVIDER_DSP_URL:-http://provider-qna-controlplane:8082}"
export PROVIDER_ID="${PROVIDER_ID:-did:web:provider-identityhub%3A7083:provider}"
export API_KEY_CP="${API_KEY_CP:-password}"
export PROVIDER_PUBLIC_API="${PROVIDER_PUBLIC_API:-http://localhost:12001}"

# Si vienes de README_DSP_ADVANCED, reutiliza exactamente el mismo ASSET_ID.
export ASSET_ID="${ASSET_ID:-asset-membership-demo-1}"

export POLL_ATTEMPTS="${POLL_ATTEMPTS:-15}"
export POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-2}"
export TRANSFER_POLL_ATTEMPTS="${TRANSFER_POLL_ATTEMPTS:-20}"
export TRANSFER_POLL_INTERVAL_SECONDS="${TRANSFER_POLL_INTERVAL_SECONDS:-2}"
```

## 4. Paso a paso de la negociacion

## Paso 0. Verificar que el asset exista en provider QnA

Antes de negociar, valida que el asset objetivo realmente exista en el provider correcto.

```bash
ASSET_PRESENT="$(curl -s -X POST "$CP_QNA/api/management/v3/assets/request" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY_CP" \
  -d '{"@context":["https://w3id.org/edc/connector/management/v0.0.1"],"@type":"QuerySpec"}' \
  | jq -r --arg A "$ASSET_ID" '[ .[] | select(."@id" == $A) ] | length')"

echo "ASSET_PRESENT=$ASSET_PRESENT"
```

Resultado esperado: `ASSET_PRESENT=1`.

## Paso 1. Refrescar catalogo federado

Forzamos una solicitud de catalogo DSP para poblar/actualizar cache del consumer.

```bash
curl -s -X POST "$CP_CONSUMER/api/management/v3/catalog/request" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY_CP" \
  -d "{
    \"@context\":[\"https://w3id.org/edc/connector/management/v0.0.1\"],
    \"@type\":\"CatalogRequest\",
    \"counterPartyAddress\":\"$PROVIDER_DSP_URL/api/dsp\",
    \"counterPartyId\":\"$PROVIDER_ID\",
    \"protocol\":\"dataspace-protocol-http\",
    \"querySpec\":{\"offset\":0,\"limit\":50}
  }" >/dev/null
```

Opcional: refrescar tambien via Catalog Server (topologia completa de la demo).

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
  }" >/dev/null
```

Consulta rapida para comprobar si el asset ya aparece en cache del consumer:

```bash
CATALOG_HIT_COUNT="$(curl -s -X POST "$CATALOG_QUERY/api/catalog/v1alpha/catalog/query" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY_CP" \
  -d '{"@context":["https://w3id.org/edc/connector/management/v0.0.1"],"@type":"QuerySpec"}' \
  | jq -r --arg ASSET_ID "$ASSET_ID" --arg ENDPOINT "${PROVIDER_DSP_URL}/api/dsp" '
      [
        .[]
        | (
            [ { service: ."dcat:service", dataset: ."dcat:dataset" } ]
            +
            (
              (."dcat:catalog" // [])
              | if type=="array" then . else [.] end
              | map({ service: ."dcat:service", dataset: ."dcat:dataset" })
            )
          )[]
        | select((.service."dcat:endpointURL" // "") == $ENDPOINT)
        | (.dataset // [])
        | if type=="array" then .[] else . end
        | select(type=="object" and (."@id" // "") == $ASSET_ID)
      ]
      | length
    ')"

echo "CATALOG_HIT_COUNT=$CATALOG_HIT_COUNT"
```

Resultado esperado: `CATALOG_HIT_COUNT` mayor que `0`.

## Paso 2. Extraer el `policy id` del asset objetivo

Se consulta el catalogo federado y se extrae el `policyId` del asset concreto que se quiere negociar (`$ASSET_ID`), filtrando ademas por el conector origen (QNA).

La negociacion necesitara el `odrl:hasPolicy.@id` exacto del asset (`$ASSET_ID`, por defecto `asset-membership-demo-1`).

```bash
POLICY_ID_ASSET="$(curl -s -X POST "$CATALOG_QUERY/api/catalog/v1alpha/catalog/query" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY_CP" \
  -d '{"@context":["https://w3id.org/edc/connector/management/v0.0.1"],"@type":"QuerySpec"}' \
  | jq -r --arg ASSET_ID "$ASSET_ID" --arg ENDPOINT "${PROVIDER_DSP_URL}/api/dsp" '
      [
        .[]
        | (
            [ { service: ."dcat:service", dataset: ."dcat:dataset" } ]
            +
            (
              (."dcat:catalog" // [])
              | if type=="array" then . else [.] end
              | map({ service: ."dcat:service", dataset: ."dcat:dataset" })
            )
          )[]
        | select((.service."dcat:endpointURL" // "") == $ENDPOINT)
        | (.dataset // [])
        | if type=="array" then .[] else . end
        | select(type=="object" and (."@id" // "") == $ASSET_ID)
        | (."odrl:hasPolicy" // [])
        | if type=="array" then .[] else . end
        | ."@id"
      ]
      | first // empty
    ')"

echo "POLICY_ID_ASSET=$POLICY_ID_ASSET"
```

Validacion rapida:

```bash
if [ -z "$POLICY_ID_ASSET" ]; then
  echo "ERROR: no se encontro odrl:hasPolicy.@id para $ASSET_ID"
  echo "Tip: repite Paso 1 para refrescar catalogo"
  echo "Tip: verifica Paso 0 (asset en provider QnA)"
  echo "Tip: si vienes de README_DSP_ADVANCED, confirma que ASSET_ID sea el mismo"
fi
```

Ese `policyId` es la referencia exacta a la oferta que el provider ha publicado para ese asset y sera obligatorio para generar una `ContractRequest`.

El `policyId` corresponde al identificador de una policy ODRL de tipo Offer publicada en el catalogo y actua como referencia unica a la oferta que el Consumer desea aceptar durante la negociacion. El provider define las policies y publica ofertas concretas basadas en ellas; el Consumer no construye nuevas policies, sino que selecciona y acepta una de las ofertas disponibles.

## Paso 3. Iniciar la contract negotiation

Enviamos `ContractRequest` con ese Offer ID al provider.

Con el `policyId` obtenido del catálogo, el Consumer inicia la negociación enviando una `ContractRequest` al Provider, indicando que desea usar el asset bajo las condiciones establecidas en esa oferta.

```bash
CONTRACT_NEGOTIATION_ID="$(curl -s -X POST "$CP_CONSUMER/api/management/v3/contractnegotiations" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY_CP" \
  -d "{
    \"@context\":[\"https://w3id.org/edc/connector/management/v0.0.1\"],
    \"@type\":\"ContractRequest\",
    \"counterPartyAddress\":\"$PROVIDER_DSP_URL/api/dsp\",
    \"counterPartyId\":\"$PROVIDER_ID\",
    \"protocol\":\"dataspace-protocol-http\",
    \"policy\":{
      \"@type\":\"Offer\",
      \"@id\":\"$POLICY_ID_ASSET\",
      \"assigner\":\"$PROVIDER_ID\",
      \"permission\":[],
      \"prohibition\":[],
      \"obligation\":{
        \"action\":\"use\",
        \"constraint\":{
          \"leftOperand\":\"DataAccess.level\",
          \"operator\":\"eq\",
          \"rightOperand\":\"processing\"
        }
      },
      \"target\":\"$ASSET_ID\"
    },
    \"callbackAddresses\":[]
  }" | jq -r '."@id" // empty')"

echo "CONTRACT_NEGOTIATION_ID=$CONTRACT_NEGOTIATION_ID"
```

Nota: recibir HTTP 2xx y un `@id` solo significa que la negociacion fue aceptada para proceso asincrono.

Durante la negociación, el Provider evalúa si el Consumer cumple las condiciones definidas en la policy (por ejemplo, requisitos de membresía o nivel de acceso). Estas condiciones no se validan únicamente contra el payload de la solicitud, sino en función del contexto del participante, sus credenciales y la configuración del conector.

## Paso 4. Polling de estado hasta `FINALIZED`

La negociación es un proceso asíncrono, por lo que tras iniciar la `ContractRequest` es necesario consultar periódicamente su estado hasta que alcance FINALIZED y se genere el `contractAgreementId`.

```bash
CONTRACT_AGREEMENT_ID=""
FINAL_STATE=""

for ((i=1; i<=POLL_ATTEMPTS; i++)); do
  NEGOTIATIONS_JSON="$(curl -s -X POST "$CP_CONSUMER/api/management/v3/contractnegotiations/request" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $API_KEY_CP" \
    -d '{"@context":["https://w3id.org/edc/connector/management/v0.0.1"],"@type":"QuerySpec"}')"

  FINAL_STATE="$(echo "$NEGOTIATIONS_JSON" | jq -r --arg NID "$CONTRACT_NEGOTIATION_ID" '
      ([ .[] | select(."@id" == $NID) ] | first | .state) // empty
    ')"

  CONTRACT_AGREEMENT_ID="$(echo "$NEGOTIATIONS_JSON" | jq -r --arg NID "$CONTRACT_NEGOTIATION_ID" '
      ([ .[] | select(."@id" == $NID) ] | first | .contractAgreementId) // empty
    ')"

  echo "poll $i/$POLL_ATTEMPTS state=${FINAL_STATE:-unknown} agreement=${CONTRACT_AGREEMENT_ID:-n/a}"

  if [ "$FINAL_STATE" = "FINALIZED" ] && [ -n "$CONTRACT_AGREEMENT_ID" ]; then
    break
  fi

  sleep "$POLL_INTERVAL_SECONDS"
done
```

## Paso 5. Resultado de negociacion

Cuando llega FINALIZED, tenemos un `contractAgreementId` listo para transferencia.

```bash
if [ "$FINAL_STATE" = "FINALIZED" ] && [ -n "$CONTRACT_AGREEMENT_ID" ]; then
  echo "OK: negociacion finalizada"
  echo "CONTRACT_AGREEMENT_ID=$CONTRACT_AGREEMENT_ID"
else
  echo "ERROR: negociacion no finalizo a tiempo"
fi
```

## 5. Paso a paso de la transferencia (desde `contractAgreementId`)

Una vez finalizada la negociacion, el `contractAgreementId` se usa para iniciar un `transfer process`.

En este escenario usamos `HttpData-PULL`, por lo que el Consumer no recibe el dato directamente en el POST inicial.
Primero obtiene una referencia de acceso (EDR) y despues descarga el dato con un token temporal.

## Paso 6. Iniciar transfer process

```bash
TRANSFER_PROCESS_ID="$(curl -s -X POST "$CP_CONSUMER/api/management/v3/transferprocesses" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY_CP" \
  -d "{
    \"@context\":[\"https://w3id.org/edc/connector/management/v0.0.1\"],
    \"assetId\":\"$ASSET_ID\",
    \"counterPartyAddress\":\"$PROVIDER_DSP_URL/api/dsp\",
    \"connectorId\":\"$PROVIDER_ID\",
    \"contractId\":\"$CONTRACT_AGREEMENT_ID\",
    \"dataDestination\":{\"type\":\"HttpProxy\"},
    \"protocol\":\"dataspace-protocol-http\",
    \"transferType\":\"HttpData-PULL\"
  }" | jq -r '."@id" // empty')"

echo "TRANSFER_PROCESS_ID=$TRANSFER_PROCESS_ID"
```

Si no hay `TRANSFER_PROCESS_ID`, normalmente hay una inconsistencia entre `assetId`, `contractId` o el provider objetivo.

## Paso 7. Consultar estado de transferencia hasta `STARTED`

```bash
TRANSFER_STATE=""

for ((i=1; i<=TRANSFER_POLL_ATTEMPTS; i++)); do
  TRANSFERS_JSON="$(curl -s -X POST "$CP_CONSUMER/api/management/v3/transferprocesses/request" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $API_KEY_CP" \
    -d '{"@context":["https://w3id.org/edc/connector/management/v0.0.1"],"@type":"QuerySpec"}')"

  TRANSFER_STATE="$(echo "$TRANSFERS_JSON" | jq -r --arg TID "$TRANSFER_PROCESS_ID" '
      ([ .[] | select(."@id" == $TID) ] | first | .state) // empty
    ')"

  echo "poll $i/$TRANSFER_POLL_ATTEMPTS transferState=${TRANSFER_STATE:-unknown}"

  if [ "$TRANSFER_STATE" = "STARTED" ] || [ "$TRANSFER_STATE" = "COMPLETED" ]; then
    break
  fi

  sleep "$TRANSFER_POLL_INTERVAL_SECONDS"
done
```

Para `HttpData-PULL`, tener estado `STARTED` suele ser suficiente para obtener el EDR.

## Paso 8. Obtener EDR (endpoint + authorization token)

```bash
EDR_JSON="$(curl -s "$CP_CONSUMER/api/management/v3/edrs/$TRANSFER_PROCESS_ID/dataaddress" \
  -H "x-api-key: $API_KEY_CP")"

EDR_ENDPOINT="$(echo "$EDR_JSON" | jq -r '.endpoint // empty')"
EDR_AUTHORIZATION="$(echo "$EDR_JSON" | jq -r '.authorization // empty')"

echo "EDR_ENDPOINT=$EDR_ENDPOINT"
echo "EDR_AUTHORIZATION_PRESENT=$([ -n "$EDR_AUTHORIZATION" ] && echo yes || echo no)"
```

El `endpoint` del EDR puede venir con hostname interno de Docker (por ejemplo `provider-qna-dataplane`).
Si ejecutas desde host local, suele ser mas fiable usar el puerto publicado en `localhost`.

## Paso 9. Descargar el dato usando el token EDR

```bash
curl -s "$PROVIDER_PUBLIC_API/api/public" \
  -H "Authorization: $EDR_AUTHORIZATION" \
  | jq .
```

Importante: no anteponer `Bearer ` manualmente si el token ya viene preparado en `authorization`.

## Paso 10. Verificacion final del flujo

```bash
if [ "$FINAL_STATE" = "FINALIZED" ] \
  && [ -n "$CONTRACT_AGREEMENT_ID" ] \
  && [ -n "$TRANSFER_PROCESS_ID" ] \
  && [ -n "$EDR_AUTHORIZATION" ]; then
  echo "OK: flujo de negociacion + transferencia completo"
else
  echo "ERROR: el flujo no quedo completo; revisar pasos de estado y EDR"
fi
```

## 6. Troubleshooting rapido

Caso: `POLICY_ID_ASSET` vacio.
- Repite Paso 1.
- Verifica Paso 0 para confirmar que el asset exista en QnA.
- Si creaste el asset en `README_DSP_ADVANCED.md`, reutiliza exactamente ese `ASSET_ID`.
- Verifica seed: `./deployment/compose/seed-compose.sh`.

Caso: negociacion no llega a `FINALIZED`.
- Espera mas (`POLL_ATTEMPTS=30`).
- Revisa logs:

```bash
cd deployment/compose
docker compose logs --tail=120 consumer-controlplane provider-qna-controlplane
```

Caso: error 4xx en `contractnegotiations`.
- Verifica que `policy.@id` venga del catalogo (no inventado).
- Verifica `counterPartyAddress` y `counterPartyId` del provider objetivo.

Caso: transferencia no llega a `STARTED`.
- Verifica que `CONTRACT_AGREEMENT_ID` venga de una negociacion `FINALIZED`.
- Aumenta espera (`TRANSFER_POLL_ATTEMPTS=30`).
- Revisa logs de controlplane consumer/provider.

Caso: `EDR_AUTHORIZATION` vacio.
- Espera unos segundos y repite Paso 8.
- Verifica que el `TRANSFER_PROCESS_ID` exista en `/transferprocesses/request`.

Caso: descarga da `401/403`.
- Verifica que estas enviando exactamente `Authorization: $EDR_AUTHORIZATION`.
- Prueba de nuevo porque el token EDR puede expirar.
- Si `EDR_ENDPOINT` usa hostname interno Docker, utiliza `http://localhost:12001/api/public`.

## 7. Referencias en el repo

- Coleccion usada como base: `deployment/postman/MVD.postman_collection.json` (`ControlPlane Management`).
- Flujo E2E completo (incluye transferencia): `deployment/compose/smoke-compose.sh`.
