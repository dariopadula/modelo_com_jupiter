# Inferencia operacional

Estado: inferencia COM fija acotada implementada en R03 y motor incremental de COM implementado en R05 con fixtures de frescura declarada. La equivalencia del corte nuevo con el bundle legado y el cierre de fuentes reales siguen pendientes. Ver [evidencia R03](../recorrido_com_r03.md) y [evidencia R05](../operacion_com_r05.md).

Aplicar modelos aprobados y mantener estado sin cambiar scores emitidos.

R07 incorpora el adaptador propio A0/P3 para series por segmento, barrio y Montevideo. Inferencia fija equivalente en muestra del 24/05/2026; rechaza A0 final en fechas de train y versiones espaciales incompatibles. No está conectado a la app ni a la operación diaria integral. [Evidencia y límites R07](../agregado_r07.md).

## Entrada y salida

Bundle, features, cierres y estado; salida: scores, rankings y nuevo estado.

## Contrato y límites

Adaptador por familia; observados posteriores separados de predicciones; no scheduler ni reproceso masivo inicial.

## Fuentes para migrar

- [funciones/scoring_operativo_utils.R](../../../funciones/scoring_operativo_utils.R)
- [scripts/emular_scoring_operativo_bloque_cluster_dia.R](../../../scripts/emular_scoring_operativo_bloque_cluster_dia.R)
- [scripts/proceso_scoring_operativo_cluster_dia.R](../../../scripts/proceso_scoring_operativo_cluster_dia.R)
- [scripts/construir_app_modelos_largo_historico.R](../../../scripts/construir_app_modelos_largo_historico.R)

Tareas: R03, R05, R06, R07. Ver [índice](../../tareas/index.md). La equivalencia R03 está acotada al bloque de marzo; las validaciones incrementales R05 usan cierres sintéticos. Ver las notas vinculadas arriba antes de ampliar esos resultados.

[Volver al cerebro](../index.md)

