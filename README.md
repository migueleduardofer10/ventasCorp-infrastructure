# ventasCorp-infrastructure

Infraestructura de Ventas Corp en AWS, escrita en Terraform. Crea las 13 lambdas, el API Gateway, las colas SQS, los buckets S3 y los permisos del diagrama de arquitectura. Solo usa las recetas de DevOps en [iac-templates](https://gitlab.com/delosi/devops/iac-templates). La única excepción son los `aws_lambda_permission` de `apigateway.tf`: el permiso que crea la receta de integración usa `/*/ANY/*` y API Gateway invoca con el verbo real, así que sin ese permiso manual con `/*/*` las APIs responden 500. Es el mismo arreglo que tiene api-delosi-integration-infrastructure.

Lo que **no** crea, porque no hay receta: bases de datos, EventBridge, WAF, secretos y la configuración de SES. Eso lo crea DevOps aparte. Lo que falta para el primer despliegue está en [PENDIENTES.md](PENDIENTES.md).

## Cómo funciona

Cada repo de aplicación (`api-invoicing-invoices`, `api-voucher-models`, etc.) se despliega en una lambda. El trabajo se reparte así:

| Quién | Qué hace |
|:--|:--|
| **Este repo (Terraform)** | Crea la lambda con su configuración: nombre, handler, memoria, timeout, VPC, rol IAM, permisos y variables de entorno. La crea con un código vacío. |
| **El pipeline de cada repo app** | Compila el proyecto y sube el `.zip` a la lambda que ya existe, con `aws lambda update-function-code`. |

Por eso hay dos cosas que tienen que coincidir entre este repo y cada repo app:

1. **El nombre de la lambda.** Terraform la crea como `Delosi-VentasCorp-{Function-Name}-Lambda-{Env}`, donde `{Function-Name}` es el nombre del repo sin el prefijo `api-`, con mayúscula inicial en cada palabra. Ese mismo nombre va en el `.gitlab-ci.yml` del repo app, en `DEV_AWS_FUNCTION_NAME`, `STG_AWS_FUNCTION_NAME` y `PRD_FUNCTION_NAME`. Si no coincide, el pipeline del app compila pero no encuentra dónde desplegar.

   ```
   repo api-voucher-models  →  Delosi-VentasCorp-Voucher-Models-Lambda-Dev
   ```

2. **El handler.** Le dice a AWS qué código ejecutar. Lo fija Terraform y el pipeline del app no lo toca. Si está mal, el despliegue sale en verde pero la lambda falla en cada llamada.

Las credenciales nunca pasan por este repo. Cada lambda lee sus secretos de Secrets Manager al arrancar; Terraform solo le pasa el nombre del secreto y le da permiso de lectura.

## Qué crea este repo

### Lambdas

Un bloque `module` por lambda en `lambdas.tf`. Hay tres tipos según quién las dispara. Las de API llevan handler de ensamblado; las de cola y la de scheduler llevan handler de método.

**Lambdas de API.** Las llama el frontend (o Micros) por HTTP a través del API Gateway. El handler es solo el nombre del ensamblado, el `AssemblyName` del `.csproj` que se despliega:

| Lambda (diagrama) | Repo | Ruta base | Handler |
|:--|:--|:--|:--|
| API-FACTURAS | api-invoicing-invoices | `/facturas` ✔ | `Delosi.InvoicingInvoices.Api` ✔ |
| API-CONFIG-APROBADORES | api-invoicing-config-approvers | `/api/v1/approvers` ✔ | `Delosi.Alfie.Invoicing.ConfigApprover.Api` ✔ |
| API-BANDEJA-APROBACIONES | api-invoicing-approval-tray | `/approval-tray` ✔ | `Delosi.Alfie.Invoicing.ApprovalTray.Api` ✔ |
| API-APROBACIONES | api-invoicing-approvals | `/approvals` ✔ | `Delosi.Alfie.Invoicing.Approvals.Api` ✔ |
| API-GESTOR | api-voucher-management | `/vouchers` ✔ | `Delosi.Alfie.Voucher.Management.Api` ✔ |
| API-MODELOS | api-voucher-models | `/voucher-models` ✔ | `Delosi.Alfie.Voucher.Model.Api` ✔ |
| API-MOTIVOS | api-voucher-reasons | `/voucher-reasons` ✔ | `Delosi.Alfie.Voucher.Reason.Api` ✔ |
| API-Maestros | api-master-data-service | `/master-data` | `Delosi.Alfie.Invoicing.MasterDataService.Api` |
| API-SYNC-VALES | api-voucher-redemption | `/voucher-redemptions` ✔ (la llama Micros) | `Delosi.Alfie.Voucher.Redemption.Api` ✔ |

**Lambdas de cola.** No tienen ruta: las despierta SQS cuando llega un mensaje. El handler es `Ensamblado::Namespace.Clase::Metodo`, el método que recibe los mensajes:

| Lambda (diagrama) | Repo | Cola | Ensamblado | Clase | Método |
|:--|:--|:--|:--|:--|:--|
| API-NOTIFICACION | api-invoicing-notifications | `notifications` | `Delosi.Alfie.Invoicing.Notifications.Functions` ✔ | `Delosi.Alfie.Invoicing.Notifications.Functions.NotificationFunction` ✔ | `FunctionHandler` ✔ |
| API-SYNC-FACTURACION | api-invoicing-sap-sync | `sap-sync` | `Delosi.Alfie.Invoicing.SapSync.Functions` ✔ | `Delosi.Alfie.Invoicing.SapSync.Functions.SapSyncFunction` ✔ | `FunctionHandler` ✔ |
| Generar PDF | api-voucher-document-generation (aún sin repo) | `document-generation` | `Delosi.Alfie.Document.Generation.Functions` ✔ | `Delosi.Alfie.Document.Generation.Functions.DocumentGenerationFunction` ✔ | `FunctionHandler` ✔ |

**Lambda de scheduler.** No tiene ruta: la despierta EventBridge Scheduler por horario. El handler tiene el mismo formato que las de cola, y el método recibe el JSON del evento:

| Lambda (diagrama) | Repo | Horario | Ensamblado | Clase | Método |
|:--|:--|:--|:--|:--|:--|
| API-MAESTROS API | api-master-data-sync | 2 veces al día | `Delosi.MasterDataSync` | `Delosi.MasterDataSync.Functions.MasterDataSyncFunction` | `FunctionHandler` |

El scheduler lo crea la receta con `enable_scheduler = true` en el bloque de la lambda: arma el schedule en EventBridge Scheduler, el rol que le permite invocarla y la asociación. No hay que crear nada más. Las horas están en `schedule_expression`.

Las filas con ✔ están confirmadas por su equipo. El resto son supuestos marcados con `A CONFIRMAR` en `lambdas.tf`: cada equipo debe confirmar su ruta base y su handler ([PENDIENTES.md](PENDIENTES.md), puntos 1 y 4).

Todas corren en VPC, con X-Ray activo y permiso de lectura sobre sus secretos. Las de API tienen timeout de 28 s porque el gateway corta a 29 s.

**Nombre en AWS.** Es el que va en el `.gitlab-ci.yml` de cada repo app. En stg y prd es el mismo terminado en `-Stg` y `-Prd`:

| Repo | Lambda en dev |
|:--|:--|
| api-invoicing-invoices | Delosi-VentasCorp-Invoicing-Invoices-Lambda-Dev |
| api-invoicing-config-approvers | Delosi-VentasCorp-Invoicing-Config-Approvers-Lambda-Dev |
| api-invoicing-approval-tray | Delosi-VentasCorp-Invoicing-Approval-Tray-Lambda-Dev |
| api-invoicing-approvals | Delosi-VentasCorp-Invoicing-Approvals-Lambda-Dev |
| api-invoicing-sap-sync | Delosi-VentasCorp-Invoicing-Sap-Sync-Lambda-Dev |
| api-invoicing-notifications | Delosi-VentasCorp-Invoicing-Notifications-Lambda-Dev |
| api-master-data-sync | Delosi-VentasCorp-Master-Data-Sync-Lambda-Dev |
| api-master-data-service | Delosi-VentasCorp-Master-Data-Service-Lambda-Dev |
| api-voucher-management | Delosi-VentasCorp-Voucher-Management-Lambda-Dev |
| api-voucher-models | Delosi-VentasCorp-Voucher-Models-Lambda-Dev |
| api-voucher-reasons | Delosi-VentasCorp-Voucher-Reasons-Lambda-Dev |
| api-voucher-redemption | Delosi-VentasCorp-Voucher-Redemption-Lambda-Dev |
| api-voucher-document-generation | Delosi-VentasCorp-Document-Generation-Lambda-Dev |

### API Gateway

Un solo API Gateway REST en `apigateway.tf`, `Delosi-VentasCorp-Main-Api-Gateway-{Env}` en AWS. Cada lambda de API cuelga de su ruta base con integración proxy: `/{ruta-base}/{proxy+}` → lambda. El gateway no conoce los endpoints reales, solo manda todo lo que empiece con la ruta base a la lambda, y la app resuelve el resto.

**La ruta base tiene que coincidir con el prefijo de la app.** En facturas, por ejemplo, es el `MapGroup("/facturas")` de `InvoiceEndpoints.cs`. Si la app define `/modelos/crear` pero el gateway usa `/voucher-models`, toda llamada responde 404.

La URL base sale en `terraform output api_invoke_url`. Un endpoint queda como `{url-base}/facturas/listar`.

Los métodos van con `authorization = NONE`: el gateway no valida nada, cada lambda valida su JWT. `/voucher-redemptions` la llama Micros, que no tiene JWT, y por ahora va abierta (ver [PENDIENTES.md](PENDIENTES.md), punto 10).

### Colas SQS

Cuatro colas en `sqs.tf`, cada una con su DLQ: tras 3 intentos fallidos el mensaje pasa a la cola muerta. Nombre en AWS: `Delosi-ventasCorp-{cola}{env}`.

| Cola | Quién publica | Quién consume | Para qué |
|:--|:--|:--|:--|
| `sap-sync` | invoicing-approvals | invoicing-sap-sync | Facturas aprobadas que hay que mandar a SAP |
| `notifications` | invoicing-approvals | invoicing-notifications | Correos que hay que enviar |
| `document-generation` | voucher-management | document-generation | Vales a los que hay que generar el PDF |
| `model-image-generation` | voucher-models | document-generation | Modelos a los que hay que generar el PNG |

La conexión cola → consumidor la hace Terraform con `sqs_event_sources` en el bloque de la lambda: AWS lee la cola y le entrega los mensajes a la lambda, que no necesita saber nada de la cola.

El que **publica** sí necesita la URL de la cola y permiso de escritura. La URL le llega como variable de entorno (PENDIENTES.md, punto 3); el permiso todavía no tiene receta (punto 9).

### Buckets S3

Dos buckets en `s3.tf`, con la receta `modules/s3`: versionado, cifrado AES256, acceso público bloqueado y HTTPS obligatorio. Nombre en AWS: `delosi-ventascorp-{bucket}-{env}`.

| Bucket | Lambda | Permiso | Variable de entorno | Prefijo |
|:--|:--|:--|:--|:--|
| `vales-s3` | document-generation | lectura y escritura | `S3_BUCKET_NAME` (la inyecta la receta) | `pdf/[ruc]/[factura]` |
| `models-s3` | voucher-models | lectura y escritura | `AWS__S3__BucketName` | `voucher-model/background-images` |
| `models-s3` | document-generation | lectura | `BackgroundImages__BucketName` | `voucher-model/background-images` |

### Permisos extra

| Lambda | Permiso | Para qué |
|:--|:--|:--|
| invoicing-notifications | Enviar correos por SES | Correos de facturas y vales |

### Secretos

Dos por ambiente, compartidos por todas las lambdas, creados por DevOps en Secrets Manager. Los tfvars solo guardan sus nombres:

```
delosi-alfie-ventascorp-{env}/db    → conexión a la base
delosi-alfie-ventascorp-{env}/app   → JWT, SAP, Micros, SES y demás configuración sensible
```

La lambda recibe los nombres en `DB_SECRET_NAME` y `APP_SECRET_NAME` y los lee al arrancar. Cada lambda lee solo las claves que le sirven: las de facturación `ConnectionStrings__Facturacion`, las de vales `ConnectionStrings__Vales` y las de maestros `ConnectionStrings__MasterData`. Ejemplo en dev:

`delosi-alfie-ventascorp-dev/db`
```json
{
  "ConnectionStrings__Facturacion": "Host=HOST;Port=5432;Database=facturacion_db;Username=USER;Password=PASSWORD;SSL Mode=VerifyFull;Root Certificate=/var/task/certificates/global-bundle.pem",
  "ConnectionStrings__Vales":       "Host=HOST;Port=5432;Database=vales_db;Username=USER;Password=PASSWORD;SSL Mode=VerifyFull;Root Certificate=/var/task/certificates/global-bundle.pem",
  "ConnectionStrings__MasterData":  "Host=HOST;Port=5432;Database=maestros_db;Username=USER;Password=PASSWORD;SSL Mode=VerifyFull;Root Certificate=/var/task/certificates/global-bundle.pem"
}
```

`delosi-alfie-ventascorp-dev/app`
```json
{
  "JwtAuth__Enabled": true,
  "JwtAuth__MetadataAddress": "https://IDP/.well-known/openid-configuration",
  "JwtAuth__ValidIssuer": "https://IDP",
  "JwtAuth__ValidAudience": "alfie-ventascorp",
  "Cors__AllowedOrigins": "https://www.alfie.pe",
  "Swagger__Enabled": false,
  "UserDirectory__BaseUrl": "https://...",
  "UserDirectory__ExistsPathTemplate": "/users/{0}/exists",
  "ApprovalScope__CompanyCodes": "<companyId>=<companyCode>;...",
  "DelosiApi__BaseUrl": "https://api.delosi.pe",
  "DelosiApi__TokenPath": "/oauth/token",
  "DelosiApi__ClientId": "xxxxx",
  "DelosiApi__ClientSecret": "xxxxx",
  "DelosiApi__Username": "xxxxx",
  "DelosiApi__Password": "xxxxx",
  "Messaging__MaxMessageBytes": 262144
}
```

| Bloque | Quién lo lee |
|:--|:--|
| `JwtAuth__*`, `Cors__*`, `Swagger__*` | Las 9 APIs |
| `UserDirectory__*` | invoicing-config-approvers |
| `ApprovalScope__*` | invoicing-approvals |
| `DelosiApi__*` | master-data-sync |
| `Messaging__*` | invoicing-sap-sync e invoicing-notifications |

Las claves las define el código de cada lambda y las asigna el equipo de desarrollo. El `__` se convierte en `:` en .NET: `JwtAuth__Enabled` se lee como `config["JwtAuth:Enabled"]`.

## Cómo desplegar

El pipeline de GitLab corre `validate` y `plan` solo; el `apply` es **manual**, se dispara desde el pipeline cuando alguien revisó el plan.

| Rama | Ambiente | Estado |
|:--|:--|:--|
| `develop` | dev | activo |
| `release` | stg | desactivado en `.gitlab-ci.yml` |
| `main` | prd | activo |

Variables CI/CD que necesita el proyecto en GitLab: `{DEV,STG,PRD}_AWS_ACCESS_KEY_ID`, `{DEV,STG,PRD}_AWS_SECRET_ACCESS_KEY`, `AWS_REGION` y `GITLAB_CI_TEST_TOKEN` (acceso a iac-templates).

Para probar en local:

```bash
terraform init -backend-config=backend-configs/backend-dev.tfvars
terraform plan -var-file=environments/dev.tfvars
```

## Cómo agregar una lambda

1. Un bloque `module` más en `lambdas.tf`, copiando uno del mismo tipo (API o cola).
2. Su `local` de variables de entorno en `main.tf`.
3. Si es de API, su bloque de ruta en `apigateway.tf` y sus entradas en el `trigger` y el `depends_on` del deployment.
4. Si es de cola, la cola en `sqs.tf` y el `sqs_event_sources` en el bloque de la lambda.
5. En el repo app, el nombre de la lambda en `DEV_AWS_FUNCTION_NAME`, `STG_AWS_FUNCTION_NAME` y `PRD_FUNCTION_NAME`.
