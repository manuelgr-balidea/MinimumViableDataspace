# Speaker Notes (1 página) — Demo MVD Compose

## Mensaje principal

“En esta demo mostramos cómo un `provider` publica datos con políticas, un `consumer` los descubre en un `federated catalog`, negocia y transfiere de forma segura, apoyado por `IdentityHub` para identidad y confianza.”

## Agenda rápida (20 min)

| Tiempo | Bloque | Qué digo | Evidencia visual sugerida |
|---|---|---|---|
| 1 min | Contexto | “Todo corre en local con Compose, sin depender de K8s para esta demo.” | Captura de `docker compose ps` con servicios `Up/healthy` |
| 4 min | Provider | “Cada provider gestiona activos y políticas de acceso de forma autónoma.” | Lista de assets (`asset-1`, `asset-2`) para QnA y Manufacturing |
| 4 min | Federated Catalog | “El consumer descubre oferta federada sin conocer cada provider internamente.” | Resultado de `catalog/request` + caché de catálogo con datasets |
| 6 min | Consumer E2E | “Aquí se ejecuta el ciclo completo: descubrimiento, negociación, transferencia y descarga.” | Salida de Newman `ControlPlane Management` en verde + `200` en download |
| 4 min | IdentityHub | “IdentityHub gestiona participantes, DIDs y endpoints de confianza.” | Participantes `did:web:...` + DID docs (`id`, `service`) |
| 1 min | Cierre | “Capacidad demostrada: gobernanza, descubrimiento federado, intercambio seguro e identidad descentralizada.” | Slide resumen con 4 bullets |

## Guion hablado por bloque

## 1) Contexto

- “La arquitectura separa responsabilidades: provider publica, consumer consume, catálogo federa, IdentityHub asegura identidad.”
- “Este setup local replica el comportamiento funcional esperado para entornos mayores.”

## 2) Provider

- “Mostramos que hay activos en dos dominios: QnA y Manufacturing.”
- “La clave aquí es la gobernanza: no es solo ‘datos’, son datos con política.”

## 3) Federated Catalog

- “El catálogo federado es la puerta de descubrimiento: reduce acoplamiento entre organizaciones.”
- “El consumer consulta una vista agregada y obtiene ofertas candidatas.”

## 4) Consumer E2E

- “Este es el corazón del negocio: negociación contractual + transferencia técnica.”
- “Cuando aparece `Download Data from Public API = 200`, el caso de uso quedó cerrado de punta a punta.”

## 5) IdentityHub

- “IdentityHub mantiene el contexto de participante, claves y endpoints.”
- “Los DIDs permiten confianza verificable entre los componentes del ecosistema.”
- “En local con `did:web`, la resolución depende del header `Host`; con `localhost` sin ese header puede devolver `204` vacío.”

Comando rápido (si quieres enseñar DID en vivo):

```bash
curl -s -H "Host: consumer-identityhub:7083" http://localhost:7083/consumer/did.json | jq '{id, service}'
curl -s -H "Host: provider-identityhub:7083" http://localhost:7093/provider/did.json | jq '{id, service}'
```

## Frases de transición (útiles en vivo)

- “Con el inventario de activos validado, pasamos a descubrimiento federado.”
- “Una vez descubierto el activo, ahora demostramos la contratación y el acceso real al dato.”
- “Antes de cerrar, conectamos el flujo con la capa de identidad y confianza.”

## Si te hacen preguntas difíciles

- **¿Qué pasa si falla STS (`invalid_client`)?**  
  “Tenemos recuperación definida: reinicio limpio + seed + smoke para re-sincronizar credenciales.”
- **¿Por qué Compose y no K8s en demo?**  
  “Para velocidad y repetibilidad local; la lógica funcional es la misma.”
- **¿Qué demuestra negocio aquí?**  
  “Intercambio de datos gobernado por políticas, con interoperabilidad y trazabilidad técnica.”
- **¿Por qué el DID a veces responde vacío (`204`)?**  
  “Porque `did:web` usa resolución por host. En local se corrige enviando `Host: consumer-identityhub:7083` o `Host: provider-identityhub:7083` en el `curl`.”

## Cierre de 20 segundos

“En resumen: demostramos publicación gobernada de activos, descubrimiento federado, negociación y transferencia seguras, y gestión de identidad descentralizada; todo en un entorno reproducible para acelerar adopción.”
