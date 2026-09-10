# Componentes

Ver tambien [[arquitectura]], [[mapa_documental]], [[tareas_por_tipo]], [[datos_y_leakage]], [[decisiones]] y [[glosario]].

## Pipeline Principal De Datos

### Ingesta de levantes

- Scripts: `scripts/get_datos_levante.R`.
- Funciones: `funciones/cargar_datos_levante.R`, `funciones/preparar_datos_levante.R`, `funciones/definir_intervalos_actividad_contenedor.R`.
- Responsabilidad: generar `data/parquet/levante/` con historia diaria por contenedor, actividad observada/inferida y variables predictivas `_pred`.
- Dependencias principales: `arrow`, `data.table`.
- Documentacion relacionada: `README.qmd`, `documentacion/flujo_datos.qmd`.

### Ingesta de COM

- Scripts: `scripts/get_datos_COM.R`.
- Funciones: `funciones/cargar_datos_com.R`, `funciones/preparar_datos_com.R`.
- Responsabilidad: generar `data/parquet/com/` con reclamos objetivo preparados, sin repetidos y en CRS comun.
- Documentacion relacionada: `documentacion/flujo_datos.qmd`.

### Clusters

- Scripts: `scripts/gen_cluster_referencia_unicos.R`, `scripts/asignar_clusters_posiciones_nuevas.R`.
- Funciones: `funciones/entrenar_clusters_referencia.R`, `funciones/asignar_posiciones_levante_a_clusters.R`, `funciones/asignar_puntos_a_clusters_referencia.R`.
- Responsabilidad: crear referencia espacial estable y asignar posiciones actuales contra esa referencia.
- Dependencias principales: `dbscan` inferido por documentacion, `FNN`, `arrow`, `data.table`.
- Documentacion relacionada: `README.qmd`, `documentacion/flujo_datos.qmd`.

### Territorio por cluster

- Scripts: `scripts/construir_cluster_territorial_segmento_censal.R`, `scripts/construir_cluster_territorial_admin.R`.
- Responsabilidad: asignar atributos censales, municipio, CCZ y barrio a cada cluster por version.
- Dependencias principales: `sf`, `arrow`, `data.table`, shapes en `shp/`.
- Documentacion relacionada: `documentacion/flujo_datos.qmd`, `documentacion/HITOS.md`.

### Asignacion COM a contenedores y clusters

- Scripts: `scripts/asignar_com_contenedores_clusters.R`.
- Funciones: `funciones/asignar_com_a_contenedores_activos.R`.
- Responsabilidad: asignar reclamos al contenedor activo/elegible mas cercano del dia y luego al cluster.
- Reglas: `asignado` hasta 50 m, `revision` de 50 a 100 m, `pendiente` por encima de 100 m.
- Documentacion relacionada: `documentacion/flujo_datos.qmd`.

### Base cluster-dia y features historicas

- Scripts: `scripts/construir_base_cluster_dia.R`, `scripts/construir_features_historicas_cluster_dia.R`.
- Funciones: `funciones/construir_base_cluster_dia.R`, `funciones/construir_features_historicas_cluster_dia.R`.
- Responsabilidad: generar `base_cluster_dia` y `features_cluster_dia`.
- Dependencias principales: `arrow`, `data.table`, `zoo`.
- Documentacion relacionada: `README.qmd`, `documentacion/flujo_datos.qmd`.

### Clima INUMET

- Scripts: `scripts/descargar_clima_inumet_melilla_g3.R`, `scripts/consolidar_experimentos_clima_modelos.R`.
- Responsabilidad: preparar variables climaticas diarias de `Melilla G3` y consolidar experimentos de clima en modelos COM y ZL.
- Entradas: `data/raw/inumet/datos_abiertos/*.csv`.
- Salidas: `data/processed/clima/inumet_melilla_g3/`, `outputs/experimentos_clima/` y `zona_limpia/outputs/experimentos_clima/`.
- Documentacion relacionada: [[datos_y_leakage]], [[modelos_com]], [[modelo_zona_limpia]], `documentacion/HITOS.md`.

## Modelado COM

### Utilidades de modelos

- Archivo: `funciones/modelos_utils.R`.
- Responsabilidad: preparacion de matriz, AUC, logloss, lift, calibracion y graficos de capture rate.
- Documentacion relacionada: `documentacion/modelos_utils.qmd`.

### Modelos principales

- Scripts:
  - `scripts/modelo_logistico_cluster_dia.R`;
  - `scripts/modelo_logistico_cluster_dia_reducido.R`;
  - `scripts/modelo_random_forest_cluster_dia.R`;
  - `scripts/modelo_xgboost_cluster_dia.R`;
  - `scripts/validacion_temporal_logistico_cluster_dia_reducido.R`.
- Responsabilidad: entrenar y evaluar modelos sobre `features_cluster_dia`.
- Documentacion relacionada: `documentacion/modelos.qmd`, `documentacion/diagnostico_variables_modelo.qmd`.

### Diagnostico de variables

- Script: `scripts/diagnostico_variables_modelo_cluster_dia.R`.
- Responsabilidad: detectar colinealidad, VIF y relaciones marginales con target.
- Documentacion relacionada: `documentacion/diagnostico_variables_modelo.qmd`.

## Scoring Operativo

- Scripts:
  - `scripts/construir_estado_historico_cluster.R`;
  - `scripts/emular_scoring_operativo_cluster_dia.R`;
  - `scripts/emular_scoring_operativo_ventana_cluster_dia.R`;
  - `scripts/emular_scoring_operativo_bloque_cluster_dia.R`;
  - `scripts/validar_estado_historico_incremental.R`;
  - `scripts/proceso_scoring_operativo_cluster_dia.R`;
  - `scripts/validar_proceso_scoring_operativo.R`.
- Funciones: `funciones/scoring_operativo_utils.R`, `funciones/modelos_utils.R`, funciones de base y features.
- Responsabilidad: construir predicciones acumuladas, controles, metricas y estado historico.
- Documentacion relacionada: `documentacion/proceso_scoring_operativo.qmd`.

## App Operativa

- Archivos: `app_operativa/app.R`, `app_operativa/R/datos_app.R`, `app_operativa/run_app.R`.
- Responsabilidad: leer salidas publicadas y visualizar predicciones, mapas, historico y estado de datos.
- Dependencias principales: `shiny`, `bslib`, `leaflet`, `DT`, `plotly`, `sf`, `arrow`, `data.table`.
- Documentacion relacionada: [[app_operativa]], `app_operativa/README.md`, `documentacion/proceso_scoring_operativo.qmd`.

## Zona Limpia

- Scripts:
  - `zona_limpia/01_generar_com_completo.R`;
  - `zona_limpia/02_diagnostico_etiquetas_zona_limpia.R`;
  - `zona_limpia/03_analisis_descriptivo_zona_limpia.R`;
  - `zona_limpia/04_comparar_com_zona_limpia_cluster_dia.R`;
  - `zona_limpia/05_evaluar_scores_com_vs_zona_limpia.R`;
  - `zona_limpia/06_comparar_seleccion_zl_vs_modelo_diario.R`;
  - `zona_limpia/08_modelo_problema_observado_zl_xgboost.R`;
  - `zona_limpia/09_diagnostico_criterio_levante_zl.R`;
  - `zona_limpia/11_diagnostico_correspondencia_com_zl_territorio.R`;
  - `zona_limpia/12_modelo_propension_visita_zl_y_ajuste_correspondencia.R`.
- Reportes:
  - `zona_limpia/reportes/07_visualizar_seleccion_zl_vs_modelo.qmd`;
  - `zona_limpia/reportes/10_sesgos_seleccion_zona_limpia.qmd`;
  - `zona_limpia/reportes/13_modelo_problema_observado_zl.qmd`.
- Funciones: `zona_limpia/funciones_zona_limpia.R`.
- Responsabilidad: analizar registros Zona Limpia sin alterar el pipeline COM.
- Documentacion relacionada: `zona_limpia/README.qmd`.

## Pendiente De Confirmar

- Dependencias completas de paquetes R por script no estan centralizadas en un lockfile o manifiesto detectado.
- No se infiere un sistema formal de tests para todo el pipeline; solo se observo prueba de app en `app_operativa/tests/test_app.R`.
