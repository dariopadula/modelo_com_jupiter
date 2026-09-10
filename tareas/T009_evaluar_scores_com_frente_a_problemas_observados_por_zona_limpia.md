# T009 - Evaluar scores COM frente a problemas observados por Zona Limpia

Estado: finalizada

Prioridad: alta

Area: zona limpia / modelos / evaluacion

Fecha de creacion: 2026-07-01 Fecha de cierre: 2026-07-01

### Contexto

Antes de entrenar un modelo especifico con target Zona Limpia,
interesa evaluar si los scores COM ya disponibles capturan parte de los
problemas reales observados por Zona Limpia pero no reclamados en COM.
En particular, se quiere saber si los casos
`solo_zona_limpia_problema` caen en percentiles altos del
score, por ejemplo top 10% diario.

Esta comparacion no cambia el target original del modelo COM: el
modelo fue entrenado para predecir reclamos COM. La pregunta es si, aun
con ese target sesgado por propension a reclamar, el score aprende
senales generales de riesgo que tambien aparecen en observaciones de
campo de Zona Limpia.

### Plan propuesto

- Cruzar predicciones existentes por `cluster_id`/`dia` con la comparacion COM vs Zona Limpia.

- Calcular ranking y percentil diario del score por modelo.

- Medir, para casos de Zona Limpia en universo comparable: proporcion en top 1%, 5%, 10% y 20%;

- score medio y mediano por estado de comparacion;

- deciles de score para problemas Zona Limpia sin COM.

- Separar especialmente `solo_zona_limpia_problema`.

- Comparar contra casos limpios y contra casos donde ambas fuentes reportan problema.

### Criterio de finalizacion

Existe una salida reproducible que indique cuanto de los problemas
observados por Zona Limpia, especialmente los no reclamados por COM,
queda priorizado por los scores COM existentes.

### Notas

La interpretacion debe limitarse al periodo con predicciones
disponibles. Si se usan predicciones offline de validacion/test, la
lectura es diagnostica y no necesariamente equivalente al scoring
operativo congelado de la app.

Se creo
`zona_limpia/05_evaluar_scores_com_vs_zona_limpia.R`. Las
salidas principales son:

- `data/processed/zona_limpia/scores_com_vs_zona_limpia_cluster_dia/`

- `zona_limpia/outputs/scores_com_vs_zona_limpia_resumen_modelo_periodo.csv`

- `zona_limpia/outputs/scores_com_vs_zona_limpia_resumen_estado.csv`

- `zona_limpia/outputs/scores_com_vs_zona_limpia_resumen_solo_zl_problema.csv`

- `zona_limpia/outputs/scores_com_vs_zona_limpia_captura_top_por_estado.csv`

- `zona_limpia/outputs/scores_com_vs_zona_limpia_decil_solo_zl_problema.csv`

Lectura inicial, excluyendo enero y febrero de 2026 por problema de
registro Zona Limpia: los scores COM priorizan fuertemente los casos
donde hay reclamo COM, incluyendo `ambos_reportan_problema`,
pero no concentran especialmente los problemas detectados solo por Zona
Limpia. En test, `solo_zona_limpia_problema` queda en top 10%
diario entre 9,0% y 9,3% segun modelo; en validacion, entre 6,2% y 6,8%.
Esto sugiere que el score COM no alcanza para recuperar sistematicamente
problemas observados en campo sin reclamo.

