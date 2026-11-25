# R06 - ZL y entrenamiento COM/ZL

- Estado: finalizada
- Prioridad: alta
- Dependencias: R05

## Contexto y objetivo

Incorporar ZL efectivo y reproducir entrenamientos pertinentes de ambas familias.

## Fuentes originales concretas

- [zona_limpia/funciones_zona_limpia.R](../../zona_limpia/funciones_zona_limpia.R)
- [zona_limpia/04_comparar_com_zona_limpia_cluster_dia.R](../../zona_limpia/04_comparar_com_zona_limpia_cluster_dia.R)
- [zona_limpia/08_modelo_problema_observado_zl_xgboost.R](../../zona_limpia/08_modelo_problema_observado_zl_xgboost.R)
- [scripts/modelo_logistico_cluster_dia_reducido.R](../../scripts/modelo_logistico_cluster_dia_reducido.R)
- [scripts/construir_app_modelos_largo_historico.R](../../scripts/construir_app_modelos_largo_historico.R)

## Entradas

COM completo, etiquetas, universo ZL y bundles/recetas efectivos.

## Salidas

Target/features ZL, adaptador COM/ZL y entradas de entrenamiento/evaluacion.

## Plan propuesto

Primero bundle fijo y preprocesamiento; despues extraer solo entrenamientos seleccionados.

## Diagnostico inicial (previo al acuerdo 2026-10-22)

- Implementados `R/features/zl_receta.R` y `R/modelos/zl_xgboost.R` para derivar las 36 variables numericas y puntuar el escenario efectivo con el bundle fijo.
- `herramientas_migracion/importar_referencia_zl_r06.R` importo el bundle y reconstruyo en 7 segundos las ocho filas congeladas de `2026-05-24`; salida aislada en `runtime/r06_zl/` y procedencia en `config/procedencia_r06_zl.json`.
- Se verifico que las 36 variables reconstruidas coinciden con las formulas del codigo fuente y que la matriz resultante coincide con la receta original (`matrix_equal=TRUE`).
- La comparacion de scores no pasa: cinco de ocho coinciden y tres difieren. Diferencia absoluta maxima: `0.05725884`. No se certifica equivalencia ni seleccion ZL.
- Desvios: `CL000288` 0.7790183 vs 0.8162721; `CL001809` 0.7521572 vs 0.7754449; `CL001899` 0.7574974 vs 0.8147562 (nuevo vs referencia). La causa no quedo atribuida al vector de features ni a su matriz.
- No se ejecuto entrenamiento completo ni se preparo aun un runner aislado para el escenario seleccionado. Sigue pendiente extraer y validar la preparacion integral COM/ZL y preparar los entrenamientos seleccionados. No usar el script legado directamente porque entrena varios escenarios y escribe en sus rutas configurables; primero dejar runners y destinos aislados. Las corridas de duracion incierta se entregaran al usuario con comandos exactos.

## Acuerdo de validacion 2026-10-22

El usuario aprobo acotar la investigacion historica. La aceptacion de migracion exige comparar codigo original y reconstruido con el mismo bundle e insumos actuales, en lugar de exigir atribuir la diferencia con la publicacion anterior. Los tres desvios publicados se conservan como pendiente de procedencia para la aceptacion previa al reemplazo del sistema vigente; no se asume una causa ni se declara equivalencia historica.

- Ejecutado `herramientas_migracion/comparar_inferencia_zl_r06.R`: ocho filas, 36 variables, diferencia de score cero, matriz/rankings/flags top iguales. Se extraen solo funciones del publicador original sin ejecutar su cuerpo principal.
- Implementados `R/entrenamiento/com_zl.R`, `scripts/entrenar_modelo.R` y `herramientas_migracion/preparar_entrenamiento_r06.R`. El preparador conserva el orden de features al unir etiquetas ZL; el ejecutable de entrenamiento no llama al legado ni activa modelos.
- Ejecutado `tests/test_entrenamiento_r06.R`: ambos entrenamientos y preparadores pasan con fixtures pequenas, splits separados y exclusion de visitas no efectivas/Voluminosos. Esto no reemplaza la corrida completa.
- [Evidencia de implementacion y hashes de los archivos probados](../config/validacion_r06_implementacion.json).
- Pendiente obligatorio: preparar y entrenar COM/ZL completos, revisar su salida y confirmar contratos/evaluacion. [Comandos exactos, requisitos, destino y resultado esperado](../cerebro_rf/entrenamiento_r06.md). La duracion/memoria de las corridas completas es incierta; las ejecuta el usuario.

Las notas anteriores conservan el diagnostico inicial. Las advertencias regionales de R no impidieron las pruebas. La validacion de migracion acotada pasa; R06 permanece en proceso por la validacion de entrenamiento completo y los restantes contratos de la ficha.

## Criterio de finalizacion

Inferencia ZL equivalente al codigo original con el mismo modelo e insumos actuales, incluyendo claves, scores, ranking y seleccion en el alcance probado; procesos de entrenamiento seleccionados validados. Las diferencias con publicaciones historicas quedan registradas como procedencia pendiente, sin certificar paridad historica. Una corrida obligatoria pendiente o un contrato de implementacion sin validar mantiene R06 abierta.

## Cierre 2026-10-22

El usuario ejecuto preparacion y entrenamiento completos en `runtime/r06_entrenamiento_20261022_102731/`. COM ajusto en 21.15 s y ZL en 8.61 s. Se revisaron las salidas guardadas: candidatos no promovidos, claves unicas, meses COM separados y dias ZL contenidos en un solo split. COM evaluo 3.969.394 filas tras el corte inicial; ZL evaluo 138.171.

El AUC COM inicial quedo NA por desbordamiento entero en el calculo de positivos por negativos. Se corrigio usando double y se recalcularon metricas sobre predicciones existentes, sin reentrenar ni modificar modelos. `tests/test_metricas_r06.R` pasa con 100.000 filas, ranking perfecto/invertido, empates y una sola clase. AUC COM train/validacion/test: 0.7719173 / 0.7527056 / 0.7547719; ZL: 0.6549678 / 0.6251992 / 0.6298416.

Las metricas revisadas viven en `com/metricas_corregidas.csv` y `zl/metricas_corregidas.csv` dentro de esa corrida. Se preservan los `resultado.rds` y CSV originales; el resultado COM original conserva AUC NA, por lo que se debe consultar el CSV corregido. No quedan corridas obligatorias pendientes para este alcance de R06. La discrepancia historica sigue registrada para R10. La siguiente tarea es R07, pendiente y sin ejecutar.

## Notas y decisiones pendientes

No sustituir operativo_segmento/random_dia_estratificado_mes por candidatos T032 ni activar ventanas moviles.

Aplicar [politica de pruebas y corridas largas](../cerebro_rf/reglas_trabajo.md). No finalizar con validaciones obligatorias pendientes. No ejecutar la tarea siguiente sin instruccion.

[Volver al indice](index.md)

