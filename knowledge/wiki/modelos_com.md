# Modelos COM

Ver tambien [[tareas_por_tipo]], [[datos_y_leakage]], [[componentes]], [[decisiones]] y [[glosario]].

## Para Que Sirve Esta Nota

Usar esta nota cuando la tarea implique entrenar, comparar, interpretar o modificar modelos que predicen reclamos COM.

## Que Leer Primero

1. `documentacion/modelos.qmd`
2. `documentacion/modelos_utils.qmd`
3. `documentacion/diagnostico_variables_modelo.qmd`
4. `documentacion/flujo_datos.qmd`
5. `documentacion/HITOS.md`, secciones de modelos
6. Si el modelo se usara operativamente: `documentacion/proceso_scoring_operativo.qmd`
7. Si se evalua desempeno por CCZ: `documentacion/analisis_territorial_pred.qmd`

## Target Y Unidad

Unidad:

- `cluster_id`/`dia`

Target principal:

- `tuvo_reclamo`

Interpretacion:

- `TRUE`: el cluster tuvo al menos un reclamo COM asignado o en revision ese dia.
- `FALSE`: no tuvo reclamos validos ese dia.

## Tabla Principal

- `data/processed/modelo_cluster_dia/features_cluster_dia/`

Incluye:

- target `tuvo_reclamo`;
- conteo `n_reclamos`;
- features de levantes;
- features historicas de reclamos;
- ratios y periodicidad teorica.

## Modelos Existentes

### Logistico completo

- Script: `scripts/modelo_logistico_cluster_dia.R`
- Salida: `data/processed/modelos/logistico_cluster_dia/`
- Uso: baseline interpretable amplio.

### Logistico reducido

- Script: `scripts/modelo_logistico_cluster_dia_reducido.R`
- Salida: `data/processed/modelos/logistico_cluster_dia_reducido/`
- Uso: referencia interpretable con menor colinealidad.

### Logistico reducido D-2

- Variante del reducido con reclamos historicos hasta `D-2`.
- Uso: scoring matinal robusto.
- Salida documentada: `data/processed/modelos/logistico_cluster_dia_reducido_reclamos_d2/`

### Random Forest

- Script: `scripts/modelo_random_forest_cluster_dia.R`
- Usa las mismas variables del logistico reducido para comparar algoritmo.

### XGBoost

- Script: `scripts/modelo_xgboost_cluster_dia.R`
- Baseline sin tuning fino, con variables comparables al reducido.
- Soporta experimento opcional con clima (`USAR_CLIMA=1`) usando features INUMET disponibles hasta `D-1`.
- Soporta experimento opcional con exceso sobre periodo teorico (`USAR_EXCESO_LEVANTE=1`).

## Experimento Clima INUMET

Se evaluo agregar variables climaticas de `Melilla G3` al XGBoost COM.

Lectura actual:

- validacion: el AUC no mejora frente al baseline;
- test: cambio practicamente nulo;
- no queda promovido como baseline operativo.

Salidas:

- `outputs/experimentos_clima/comparacion_metricas_com_xgboost_clima*.csv`
- `outputs/experimentos_clima/features_importancia_com_y_zl.csv`
- `outputs/experimentos_clima/features_clima_importancia_com_y_zl.csv`

Fuente metodologica breve: `documentacion/HITOS.md` y `TAREAS.md`, tarea T019.

## Experimento Exceso Sobre Periodo Teorico

Se evaluo agregar:

- `exceso_mean_tiempo_periodo_pred_pos`;
- `exceso_mean_tiempo_periodo_pred_trunc_7`.

Lectura actual:

- las variables tienen importancia en XGBoost;
- la mejora en validacion es marginal;
- test baja levemente en XGBoost y logistico reducido;
- no queda promovido como baseline operativo.

Salidas:

- `outputs/experimentos_exceso_levante/comparacion_metricas_com_exceso_levante_delta.csv`
- `outputs/experimentos_exceso_levante/comparacion_lift_com_exceso_levante_delta.csv`
- `outputs/experimentos_exceso_levante/importancia_exceso_levante_xgboost_com.csv`

Fuente metodologica breve: `documentacion/HITOS.md` y `TAREAS.md`, tarea T020.

## Pronóstico Agregado Diario COM

T028 estudia la cantidad diaria de clusters con al menos un reclamo mediante
modelos con unidades barrio/dia, CCZ/dia y segmento/dia. La referencia
predictiva combina A0, con jerarquia barrio/segmento, y una correccion XGBoost
compacta. T029 fija ademas una referencia inferencial segmento/dia con
`mgcv::bam()`: calendario, densidad, NBI, atraso, propension historica, cambio
reciente y efectos penalizados de barrio y segmento. Su bootstrap conjunto de
50 replicas remuestrea semanas y segmentos completos. Densidad y NBI conservan
el signo, mientras que la interaccion atraso por cambio reciente incluye cero.
Estos resultados son asociaciones dentro de los barrios observados.

Para consultar rapidamente cada familia, su unidad y el hallazgo principal,
ver [[modelos_agregados_com]].

Fuentes:

- `tareas/T028_pronosticar_y_explicar_volumen_diario_reclamos_com.md`;
- `documentacion/pronostico_diario_clusters_reclamo_com.qmd`;
- `tareas/T029_explicar_dias_alta_afectacion_territorial_com.md`;
- `documentacion/informe_diagnostico_temporal_modelo_inferencial_com.qmd`;
- `scripts/benchmark_modelo_segmento_barrio_com.R`;
- `scripts/experimentar_*_com.R`.

## Features Clave Del Logistico Reducido

Familias seleccionadas:

- historia inmediata: `n_reclamos_lag1`;
- historia acumulada: `n_reclamos_sum_7d`, `n_reclamos_sum_30d`;
- historia observada por tramos;
- recencia: `dias_desde_ultimo_reclamo_o_inicio_trunc_90`;
- existencia: `dias_cluster_existente_30d`;
- composicion: `n_contenedores_activos`, `pct_contenedores_inferidos`;
- levante: `mean_tiempo_desde_ultimo_levante_pred`;
- periodicidad: `mean_levante_periodo`;
- exceso sobre periodo teorico: evaluado como experimento, no incluido en baseline;
- inferencia: `mean_dias_total_tramo_inferido_estado`.

## Evaluacion

Metricas principales:

- AUC;
- logloss;
- precision en top N%;
- capture rate;
- lift;
- calibracion por deciles;
- estabilidad diaria.

Utilidades:

- `auc_binaria()`;
- `logloss_binaria()`;
- `lift_top()`;
- `lift_diario_top()`;
- `calibracion_deciles()`;
- `preparar_matriz()`.

## Diagnostico Territorial Por CCZ

Fuente primaria:

- `documentacion/analisis_territorial_pred.qmd`.

Implementacion y salidas:

- `scripts/diagnostico_territorial_modelo_com_ccz.R`;
- `outputs/diagnostico_territorial_modelo_com_ccz/`.

El diagnostico aplica el mismo modelo logistico reducido COM `D-2` a toda la
ciudad y luego calcula metricas por CCZ. No entrena modelos territoriales ni usa
CCZ como predictor.

Resultados de referencia:

- cobertura completa en 18 CCZ;
- AUC global `0,753` en validacion y test;
- AUC por CCZ entre `0,691` y `0,771` en validacion;
- AUC por CCZ entre `0,691` y `0,760` en test;
- diferencias territoriales de calibracion;
- intervalos mediante 1.000 remuestreos de metricas diarias por CCZ.

El reporte separa dos politicas operativas:

- ranking global diario de ciudad, donde los CCZ compiten por lugares en el top;
- ranking local diario, que selecciona el mismo porcentaje dentro de cada CCZ.

Conceptos para interpretar sus tablas:

- `positivos` cuenta cluster-dias con al menos un reclamo, no reclamos
  individuales;
- `prevalencia` es positivos dividido por cluster-dias evaluados;
- `captura` es la proporcion de cluster-dias positivos del CCZ seleccionada;
- `lift` es precision dividida por prevalencia del CCZ;
- `representacion relativa` es el peso del CCZ dentro del top dividido por su
  peso en el universo de cluster-dias.

La lectura se limita al target de reclamos COM. Diferencias entre CCZ pueden
combinar problemas, exposicion, propension a reclamar, registro y desempeno del
modelo; no demuestran por si solas diferencias en problemas fisicos o equidad
territorial.

## Reglas De No Leakage

- Usar variables `_pred` para levante.
- Excluir el dia objetivo de features historicas.
- Aprender imputacion/estandarizacion solo en entrenamiento.
- Para scoring matinal, respetar COM cerrado hasta `D-2`.

Detalles en [[datos_y_leakage]].

## Que Documentar Si Se Cambia Algo

- `documentacion/modelos.qmd`: especificacion, resultados, interpretacion.
- `documentacion/diagnostico_variables_modelo.qmd`: si cambian features o criterio de reduccion.
- `documentacion/modelos_utils.qmd`: si cambian metricas/preparacion compartida.
- `documentacion/proceso_scoring_operativo.qmd`: si el modelo entra al scoring.
- `documentacion/analisis_territorial_pred.qmd`: si cambia la evaluacion por CCZ.
- `TAREAS.md` y `documentacion/HITOS.md`: si hay cambio relevante.

## Riesgos

- Comparar modelos con features o splits distintos sin explicitarlo.
- Introducir indicadores `_na` que codifiquen bordes temporales.
- Usar variables no disponibles al momento operativo.
- Confundir buen desempeno para COM con buen desempeno para problemas observados en campo.

## Pendiente De Confirmar

Para T032, `com_xgboost_d2` supera al logistico reducido en la validacion
`reevaluacion_2026_v1`: AUC `0,7752` contra `0,7667`, con menor logloss y Brier.
La ventaja aparece en abril, mayo y junio y tambien en el ranking diario. El
logistico se conserva como referencia parsimoniosa para congelar finalistas en
el paso 7. El test no fue leido.

- Si conviene tuning acotado de Random Forest o XGBoost.
- Evaluacion futura de modelos de conteo para `n_reclamos`.
- Regla alternativa de actividad reciente por levantes.
- Si conviene reevaluar clima en el modelo inferencial agregado una vez que
  temperatura y precipitacion cubran todo el nuevo periodo. La exploracion
  actual con `D-1` no produjo una mejora estable y no justifica por si sola
  incorporarlo.
- Si el exceso sobre periodo teorico debe revaluarse con interacciones o sin las variables base de tiempo/periodo.
- Si la heterogeneidad barrio/levante persiste al usar scores COM realmente OOF.
