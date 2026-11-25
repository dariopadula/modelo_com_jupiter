# Acceso, extraccion y publicacion R09

Estado: implementado y validado localmente/S3 simulado. R09 en proceso por comprobaciones reales pendientes de ubicaciones y acceso, segun respuesta del usuario. No iniciar R10.

## Configuracion reunida

El ejemplo central es [`.Renviron.example`](../.Renviron.example), con valores locales activos y secciones comentadas para S3/Impala. Copiar a `.Renviron` privado en la raiz reconstruccion/ y arrancar R desde esa carpeta. `Rscript --vanilla` omite este archivo: para cargarlo automaticamente usar `Rscript scripts/run_app.R`, o configurar las variables en el entorno del proceso antes de usar --vanilla como en los comandos de esta guia. Los DCF siguen como ejemplos alternativos de rf_config; los scripts leen el entorno. No se modifico el Renviron.example del sistema original. La validacion real queda diferida por el usuario hasta disponer de los datos de ingesta en Cloudera.

## Responsabilidades

- `R/acceso/almacen.R`: transporte de archivos local/S3 por propietario. Respeta `INGESTA_INPUT_BACKEND`, `PIPELINE_STORAGE_BACKEND` y `APP_DATA_SOURCE` independientes. S3 usa la conexion administrada CML y un Python ya instalado; no instala paquetes ni guarda secretos.
- `R/acceso/entregas.R`: valida `fuentes_v2`, esquema crudo, particiones completas, contexto de levantes de 90 dias, conteos y cierres declarados. Materializa solo objetos necesarios; proyecta `anio_mes` para controles antes de cargar datos. Rechaza cierres desconocidos para operar. Un mes sin eventos conserva cero y fechas de eventos `null`; no se convierte en fuente no entregada.
- `R/acceso/impala.R`: COM y levantes de las dos tablas originales; una consulta por mes completo, seis meses maximos por fuente/pedido, incluido contexto. Conserva exclusiones COM y columnas de levantes originales. El productor aporta cierre/disponibilidad; no se infieren del ultimo evento. La conexion se cierra tambien ante error.
- `R/publicacion/versiones.R`: objetos en `versions/<id>/`, inventario con tamanos y MD5, publicado al final. Verifica lectura de objetos antes de activarlos. MD5 detecta corrupcion accidental; no sustituye controles de acceso.
- `R/acceso/lector_app.R`: resuelve `current.json` una vez, crea cache de sesion/version y verifica objetos. Precarga operacion, serie y referencia; detalle historico por fecha/familia elegidas. Las fechas disponibles se calculan con los mismos predicados de cierre COM/ZL de R08, sin inferirlas desde el ultimo dia.

La materializacion devuelve rutas crudas y marcas separadas COM/levantes; no aplica recetas ni puntua. La coordinacion con preparacion, modelos y estado corresponde a R10. Los objetos de otros componentes pueden persistirse con el mismo transporte, sin convertir la app en un pipeline.

## Activacion y recuperacion

`publicar_productos.R` crea una version nueva; solo activa con el argumento `activar`. `activar_publicacion.R` permite seleccionar una version existente o `restaurar` el puntero previo. Toda activacion valida integridad completa antes del cambio.

Local: lock de publicador por version y lock de activacion, candidato de puntero y respaldo `previous.json` antes del reemplazo. En Windows hay un intervalo entre retirar el puntero y renombrar el candidato: un lector nuevo puede fallar de forma explicita, nunca mezclar versiones; recuperar con `restaurar`. Un lock abandonado requiere comprobar que no haya proceso activo antes de retirarlo manualmente. No se implementa expiracion automatica.

S3: versiones nuevas y objeto de puntero completo, sin rename. Se exige un solo publicador por prefijo: no hay CAS ni bloqueo distribuido. Las versiones incompletas no tienen inventario ready, no se activan y se conserva el puntero anterior. Reintentar con otro identificador. Un lector existente sigue con su version aunque cambie el puntero. Actualizacion automatica de sesiones y retencion/borrado de versiones quedan fuera de R09.

## Evidencia local

- `tests/test_acceso_r09.R`: SQL sin red e inyeccion rechazada; esquema/contexto/cierre; mes cero y correccion retrospectiva; entrega local/S3 equivalente; matriz de cuatro combinaciones de entrada/destino; bytes identicos; publicacion parcial; fallo de activacion antes del puntero y durante reemplazo local; recuperacion; lector fijo; checksum/corrupcion; cache por particion; UI por cargador publico y respuesta HTTP 200.
- `tests/test_app_r08.R`: regresion aprobada del constructor, operacion y vistas COM/ZL/evolucion, UI y HTTP.
- `tests/test_base.R`: 26 comprobaciones aprobadas.
- CLI local probado: `runtime/r09_piloto_20261022_153807/almacen`, version `piloto_r09` activa. Solo contiene el piloto de R08; no reemplaza ni activa publicaciones del sistema original.

Fallos detectados durante desarrollo: rename de R denegado en TEMP de Windows sandbox (comprobado que funciona en runtime propio, donde se hacen las pruebas); comparacion de atributos de lectura Arrow y archivo mapeado reutilizado en fixture (se comprueban valores y bytes, con destinos distintos); campos null omitidos en meses cero (corregido); cargador Shiny directo sin adjuntar shiny en fixture (corregido para reproducir runApp). No son evidencia de conexion remota. Los fallos anteriores de indice Arrow y seleccion app.R/server.R de R08 conservan sus regresiones.

## Uso local

Desde reconstruccion/, un almacen versionado aislado puede abrirse asi (cerrar antes otra instancia en el mismo puerto):

```powershell
$env:APP_DATA_SOURCE = 'local'
$env:RF_APP_STORE = 'C:\DARIO\Git\modelo_com_jupiter\reconstruccion\runtime\r09_piloto_20261022_153807\almacen'
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' --vanilla scripts/run_app.R
```

`RF_APP_STORE` tiene precedencia sobre `RF_APP_PUBLICATION` en local. Si no hay almacen versionado, se conserva la publicacion directa R08. Para volver a ella: `Remove-Item Env:RF_APP_STORE -ErrorAction SilentlyContinue` y definir `RF_APP_PUBLICATION`.

Para publicar otra version local, elegir un id nuevo y una publicacion R08 ready:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' --vanilla scripts/publicar_productos.R `
  '<publicacion_ready>' '<almacen_local_aislado>' '<id_nuevo>' activar
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' --vanilla scripts/activar_publicacion.R `
  '<almacen_local_aislado>' restaurar
```

El rollback requiere una activacion previa que haya creado `previous.json`. La publicacion del historico completo vuelve a recorrer/verificar sus archivos; duracion no medida, ejecutarla el usuario si la necesita. No repetir la construccion R08 para probar transporte.

## Pendiente real: Impala y Cloudera/S3

El usuario confirmo que aun no hay ubicaciones ni acceso definidos. No se consulto Impala, descargo de S3 ni publico remotamente. No inventar bucket, prefijo ni cierre. No instalar dependencias.

Requisitos: reconstruccion y piloto propios en Cloudera; R con Arrow/dplyr/jsonlite, RJDBC/DBI/Java y driver instalados; Python CML con `cml.data_v1`; conexion administrada con permisos de listado/lectura/escritura; bucket y prefijos nuevos aislados; productor que confirme cierres. Secretos Impala en entorno administrado, nunca en archivos del repositorio ni en la salida compartida.

1. Completar `config/pedido_impala_r09.json.example` en `runtime/r09_remoto/pedido.json` con un mes objetivo y cierres/disponibilidad reales. El extractor agrega meses completos de contexto. No ejecutar los placeholders. Las consultas mensuales pueden demorar: las ejecuta el usuario, no se estima tiempo sin evidencia.
2. Configurar Impala y ejecutar en terminal Cloudera, desde la raiz reconstruccion:

```bash
export RF_EXTRACTOR=impala
export RF_ENVIRONMENT=cloudera
export IMPALA_JDBC_JAR='<jar_instalado>'
export IMPALA_JDBC_URL='<url_confirmada_sin_secretos>'
# IMPALA_USER e IMPALA_PASSWORD ya deben existir en el entorno administrado.
Rscript --vanilla scripts/extraer_fuentes.R runtime/r09_remoto/pedido.json runtime/r09_remoto/entrega
```

Destino debe ser nuevo. Resultado esperado: `R09_EXTRACT_OK`, parquet crudo por mes y `entrega/manifest.json` lista, con cierres aportados y conteos. Si falla, compartir mensaje sin credenciales; no continuar.

3. Elegir prefijos nuevos y aislados; reemplazar todos los marcadores antes de ejecutar. El verificador rechaza un almacen de publicaciones que ya tenga versiones o puntero:

```bash
export RF_EXTRACTOR=entrega
export INGESTA_INPUT_BACKEND=cloudera_s3
export PIPELINE_STORAGE_BACKEND=cloudera_s3
export APP_DATA_SOURCE=cloudera_s3
export RETICULATE_PYTHON='<ruta_python_CML_instalado>'
export PIPELINE_S3_CONNECTION='<conexion_administrada>'
export PIPELINE_S3_BUCKET='<bucket_confirmado>'
export INGESTA_S3_PREFIX='<prefijo_nuevo_aislado>/entrega'
export INGESTA_S3_MANIFEST_KEY="$INGESTA_S3_PREFIX/manifest.json"
export PIPELINE_S3_PREFIX='<prefijo_nuevo_aislado>/publicaciones'
export APP_S3_CONNECTION="$PIPELINE_S3_CONNECTION"
export APP_S3_BUCKET="$PIPELINE_S3_BUCKET"
export APP_S3_PREFIX="$PIPELINE_S3_PREFIX"
Rscript --vanilla tests/validar_s3_real_r09.R runtime/r09_remoto/entrega runtime/r08_app/publicacion_piloto remoto_r09_01
```

Resultado esperado: `R09_S3_REAL_OK`, entrega de ida/vuelta con esquema/conteos, dos versiones piloto verificadas, activacion y rollback a la primera, lector fijado y lectura historica por particion. Destinos: los prefijos aislados y caches bajo runtime. Duracion remota desconocida; ejecuta el usuario. La prueba de fallos inyectados sigue siendo local/simulada; no atribuirla a un corte real de S3.

4. Con ese mismo entorno, `Rscript --vanilla scripts/run_app.R` debe abrir la version piloto remota. Confirmar operacion e historia COM/ZL. Compartir los marcadores de exito y errores sin secretos. Revisar evidencias antes de finalizar R09. No desplegar ni cambiar consumidores vigentes.

[Ficha R09](../tareas/R09_acceso_publicacion.md) | [Estado](estado_actual.md) | [Reglas](reglas_trabajo.md)


El lanzador conserva host local como el original y reconoce CDSW_APP_PORT antes de APP_PORT. En Cloudera definir RF_OPEN_BROWSER=0 antes de lanzar; la accesibilidad por proxy/despliegue real sigue pendiente. La identidad del manifiesto copiado coincide con la version R09 y conserva source_publication_id; el original R08 no cambia.

