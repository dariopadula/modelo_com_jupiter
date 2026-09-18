# Datos Y Leakage

Ver tambien [[tareas_por_tipo]], [[arquitectura]], [[modelos_com]], [[scoring_operativo]] y [[zona_limpia]].

## Para Que Sirve Esta Nota

Usar esta nota cuando una tarea toque datos, cortes temporales, asignacion de reclamos, construccion de features, scoring o cambios que puedan introducir leakage.

## Que Leer Primero

1. `documentacion/flujo_datos.qmd`
2. `documentacion/proceso_scoring_operativo.qmd`
3. `documentacion/modelos.qmd`, si afecta modelos
4. `AGENTS.md`, seccion Datos, Modelos y App
5. `zona_limpia/README.qmd`, si afecta Zona Limpia

## Que Es Leakage En Este Proyecto

Leakage ocurre si una feature usa informacion que no estaria disponible al momento de predecir el dia objetivo.

Casos sensibles:

- usar levantes posteriores a `D 01:00` para predecir `D`;
- usar reclamos de `D` como feature;
- usar COM de `D-1` si no esta cerrado para scoring matinal;
- aprender imputacion o escalado con validacion/test;
- recalcular predicciones historicas con informacion posterior sin versionarlo.

## Reglas Temporales Vigentes

Para modelado y scoring:

- features historicas excluyen el dia objetivo;
- variables predictivas de levante usan corte `dia + 1 hora`;
- columnas predictivas llevan sufijo `_pred`;
- features derivadas de levante, como exceso sobre periodo teorico, deben calcularse solo desde columnas predictivas ya disponibles;
- scoring operativo usa COM cerrado hasta `D-2`;
- features climaticas usan solo informacion hasta el dia anterior al objetivo (`D-1`) y ventanas cerradas en `D-1`;
- reclamos observados se completan despues, no entran en la prediccion congelada.

## Fuentes Y Salidas Que No Hay Que Confundir

### `data/parquet/com/`

Base COM filtrada para el modelo principal.

### `data/parquet/com_completo/`

Base ampliada para Zona Limpia. No reemplaza la base COM del modelo.

### `data/processed/modelo_cluster_dia/base_cluster_dia/`

Base diaria por cluster con targets COM y features contemporaneas de levante.

### `data/processed/modelo_cluster_dia/features_cluster_dia/`

Tabla principal de modelado con features historicas.

### `data/processed/features_compartidas/`

Capa normalizada para la reevaluacion 2026. Contiene calendario por dia y
agregados segmento/dia con q7, q30, w7, w30, ciclo anual, densidad y NBI. No
contiene splits ni clima. Los modelos cluster/dia siguen usando
`features_cluster_dia` y unen calendario y territorio segun corresponda.

El split compartido vive separado en
`config/splits_reevaluacion_2026.csv`. La version `reevaluacion_2026_v1` usa
train `2025-04-01` a `2026-03-31`, validacion `2026-04-01` a `2026-06-30` y
test sellado `2026-07-01` a `2026-09-14`. El test no puede informar seleccion
ni metricas hasta el paso 8 de T032.

### `data/processed/app_*/predicciones_operativas_cluster_dia/`

Predicciones ya calculadas para consumo de app.

### `data/processed/zona_limpia/`

Salidas analiticas de Zona Limpia separadas del pipeline operativo principal.

### `data/processed/clima/inumet_melilla_g3/`

Variables climaticas diarias de INUMET para `Melilla G3`. La tabla
`clima_inumet_melilla_g3_features_diarias.csv` esta preparada para join por
`dia`: para predecir `D`, usa clima de `D-1` y ventanas `D-3` a `D-1`.

## Scripts Sensibles

Datos:

- `scripts/get_datos_levante.R`
- `scripts/get_datos_COM.R`
- `scripts/asignar_com_contenedores_clusters.R`
- `scripts/construir_base_cluster_dia.R`
- `scripts/construir_features_historicas_cluster_dia.R`
- `scripts/construir_features_compartidas_modelos.R`
- `scripts/validar_features_compartidas_modelos.R`
- `scripts/congelar_splits_reevaluacion_2026.R`
- `scripts/validar_splits_reevaluacion_2026.R`
- `scripts/descargar_clima_inumet_melilla_g3.R`

Modelos:

- `scripts/modelo_*cluster_dia*.R`
- `funciones/modelos_utils.R`

Scoring:

- `scripts/proceso_scoring_operativo_cluster_dia.R`
- `scripts/emular_scoring_operativo_*`
- `funciones/scoring_operativo_utils.R`

Zona Limpia:

- `zona_limpia/04_comparar_com_zona_limpia_cluster_dia.R`
- `zona_limpia/08_modelo_problema_observado_zl_xgboost.R`
- `zona_limpia/12_modelo_propension_visita_zl_y_ajuste_correspondencia.R`

## Checklist Antes De Cambiar Datos O Features

- La variable existe al momento operativo de prediccion?
- Si usa levantes, respeta `D 01:00`?
- Si deriva nuevas variables de levante, usa solo columnas `_pred` y no estados posteriores?
- Si usa COM, respeta exclusion del dia objetivo y regla D-2 si aplica?
- Si se imputa, la mediana/media se aprende solo en entrenamiento?
- Si cambia el target, queda documentado el universo?
- Si afecta Zona Limpia, se mantiene separado `com_completo` de `com`?
- Si afecta app, la app sigue sin recalcular?
- Si agrega clima u otra fuente externa, queda claro que solo usa informacion disponible antes de operar?

## Que Documentar Si Se Cambia Algo

- `documentacion/flujo_datos.qmd` si cambia preparacion/asignacion/features.
- `documentacion/proceso_scoring_operativo.qmd` si cambia corte temporal o scoring.
- `documentacion/modelos.qmd` si cambia una feature usada por modelos.
- `zona_limpia/README.qmd` si afecta Zona Limpia.
- `documentacion/HITOS.md` y `TAREAS.md` si la decision es relevante.

## Pendiente De Confirmar

- Evaluacion de regla alternativa `tuvo_levante_ultimos_7d`.
- Si COM podria cerrar a medianoche en el futuro para volver de D-2 a D-1.
