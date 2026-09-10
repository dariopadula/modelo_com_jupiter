# App Operativa

Ver tambien [[scoring_operativo]], [[datos_y_leakage]], [[componentes]] y [[estado_actual]].

## Para Que Sirve Esta Nota

Usar esta nota cuando la tarea sea cambiar la app Shiny, sus entradas, sus filtros, sus visualizaciones o la salida operativa que consume.

## Fuentes Primarias

- `app_operativa_v2/README.md`
- `documentacion/contrato_datos_app_operativa_v2.qmd`
- `documentacion/proceso_scoring_operativo.qmd`
- `app_operativa_v2/app.R`
- `app_operativa_v2/R/datos_app.R`
- `TAREAS.md`, tarea T030
- `documentacion/HITOS.md`

## Contrato Actual

La app consume datos ya calculados. No calcula features, no aplica modelos y no decide frescura de fuentes.

La salida historica multi-modelo vigente esta en:

- `app_operativa_v2/data/operacional/`

La tabla principal es:

- `predicciones_operativas_cluster_dia/`

Unidad de fila:

- `cluster_id`
- `dia_objetivo`
- `modelo_id`
- `version_modelo`

Modelos disponibles:

- `com_reclamo`: score de probabilidad de reclamo COM.
- `zl_problema`: score exploratorio de problema observado Zona Limpia.

En la vista Mapa, COM y ZL se seleccionan de forma independiente y se muestran
como capas superpuestas. COM usa puntos rellenos y ZL anillos, por lo que las
coincidencias quedan visibles sin convertir ambos targets en una categoria
unica.

La app incluye ademas un prototipo retrospectivo para T028: muestra el total
estimado de clusters con reclamo, afectacion por barrio y estrategias dinamicas
de seleccion COM. COM y ZL se configuran por separado y pueden superponerse en
el mapa. El modelo agregado no se aplica a ZL. Estas salidas aun no son un
contrato operativo diario.

La version modular en `app_operativa_v2/` es autocontenida en codigo desde el
2026-09-10: sus utilidades de carga y seleccion viven en su propia carpeta `R/`
y ya no importa funciones desde `app_operativa/`.

Tambien es autocontenida en datos de ejecucion: usa `data/operacional/`,
`data/historico/` y `data/referencia/` dentro de la carpeta de la app. Los
procesos que generan datos especificos para la interfaz publican directamente
alli. El shape de barrios se copia porque es un insumo externo no generado.

La vista Historico reutiliza las estrategias de seleccion del mapa para evaluar
su desempeno retrospectivo. Cuando se muestran observados, usa categorias
mutuamente excluyentes de seleccion, visita y resultado; no superpone capas de
score, visitas y problemas.

La comparacion de desempeno se presenta como tabla por estrategia con parametros
efectivos, cantidad seleccionada, observados capturados, precision, cobertura y
lift. En ZL, precision y lift se calculan dentro de seleccionados con visita
efectiva para no tratar ausencia de visita como ausencia de problema.

## Observados

Para `com_reclamo`, las metricas historicas usan:

- `tuvo_reclamo_observado`
- `n_reclamos_observado`

Para `zl_problema`, las metricas historicas usan:

- `problema_zl_observado`
- `n_zl_problema_comparable`

En ZL, los cluster-dias sin visita efectiva no son negativos observados: quedan sin observacion del problema ZL.

## Script De Construccion

La salida historica se reconstruye con:

```powershell
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/construir_app_modelos_largo_historico.R
```

El script integra:

- modelo COM logistico reducido `d2`;
- modelo ZL XGBoost `operativo_segmento`, escenario `random_dia_estratificado_mes`;
- observados COM desde `features_cluster_dia`;
- observados ZL desde `comparacion_com_zona_limpia_cluster_dia`.

## Validacion

Prueba principal:

```powershell
Set-Location app_operativa/tests
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" test_app.R
```

Ultimo resultado documentado: `SESSION_OK`.

## Riesgos

- Mezclar filas de distintos `modelo_id` al calcular mapas o metricas.
- Comparar score ZL contra observado COM o score COM contra observado ZL sin explicitarlo.
- Interpretar ausencia de visita ZL como ausencia de problema.
- Mover calculo de features o modelos dentro de la app.

## Refactor Planificado

El 2026-08-31 se decidio detener los parches incrementales de interfaz y abrir
T030 para refactorizar la app a partir de una definicion funcional validada.
La app vigente se conserva como referencia y no debe reemplazarse hasta comparar
ambas versiones.

La estructura inicial propuesta separa:

- `Operacion del dia`: ultimo dia con predicciones, sin observados pendientes;
- `Historico`: fechas cerradas, estimados frente a observados y serie temporal;
- `Diagnostico`: scores, estrategias, frescura y controles tecnicos.

Antes de implementar se deben acordar preguntas, indicadores, controles,
visualizaciones, contrato de datos y wireframes. Para cambios Shiny se debe leer
`skills/shiny_skill.md`. La ficha fuente para retomar es
`tareas/T030_refactorizar_app_operativa_shiny.md`.

El 2026-09-01 se implementa una primera version aislada en
`app_operativa_v2/`. Solo cubre `Operacion del dia`: resumen plegable, mapa
principal, selecciones COM/ZL separadas, capas independientes superpuestas y
lista en otra subpestana. La carga materializa solo la fecha maxima mediante
Arrow. La app anterior permanece sin cambios como referencia.

La seleccion COM y ZL admite tambien un umbral de score. La subpestana `Scores
y umbrales` muestra, para un modelo por vez, la distribucion de scores y la
curva decreciente de clusters seleccionados al aumentar el umbral. El valor se
comparte con el mapa y la lista; no se superponen scores COM y ZL porque miden
objetivos distintos.

Para `Historico` se publica una capa separada en
`app_operativa_v2/data/historico/`: una serie COM pequena para
Montevideo y barrios, y un detalle por cluster particionado primero por fecha y
luego por modelo. La app debe filtrar antes de `collect()` y unir el dia elegido
al maestro territorial. El contrato fuente es
`documentacion/contrato_datos_app_operativa_v2.qmd`.

La definicion preliminar de `Historico` separa dos preguntas: evolucion temporal
de clusters con reclamo estimados frente a observados, y evaluacion territorial
de las selecciones para un dia cerrado. La primera tendra filtro de periodo y
una lectura barrial aun por disenar. La segunda reutilizara los metodos de
seleccion operativos. Evolucion temporal muestra Montevideo para validacion y
test, con periodo, metricas y puntos que identifican los lunes. Evaluacion del
dia COM compara distribuciones seleccionadas y observadas en dos mapas de
hexagonos con escala comun, capas opcionales de puntos y una tabla de ocho
estrategias. Evaluacion del dia ZL combina en un mapa seleccion, visita y
problema, incluyendo visitas no seleccionadas, y compara cinco estrategias.
Pendientes: validacion visual y de sincronizacion, metricas territoriales
adicionales y lectura barrial de la serie. Retomar desde T030.
