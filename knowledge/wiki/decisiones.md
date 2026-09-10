# Decisiones

Ver tambien [[arquitectura]], [[componentes]], [[flujo_trabajo]], [[tareas_por_tipo]] y [[glosario]].

Esta nota registra decisiones que se infieren claramente de la documentacion actual. No incluye hipotesis no documentadas.

## Unidad De Modelado

- La unidad principal es `cluster_id`/`dia`, no `contenedor_id`/`dia`.
- Motivo documentado: un reclamo puede representar un problema de un conjunto de contenedores cercanos; modelar por cluster reduce ruido y falsos ceros.
- Fuentes: `README.qmd`, `documentacion/flujo_datos.qmd`, `documentacion/HITOS.md`.

## Clusters Estables

- Se entrena una referencia espacial versionada de clusters.
- Las posiciones nuevas se asignan contra la referencia sin modificarla.
- Los puntos ruido pueden recibir cluster propio.
- Fuentes: `README.qmd`, `documentacion/flujo_datos.qmd`.

## Asignacion COM

- COM se asigna al contenedor activo/elegible mas cercano del mismo dia.
- `asignado` y `revision` entran al target; `pendiente` queda fuera.
- Umbrales documentados: hasta 50 m `asignado`, 50 a 100 m `revision`, mas de 100 m `pendiente`.
- Fuentes: `documentacion/flujo_datos.qmd`.

## No Leakage Temporal

- Las features historicas excluyen el dia objetivo.
- Levantes predictivos usan corte `D 01:00` y sufijo `_pred`.
- El exceso sobre periodo teorico solo puede calcularse desde columnas predictivas de levante y periodo teorico.
- Scoring operativo matinal usa COM cerrado hasta `D-2`.
- Las features climaticas predictivas se cierran en `D-1`.
- Reclamos de `D` nunca entran como features.
- Fuentes: `documentacion/flujo_datos.qmd`, `documentacion/proceso_scoring_operativo.qmd`.

## Modelo Logistico Reducido

- Se eligio un conjunto reducido de predictores para mejorar interpretabilidad y reducir colinealidad.
- Se excluyeron ratios tiempo/periodo y duplicados `min`/`median`/`max`.
- Se usa historia observada por tramos y `dias_desde_ultimo_reclamo_o_inicio_trunc_90`.
- Fuentes: `documentacion/modelos.qmd`, `documentacion/diagnostico_variables_modelo.qmd`, `documentacion/HITOS.md`.

## Comparacion De Modelos

- Random Forest y XGBoost usan las mismas variables del logistico reducido para comparar principalmente el algoritmo.
- El logistico reducido queda como referencia interpretable.
- Fuentes: `documentacion/modelos.qmd`, `documentacion/HITOS.md`.

## Scoring Operativo

- La app no calcula features ni corre modelos.
- El proceso operativo publica predicciones acumuladas y controles.
- Las predicciones historicas no se recalculan por defecto.
- Se usan staging, respaldos y lock para evitar publicaciones incompletas o simultaneas.
- Fuentes: `documentacion/proceso_scoring_operativo.qmd`, `documentacion/HITOS.md`.

## App Operativa

- La app es de solo lectura.
- Consume salidas publicadas por scoring.
- Incluye vistas de dia operativo, mapa, historico y estado de datos.
- La primera agregacion territorial usa hexagonos; DBSCAN no se ejecuta dentro de la app.
- Fuentes: `documentacion/proceso_scoring_operativo.qmd`, `app_operativa/README.md`.

## Zona Limpia Separada Del Pipeline Principal

- Los analisis Zona Limpia viven en `zona_limpia/`.
- `data/parquet/com/` no se altera; `data/parquet/com_completo/` se usa para analisis ampliados.
- `Voluminosos` no cuenta como problema comparable estricto con COM en la metrica principal.
- Problemas comparables: `basura_fuera` y `contenedor_desbordado`.
- Fuentes: `zona_limpia/README.qmd`, `documentacion/HITOS.md`.

## Meses Excluidos En Zona Limpia

- `202508`, `202509`, `202601` y `202602` se excluyen de analisis Zona Limpia por cobertura anomala.
- La exclusion no modifica `com_completo`.
- Fuente: `zona_limpia/README.qmd`, `documentacion/HITOS.md`.

## Clima INUMET En Modelos

- Las variables climaticas de `Melilla G3` quedan disponibles como features ex ante hasta `D-1`.
- La evaluacion exploratoria en XGBoost COM y ZL no alcanza para promover clima al baseline.
- Fuente: `documentacion/HITOS.md`, `TAREAS.md`.

## Exceso Sobre Periodo Teorico En COM

- La feature se evaluo como experimento en modelos COM.
- Tiene importancia en XGBoost, pero no mejora de forma robusta validacion/test.
- No se promueve al baseline operativo con la evidencia actual.
- Fuente: `documentacion/HITOS.md`, `TAREAS.md`.

## Municipio B En Zona Limpia

- Municipio B tiene cobertura incompleta en la fuente actual de Zona Limpia.
- No debe interpretarse como baja prioridad real ni ausencia de visitas.
- Se excluye de diagnosticos de correspondencia/propension hasta integrar la fuente faltante.
- Fuentes: `zona_limpia/README.qmd`, `zona_limpia/reportes/10_sesgos_seleccion_zona_limpia.qmd`, `TAREAS.md`.

## Propension De Visita Zona Limpia

- Se usa un ajuste exploratorio por propension para no generalizar mecanicamente desde puntos visitados por ZL.
- Target: `P(visita efectiva ZL | features previas de levante, territorio y calendario)`.
- Los ratios COM-ZL se recalculan con pesos IPW estabilizados.
- El ajuste no elimina la hipotesis de subreclamo, pero depende del supuesto de seleccion ignorable condicionada a features.
- Fuentes: `zona_limpia/README.qmd`, `zona_limpia/reportes/10_sesgos_seleccion_zona_limpia.qmd`, `TAREAS.md`.

## Pendiente De Confirmar

- Integracion de fuente faltante de Municipio B.
- Decision final sobre usar regla alternativa de actividad reciente por levantes en ultimos 5, 7 o 10 dias.
- Ruta productiva final y versionado definitivo de artefactos operativos.
