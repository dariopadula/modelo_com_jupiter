# T012 - Primer modelo de problema observado Zona Limpia

Estado: finalizada

Prioridad: alta

Area: zona limpia / modelos / territorio

Fecha de creacion: 2026-07-03 Fecha de cierre: 2026-07-03

### Contexto

La comparacion entre seleccion Zona Limpia y modelo COM mostro que el
modelo COM sirve para priorizar reclamos, pero no necesariamente
problemas observados en campo. Se necesita un primer modelo cuyo
objetivo sea aproximar la probabilidad de encontrar un problema
observable si se visita un cluster.

### Plan propuesto

- Agregar municipio, CCZ y barrio a los clusters usando las capas nuevas en `shp/`.

- Construir un dataset observado usando solo visitas efectivas de Zona Limpia.

- Usar como target `hay_com OR hay_zl_problema_comparable`.

- Excluir `Voluminosos` y los meses con cobertura anomala.

- No usar features COM historicas ni contemporaneas como predictores.

- Entrenar un baseline XGBoost sin tuning fino con features de levante, territorio y calendario.

- Evaluar con split temporal y split random estratificado por mes/target.

### Criterio de finalizacion

Existe un baseline reproducible con metricas, lift, calibracion,
importancia de variables y predicciones observadas para evaluar si hay
senal aprendible en los datos observados por Zona Limpia.

### Notas

Se crearon:

- `scripts/construir_cluster_territorial_admin.R`

- `zona_limpia/08_modelo_problema_observado_zl_xgboost.R`

Salidas principales:

- `data/processed/cluster_territorial/cluster_admin_territorial/`

- `data/processed/modelos/zona_limpia_problema_observado_xgboost/`

- `zona_limpia/outputs/modelo_zl_observado_metricas.csv`

- `zona_limpia/outputs/modelo_zl_observado_lift.csv`

- `zona_limpia/outputs/modelo_zl_observado_importancia.csv`

Lectura inicial: el split random muestra AUC cercano a
`0,67`, mientras que el split temporal cae a cerca de
`0,60` en validacion/test. Esto sugiere que hay senal
aprendible, pero tambien posible cambio temporal de criterio, cobertura
o regimen de seleccion/observacion.

