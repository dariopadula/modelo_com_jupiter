# App operativa v2

Primera version del refactor planificado en T030. Su codigo de ejecucion es
autocontenido y no depende de `app_operativa/`.

Esta version implementa `Operacion del dia`:

- abre en el ultimo dia con predicciones;
- mantiene COM y Zona Limpia como selecciones y capas independientes;
- permite seleccionar clusters por umbral de score;
- presenta un resumen cerrado por defecto;
- prioriza un mapa Leaflet de gran tamano;
- separa la lista de clusters en una subpestana;
- incorpora una subpestana de scores y umbrales con histograma y curva de
  cantidad seleccionada;
- no muestra observados del dia operativo.

El umbral configurado en los controles laterales es compartido por el mapa, la
lista y los graficos. En `Scores y umbrales` se analiza COM o Zona Limpia por
separado, porque sus scores corresponden a objetivos distintos.

## Datos de ejecucion

Por defecto, la app usa rutas relativas dentro de `app_operativa_v2/data/`:

- `operacional/`: predicciones y controles publicados por
  `scripts/construir_app_modelos_largo_historico.R`;
- `historico/`: serie agregada y detalle por cluster publicados por
  `scripts/construir_tablas_historicas_app_v2.R`;
- `referencia/maestro_clusters/`: maestro territorial compacto publicado por
  `scripts/construir_maestro_clusters_app_v2.R`;
- `referencia/barrios_mvd_23_pg.gpkg`: shape de barrios copiado como insumo de
  referencia porque no se genera dentro del proyecto.

Los scripts que generan datos especificos para la app escriben directamente en
estas rutas. Las carpetas anteriores bajo `data/processed/` ya no se conservan,
por lo que no existe una segunda copia de esas publicaciones.

La capa usada por `Historico` se publica en `data/historico/`:

- `serie_historica_com/`: serie liviana para Montevideo y barrios;
- `detalle_cluster_dia/`: detalle minimo particionado por fecha y modelo.

El contrato completo esta en
`documentacion/contrato_datos_app_operativa_v2.qmd`. Estas tablas aun no estan
conectadas al detalle cartografico. La serie agregada ya alimenta
`Historico > Evolucion temporal`: Montevideo, validacion y test, selector de
periodo y comparacion de correlacion, R2 predictivo, RMSE y MAE contra toda la
evaluacion. El entrenamiento no se muestra. `APP_HISTORICO_PATH` permite
configurar la ruta base de estas tablas.

`APP_DATA_PATH`, `APP_HISTORICO_PATH`, `APP_CLUSTER_PATH` y `APP_BARRIOS_PATH`
permiten reemplazar las rutas por defecto. En Cloudera se puede conservar esa
copia dentro del proyecto o usar la misma estructura desde el Object Store.

### Fuente local o Cloudera S3

La fuente predeterminada continúa siendo el sistema de archivos local:

```text
APP_DATA_SOURCE=local
```

Para consumir la misma estructura desde la conexión administrada de Cloudera:

```text
APP_DATA_SOURCE=cloudera_s3
APP_S3_CONNECTION=S3 Object Store
APP_S3_BUCKET=bucket
APP_S3_PREFIX=dario/modelo_com_app/data
```

El modo S3 usa `reticulate` para reutilizar desde R el cliente autenticado de
`cml.data_v1`. Las dependencias Python `boto3` y `raz-client` se declaran
mediante `reticulate::py_require()` para que el entorno administrado por `uv`
las resuelva sin depender de `pip`. Los objetos se descargan en una caché temporal y los lectores
Arrow y `sf` conservan el mismo contrato que en modo local. La ubicación de la
caché puede fijarse con `APP_S3_CACHE_PATH`; `APP_S3_REFRESH=1` fuerza una nueva
descarga al reiniciar la app.

La serie COM, el maestro territorial y el GeoPackage se materializan como
insumos pequeños. Las predicciones operativas se limitan al mes que contiene el
último día informado por `control_scoring`. Para el histórico, la app lista las
particiones disponibles y descarga únicamente la combinación
`dia_objetivo/modelo_id` elegida por el usuario.

La estructura esperada bajo el prefijo es:

```text
dario/modelo_com_app/data/
  operacional/
  historico/
  referencia/
```

La serie temporal marca con puntos solamente los lunes, sobre las lineas de
observados y estimados, para identificar visualmente el comienzo de cada semana.

La guia Shiny se aplica mediante un modulo independiente con UI y servidor
separados. Prueba especifica: `tests/test_evolucion.R` (desde `tests/`).

En modo local, Arrow detecta la fecha máxima y materializa solamente las
predicciones de ese día. En modo S3, `control_scoring` identifica el mes que se
debe descargar y Arrow aplica luego el mismo filtro diario. Esto evita cargar
el histórico completo en memoria para una pantalla exclusivamente operativa.

Ejecucion desde la raiz del proyecto:

```powershell
$env:APP_PORT = "3839"
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" app_operativa_v2/run_app.R
```

Prueba de sesion:

```powershell
Set-Location app_operativa_v2/tests
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" test_app.R
```

Prueba de datos historicos, desde `app_operativa_v2/tests`:

```powershell
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" test_datos_historicos.R
```

Prueba de selección del backend, sin conectarse a S3:

```powershell
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" test_fuente_datos.R
```
## Evaluacion del dia COM

Historico incluye dos mapas sincronizados de distribucion por hexagonos.
Cada celda muestra porcentaje del total seleccionado o del total observado,
con grilla y escala de color comunes. No mide coincidencia punto a punto.
Reutiliza los ocho criterios COM de Operacion, carga solo el dia consultado y
exige observados cerrados, version territorial compatible y coordenadas completas.
Ofrece hexagonos de 500, 1000 y 2000 metros; la grilla se ancla al maestro
territorial para no cambiar con el criterio o la fecha. La seleccion de fechas
se limita a dias cerrados con pronostico agregado disponible.
Prueba: `tests/test_dia_com.R`, desde `tests/`.

### Puntos y metricas (2026-09-08)

Cada mapa de Evaluacion del dia COM permite mostrar su capa de puntos mediante
un control independiente. La tabla inferior compara los ocho criterios con los
parametros actuales de los controles COM e identifica el criterio activo.
Incluye seleccionados, evaluables, observados capturados, precision, cobertura
y lift. Precision usa seleccionados como denominador; cobertura usa todos los
observados del dia; lift divide precision por prevalencia del universo diario.
Los denominadores nulos producen valores no calculables. Estas metricas evalúan
coincidencias por cluster y complementan la distribucion territorial por hexagonos.

El encabezado resume, para la fecha elegida, las cantidades de clusters
evaluados, seleccionados, observados y estimados. El total estimado corresponde
al pronostico agregado de Montevideo y se muestra redondeado.

## Evaluacion del dia ZL

La vista historica ZL presenta un unico mapa con los puntos seleccionados por el
modelo. Superpone un aro gris oscuro, grande y discontinuo para la seleccion;
un aro verde interior, continuo y con relleno tenue cuando hubo visita efectiva;
y un punto naranja cuando se observo un problema.
Asi distingue seleccionado sin visita, seleccionado y visitado sin problema, y
seleccionado, visitado y con problema.

Las visitas no seleccionadas tambien se muestran: aro azul sin aro gris cuando
no hubo problema, y aro azul con punto naranja cuando se observo un problema.
De esta forma el mapa incluye todas las visitas reales del dia y conserva la
seleccion del modelo como una capa independiente.

La leyenda del mapa usa simbolos dibujados dentro del propio control
para mostrar las referencias sin depender de estilos externos.

La tabla inferior compara los cinco criterios ZL. Precision y lift usan como
denominador solo los seleccionados con visita efectiva; cobertura usa todos los
problemas observados del dia. Los clusters sin visita nunca se consideran casos
sin problema. Prueba: `tests/test_dia_zl.R`, desde `tests/`.

El selector diario de COM y el de ZL excluyen los dos ultimos dias publicados,
marcados como pendientes de validacion por el rezago operativo `D-2`.

El resumen diario muestra tambien el porcentaje de visitas efectivas que
registraron problema. Esta prevalencia observada sirve como referencia para la
precision y el lift de las estrategias de seleccion.
