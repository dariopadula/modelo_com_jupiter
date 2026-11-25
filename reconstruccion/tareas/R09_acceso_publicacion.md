# R09 - Acceso dual, extraccion y publicacion

- Estado: en proceso
- Prioridad: alta
- Dependencias: R08

## Contexto y objetivo

Completar portabilidad de extremo a extremo y activacion coherente.

## Fuentes originales concretas

- [funciones/backend_local_s3_utils.R](../../funciones/backend_local_s3_utils.R)
- [funciones/configuracion_impala.R](../../funciones/configuracion_impala.R)
- [funciones/cargar_datos_com.R](../../funciones/cargar_datos_com.R)
- [funciones/cargar_datos_levante.R](../../funciones/cargar_datos_levante.R)
- [scripts/publicar_ingesta_incremental.R](../../scripts/publicar_ingesta_incremental.R)
- [scripts/publicar_ingesta_incremental_windows.ps1](../../scripts/publicar_ingesta_incremental_windows.ps1)
- [scripts/validar_contrato_backend_local_s3.R](../../scripts/validar_contrato_backend_local_s3.R)
- [app_operativa_v2/R/datos_fuente.R](../../app_operativa_v2/R/datos_fuente.R)

## Entradas

Entregas, configuracion sin secretos y productos validados.

## Salidas

Adaptadores local/S3, extractor Impala y publicacion versionada recuperable.

## Plan propuesto

Separar origen/destino; probar fixtures; incorporar conexiones reales solo con ubicaciones confirmadas.

## Validacion

Matriz local/S3; fallo/recuperacion; una version por lectura; cierre desconocido rechazado; comprobacion remota separada.

Estado de validacion: matriz local/S3 simulada, fallos/recuperacion, integridad, lector fijo, extraccion sin red y app versionada implementados y probados. Regresion R08 y 26 comprobaciones R02 aprobadas. CLI local de publicacion/activacion aprobado. Pendientes obligatorios: consulta real Impala, lectura/escritura S3 real y app sobre esa publicacion. El usuario confirmo que aun no hay ubicaciones ni acceso; no se ejecutaron conexiones remotas.

## Criterio de finalizacion

Pruebas de contratos y validaciones reales obligatorias documentadas; sin atribuir al simulador prueba remota.

## Notas y decisiones pendientes

No rename transaccional en S3; no inventar buckets; no entrenar para probar transporte.

Implementados almacen por propietario, entrega fuentes_v2 con cierres explicitos, extractor mensual acotado y publicacion inmutable con inventario/verificacion y puntero recuperable. Local usa locks y respaldo; S3 exige un publicador por prefijo, sin CAS. App fija una version y cachea detalle por fecha/modelo. No se cambio el sistema original ni se inicio R10.

Configuracion reunida en ../.Renviron.example con valores locales activos y secciones S3/Impala comentadas, sin credenciales. Incluye precedencia de rutas y puerto y advierte que --vanilla omite .Renviron. El usuario difiere la validacion en Cloudera porque los datos de ingesta aun no estan subidos; R09 conserva estado en proceso por esa validacion pendiente.

Validacion del ejemplo ejecutada: readRenviron y rf_config aceptan el archivo; se comprobo cobertura de parametros, selectores locales y ausencia de placeholders activos. Resultado R09_ENV_EXAMPLE_OK, sin conexiones ni instalaciones.

Procedencia: patrones de backend_local_s3_utils e ingesta_incremental_utils (esquema crudo y contrato); consultas de cargar_datos_com/levante y configuracion_impala; publicacion recuperable de los publicadores originales. No se importan ni ejecutan esos archivos desde el sistema nuevo.

Evidencia, fallos de desarrollo registrados, limites y comandos reales aislados en [acceso/publicacion R09](../cerebro_rf/acceso_publicacion_r09.md). Piloto CLI local: runtime/r09_piloto_20261022_153807/almacen, version piloto_r09. La validacion remota sigue pendiente; no finalizar R09 ni habilitar R10 automaticamente.

Aplicar [politica de pruebas y corridas largas](../cerebro_rf/reglas_trabajo.md). No finalizar con validaciones obligatorias pendientes. No ejecutar la tarea siguiente sin instruccion.

[Volver al indice](index.md)


