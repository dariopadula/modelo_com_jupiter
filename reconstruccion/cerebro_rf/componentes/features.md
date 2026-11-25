# Features históricas y operacionales

Estado: receta COM migrada en R03 y construcción propia de base/historia desde tablas canónicas preparadas en R04. Bloque de marzo validado; features para nuevas familias siguen pendientes. Ver [evidencia R04](../datos_com_r04.md).

Compartir reglas y recetas sin forzar una matriz única para todas las familias.

## Entrada y salida

Datos canónicos, asignaciones, calendario y contexto; salida: tablas cluster/día o segmento/día con esquema/corte.

## Contrato y límites

Preservar COM D-2 y levantes D 01:00; comparar ventanas q60/q30 antes de sustituir.

## Fuentes para migrar

- [funciones/construir_base_cluster_dia.R](../../../funciones/construir_base_cluster_dia.R)
- [funciones/construir_features_historicas_cluster_dia.R](../../../funciones/construir_features_historicas_cluster_dia.R)
- [scripts/construir_features_compartidas_modelos.R](../../../scripts/construir_features_compartidas_modelos.R)
- [scripts/comparar_ventanas_propension_xgboost_com.R](../../../scripts/comparar_ventanas_propension_xgboost_com.R)

Tareas: R04, R06, R07. Ver [índice](../../tareas/index.md). Evidencia de migración y equivalencia: pendiente; registrar en la ficha correspondiente.

[Volver al cerebro](../index.md)

