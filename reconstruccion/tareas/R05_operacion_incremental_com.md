# R05 - Operacion incremental COM

- Estado: finalizada
- Prioridad: alta
- Dependencias: R04

## Contexto y objetivo

Mantener estado y procesar pendientes sin alterar scores emitidos.

## Fuentes originales concretas

- [funciones/scoring_operativo_utils.R](../../funciones/scoring_operativo_utils.R)
- [scripts/construir_estado_historico_cluster.R](../../scripts/construir_estado_historico_cluster.R)
- [scripts/emular_scoring_operativo_bloque_cluster_dia.R](../../scripts/emular_scoring_operativo_bloque_cluster_dia.R)
- [scripts/proceso_scoring_operativo_cluster_dia.R](../../scripts/proceso_scoring_operativo_cluster_dia.R)
- [scripts/validar_proceso_scoring_operativo.R](../../scripts/validar_proceso_scoring_operativo.R)

## Entradas

Features, modelo fijo, cierre y estado inicial identificado.

## Salidas

Scores por bloque, estado y observados posteriores con controles.

## Plan propuesto

Separar calculo de acceso/publicacion; conservar memoria historica y politica de pendientes.

## Validacion

Un dia y varios dias equivalen; repeticion idempotente; fuente atrasada bloquea; observados nuevos no cambian scores.

Estado de validacion: aprobada el 21/10/2026. `tests/test_scoring_incremental_com.R`: bloque de tres dias equivalente a llamadas sucesivas; idempotencia; bloqueo por cierre atrasado sin avanzar estado; cierre posterior agrega observados y mantiene scores; cierre ausente y politica incorrecta detienen el motor. Regresiones R02 (26), R03 y R04 (16 reglas y features/score) aprobadas. Las marcas de fuente del test son sinteticas; fuentes reales y compatibilidad del corte nuevo con el modelo quedan pendientes y documentadas, no se declaran validadas.

## Criterio de finalizacion

Validaciones incrementales pasan y estado/predicciones quedan aislados. Cumplido para la operacion local con marcas controladas; no implica habilitacion productiva.

## Notas y decisiones pendientes

El script de emulacion es dependencia operativa; no descartarlo por el nombre.

Antecedente R04: el snapshot historico no declara cierre contractual y no puede habilitar scoring diario por inferencia del ultimo evento. Los nuevos levantes usan corte corregido 01:00 America/Montevideo, aprobado por el usuario; antes de operarlos con el bundle legado verificar su efecto, sin reescribir scores historicos. Mayo conserva una discrepancia de predicciones sin causa atribuida: no extender la equivalencia de marzo a ese periodo. Ver datos_com_r04.md en el cerebro.

Aplicar [politica de pruebas y corridas largas](../cerebro_rf/reglas_trabajo.md). No finalizar con validaciones obligatorias pendientes. No ejecutar la tarea siguiente sin instruccion.

Implementacion y limites: [evidencia R05](../cerebro_rf/operacion_com_r05.md). Siguiente tarea: R06; requiere autorizacion en otro chat.

[Volver al indice](index.md)

