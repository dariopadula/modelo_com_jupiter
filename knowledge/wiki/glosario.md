# Glosario

Ver tambien [[arquitectura]], [[componentes]], [[tareas_por_tipo]] y [[decisiones]].

## AUC

Metrica de ranking para clasificacion binaria. Mide si el modelo asigna mayor score a casos positivos que a negativos.

## Base `cluster_id`/`dia`

Unidad principal de modelado. Cada fila representa un cluster en un dia.

## Capture Rate

Proporcion de positivos totales capturada dentro de un grupo priorizado, por ejemplo top 10% de riesgo.

## CCZ

Centro Comunal Zonal. Se usa como atributo territorial administrativo asignado a clusters.

## Cluster

Grupo espacial estable de posiciones de contenedores. Permite modelar zonas de contenedores cercanos en vez de contenedores individuales.

## COM

Fuente de reclamos ciudadanos. En el modelo principal define el target `tuvo_reclamo` para incidentes como contenedor desbordado o basura fuera del contenedor.

## `com_completo`

Base ampliada para analisis Zona Limpia. Incluye incidentes usados por el modelo y registros cuyo incidente comienza con `Zona limpia`. No reemplaza `data/parquet/com/`.

## D-2

Regla operativa para usar reclamos historicos cerrados hasta dos dias antes del dia objetivo. Se adopta por frecuencia de actualizacion de COM en scoring matinal.

## Elegibilidad De Contenedor

Regla que define si un contenedor activo/inferido puede usarse para asignacion y modelado. La regla vigente usa actividad observada o inferida con limites de 8 dias desde ultima observacion y 15 dias de tramo inferido.

## Exceso Sobre Periodo Teorico

Variable exploratoria usada en Zona Limpia:

```text
tiempo desde ultimo levante - periodo teorico
```

Suele truncarse en cero y en un maximo, por ejemplo 7 dias.

## Features `_pred`

Variables predictivas calculadas con informacion disponible al corte operativo, por ejemplo `D 01:00`. Evitan usar levantes posteriores al momento de prediccion.

## IPW

Inverse Probability Weighting. En Zona Limpia se usa para ponderar visitas segun la inversa de su propension de visita estimada.

## Lift

Precision del grupo priorizado dividida por la prevalencia general. Un lift mayor que 1 indica concentracion de positivos frente a seleccion aleatoria.

## Logloss

Metrica probabilistica que penaliza predicciones muy seguras pero equivocadas.

## Municipio B

Municipio con cobertura incompleta en la fuente actual de Zona Limpia. Sus lecturas territoriales deben marcarse como pendientes hasta integrar la fuente faltante.

## Problema Comparable Zona Limpia

Problema observado por Zona Limpia comparable con el target COM. Incluye `basura_fuera` y `contenedor_desbordado`; excluye `Voluminosos` en la metrica principal.

## Propension De Visita

Probabilidad estimada de que un `cluster_id`/`dia` sea visitado por Zona Limpia dadas features previas de levante, territorio y calendario.

## Scoring Operativo

Proceso fuera de la app que genera predicciones acumuladas, rankings, observados cerrados, metricas y controles de frescura.

## Segmento Censal

Unidad territorial usada para asignar variables demograficas y socioeconomicas a clusters.

## Target `tuvo_reclamo`

Indicador binario de si un cluster tuvo al menos un reclamo COM valido ese dia.

## Universo Comparable ZL

Cluster-dias donde Zona Limpia tuvo observacion efectiva: problema comparable, voluminosos o limpio. Casos no visitados, no encontrados o no realizados no se tratan como acuerdo/desacuerdo con COM.

## Voluminosos

Categoria Zona Limpia registrada separadamente. No se considera problema comparable estricto con COM en las metricas principales.

## Zona Limpia

Registros COM especiales asociados a visitas/observaciones de campo. Se usan para auditar seleccion, problemas observados y brechas frente a reclamos COM.
