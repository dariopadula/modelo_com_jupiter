# Zona Limpia

Ver tambien [[modelo_zona_limpia]], [[tareas_por_tipo]], [[datos_y_leakage]], [[modelos_com]], [[decisiones]] y [[glosario]].

## Para Que Sirve Esta Nota

Usar esta nota cuando la tarea involucre registros Zona Limpia, problemas observados en campo, comparacion con COM, sesgos de seleccion o modelos de problema observado.

## Que Leer Primero

1. `zona_limpia/README.qmd`
2. `zona_limpia/reportes/10_sesgos_seleccion_zona_limpia.qmd`
3. `documentacion/HITOS.md`, seccion Zona Limpia
4. `TAREAS.md`, tareas T004 a T019
5. Si hay comparacion con modelo COM: `zona_limpia/reportes/07_visualizar_seleccion_zl_vs_modelo.qmd`
6. Si hay modelado ZL: [[modelo_zona_limpia]] y `zona_limpia/reportes/13_modelo_problema_observado_zl.qmd`
7. Si hay modelos COM o lectura general: `documentacion/modelos.qmd`

## Contrato Conceptual

Zona Limpia se analiza como un frente separado del pipeline principal COM. Su objetivo es auditar seleccion y problemas observados en campo sin alterar:

- `data/parquet/com/`;
- modelos COM existentes;
- app operativa.

La base ampliada para analisis es:

- `data/parquet/com_completo/`

Esta base incluye incidentes usados por el modelo y registros cuyo incidente comienza con `Zona limpia`.

## Scripts En Orden Aproximado

1. `zona_limpia/01_generar_com_completo.R`
2. `zona_limpia/02_diagnostico_etiquetas_zona_limpia.R`
3. `zona_limpia/03_analisis_descriptivo_zona_limpia.R`
4. `zona_limpia/04_comparar_com_zona_limpia_cluster_dia.R`
5. `zona_limpia/05_evaluar_scores_com_vs_zona_limpia.R`
6. `zona_limpia/06_comparar_seleccion_zl_vs_modelo_diario.R`
7. `zona_limpia/08_modelo_problema_observado_zl_xgboost.R`
8. `zona_limpia/09_diagnostico_criterio_levante_zl.R`
9. `zona_limpia/11_diagnostico_correspondencia_com_zl_territorio.R`
10. `zona_limpia/12_modelo_propension_visita_zl_y_ajuste_correspondencia.R`

Reportes:

- `zona_limpia/reportes/07_visualizar_seleccion_zl_vs_modelo.qmd`
- `zona_limpia/reportes/10_sesgos_seleccion_zona_limpia.qmd`
- `zona_limpia/reportes/13_modelo_problema_observado_zl.qmd`

## Decisiones Que No Hay Que Perder

- `Voluminosos` queda separado y no cuenta como problema comparable estricto con COM.
- Problemas comparables ZL: `basura_fuera` y `contenedor_desbordado`.
- Meses `202508`, `202509`, `202601` y `202602` se excluyen de analisis por cobertura anomala.
- El campo `municipio` original esta incompleto. Para cobertura territorial se debe usar el municipio asignado espacialmente al cluster; este criterio recupera visitas del Municipio B desde 2025-09-11 y cobertura diaria intensa desde 2026-05-14.
- COM no es verdad absoluta: depende de propension territorial a reclamar.
- Zona Limpia con visita efectiva se trata como evidencia observacional de campo.
- El modelo de problema observado ZL usa COM solo para definir target, no como feature.
- El ajuste por propension intenta corregir seleccion observable, pero no convierte la lectura en verdad poblacional definitiva.
- Las variables climaticas INUMET se evaluaron como experimento; no quedan promovidas al baseline ZL actual.
- El modelo amplio ZL con municipio/CCZ/barrio queda como diagnostico territorial; la cascada parsimoniosa marca `operativo_segmento` como candidato mas prudente.

## Outputs Relevantes

Comparacion COM-ZL:

- `data/processed/zona_limpia/comparacion_com_zona_limpia_cluster_dia/`
- `zona_limpia/outputs/comparacion_com_zona_limpia_resumen_estado*.csv`

Seleccion ZL vs modelo:

- `zona_limpia/outputs/seleccion_zl_vs_modelo_diario_logistico_reducido_d2.csv`
- `zona_limpia/outputs/seleccion_zl_vs_modelo_mensual_logistico_reducido_d2.csv`

Modelo problema observado:

- [[modelo_zona_limpia]]
- `zona_limpia/reportes/13_modelo_problema_observado_zl.qmd`
- `data/processed/modelos/zona_limpia_problema_observado_xgboost/`
- `zona_limpia/outputs/modelo_zl_observado_*.csv`
- `zona_limpia/outputs/modelo_zl_observado_resumen_splits.csv`
- `zona_limpia/outputs/modelo_zl_observado_metricas_random_dia_reps.csv`
- `zona_limpia/outputs/modelo_zl_observado_metricas_targets.csv`
- `zona_limpia/outputs/experimentos_clima/`
- `outputs/experimentos_clima/features_importancia_com_y_zl.csv`
- `zona_limpia/outputs/experimentos_cascada_zl/`

Sesgos y propension:

- `zona_limpia/outputs/diagnostico_levante_zl_*.csv`
- `zona_limpia/outputs/correspondencia_com_zl_territorio_*.csv`
- `zona_limpia/outputs/correspondencia_com_zl_ipw_*.csv`
- `zona_limpia/outputs/propension_visita_zl_*.csv`

## Que Documentar Si Se Cambia Algo

- Siempre revisar si corresponde actualizar `zona_limpia/README.qmd`.
- Si cambia una decision o lectura estable: `documentacion/HITOS.md`.
- Si se abre, avanza o cierra una tarea: `TAREAS.md`.
- Si cambia el modelo ZL o su interpretacion: `zona_limpia/reportes/13_modelo_problema_observado_zl.qmd` y referencia breve en `documentacion/modelos.qmd`.
- Si cambia esta guia de trabajo: esta nota y [[tareas_por_tipo]].

## Riesgos

- Generalizar desde visitas ZL a toda la ciudad sin corregir ni explicitar supuestos.
- Agrupar por el campo `municipio` original y omitir las visitas recuperables mediante la asignacion espacial del cluster.
- Mezclar `Voluminosos` con problemas comparables.
- Usar COM como feature en modelos cuyo objetivo es problema observado ZL limpio de COM.
- Comparar modelo COM contra ZL sin aclarar que optimizan objetivos distintos.

## Pendiente De Confirmar

- Recalculo de los diagnosticos historicos que excluyeron Municipio B bajo la hipotesis de una fuente faltante.
- Comparacion del modelo ZL puro contra ajustes por propension de visita.
- Integracion futura del score ZL puro con el score COM en la app operativa.
