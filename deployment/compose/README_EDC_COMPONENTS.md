## Integración con Docker
Cada launcher genera un JAR que se empaqueta en una imagen Docker usando un Dockerfile propio. El proceso típico es:

1. Compilar el launcher (por ejemplo, `./gradlew :launchers:dataplane:build`).
2. Generar el JAR en `launchers/<servicio>/build/libs/`.
3. Usar el Dockerfile en `launchers/<servicio>/src/main/docker/Dockerfile` para crear la imagen.

Ejemplo de Dockerfile:
```
FROM eclipse-temurin:23.0.2_7-jre-alpine
ARG JAR
WORKDIR /app
COPY ${JAR} edc-dataplane.jar
EXPOSE 8080
CMD ["java", "-jar", "edc-dataplane.jar"]
```

En el build.gradle.kts del launcher se configura la tarea `dockerize` para construir la imagen y pasar el JAR como argumento.

Así, cada servicio EDC se despliega como un contenedor Docker independiente, listo para integrarse en arquitecturas como Docker Compose o Kubernetes.
# EDC Deployment: Launchers, BOMs y Extensibilidad

Este proyecto utiliza una arquitectura modular basada en launchers y BOMs (Bills-of-Material) para desplegar componentes EDC (Eclipse Dataspace Components) como servicios independientes.

## ¿Qué es un launcher?
Un launcher es un módulo que define la configuración, dependencias y punto de entrada de un servicio EDC (por ejemplo: controlplane, dataplane, identityhub, catalog-server, issuerservice). Cada launcher tiene su propia carpeta bajo `launchers/` y genera un JAR específico para su rol.

## ¿Qué es un BOM?
Un BOM es un meta-módulo que agrupa dependencias recomendadas para un tipo de servicio. Al incluir un BOM en el `build.gradle.kts` de un launcher, se heredan automáticamente todas las dependencias necesarias para ese componente, sin tener que declararlas una por una.

Ejemplo de BOMs:
- `controlplane-base-bom`, `controlplane-dcp-bom`
- `dataplane-base-bom`
- `identityhub-bom`, `identityhub-with-sts-bom`
- `federatedcatalog-base-bom`, `federatedcatalog-dcp-bom`

## ¿Cómo se genera cada servicio?
Cada launcher compila su propio JAR usando el código base del conector EDC y las dependencias definidas por su BOM. Los launchers comparten gran parte del código, pero cada uno puede incluir extensiones o módulos específicos según su función.

## Extensibilidad
Para extender un componente:
1. Crea una nueva extensión en el proyecto (por ejemplo, en `extensions/`).
2. Añade la extensión como dependencia en el `build.gradle.kts` del launcher correspondiente.
3. El launcher empaquetará la extensión en su JAR y la ejecutará al iniciar el servicio.

## Ejemplo de estructura
```
launchers/
  controlplane/
    build.gradle.kts
    src/main/java/
  dataplane/
    build.gradle.kts
    src/main/java/
  identity-hub/
    build.gradle.kts
    src/main/java/
extensions/
  superuser-seed/
  did-example-resolver/
  ...
```

## Resumen
- Los BOMs definen qué módulos/extensiones se incluyen en cada servicio.
- Los launchers generan JARs independientes, pero comparten el código base del conector.
- Puedes extender cualquier servicio creando nuevas extensiones y agregándolas como dependencias.

---

## Versiones utilizadas
Las versiones de los BOMs y módulos EDC se definen en el archivo `gradle/libs.versions.toml`.
Por ejemplo:

- Versión principal de EDC: `edc = "0.14.1"`
- BOMs utilizados:
  - `edc-bom-controlplane = { module = "org.eclipse.edc:controlplane-dcp-bom", version.ref = "edc" }`
  - `edc-bom-dataplane = { module = "org.eclipse.edc:dataplane-base-bom", version.ref = "edc" }`
  - `edc-bom-identityhub = { module = "org.eclipse.edc:identityhub-bom", version.ref = "edc" }`
  - `edc-bom-issuerservice = { module = "org.eclipse.edc:issuerservice-bom", version.ref = "edc" }`

Esto significa que todos los BOMs y módulos EDC están usando la versión definida en la variable `edc`.
Si quieres consultar o cambiar la versión, revisa este archivo.

¿Dudas o quieres ejemplos de cómo crear una extensión? ¡Consulta este README o pregunta al equipo!

---
Nota: Este documento ha sido creado por Manuel Gandarela, Balidea.
