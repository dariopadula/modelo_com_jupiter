# R07 - Agregado A0 y P3 con entrenamiento

- Estado: finalizada
- Prioridad: alta
- Dependencias: R06

## Contexto y objetivo

Reproducir el compuesto y eliminar dependencia del target respecto de una publicacion previa de la app.

## Fuentes originales concretas

- [scripts/probar_xgboost_correccion_estructural_com.R](../../scripts/probar_xgboost_correccion_estructural_com.R)
- [scripts/comparar_ventanas_propension_xgboost_com.R](../../scripts/comparar_ventanas_propension_xgboost_com.R)
- [scripts/comparar_poda_xgboost_com.R](../../scripts/comparar_poda_xgboost_com.R)
- [scripts/construir_features_compartidas_modelos.R](../../scripts/construir_features_compartidas_modelos.R)
- [scripts/construir_tablas_historicas_app_v2.R](../../scripts/construir_tablas_historicas_app_v2.R)

## Entradas

Datos canonicos, features segmento/dia y bundles A0/P3 verificados.

## Salidas

Margen A0, cinco features P3, inferencia y series Montevideo/barrio; entrenamiento compuesto.

## Plan propuesto

Derivar target desde fuentes canonicas; comparar universo; extraer solo recorrido A0/P3; preservar OOF temporal.

## Validacion

Equivalencia con CSV P3 en muestra; exposicion, margen, orden de variables y agregacion; revisar q60 frente a q30.

## Avance y validacion 2026-10-22

- Implementados receta canonica, adaptador fijo, entrenador OOF/seleccion/refit y tres entradas propias en scripts/. Los puentes de migracion viven separados en herramientas_migracion/.
- Hashes A0/P3 contrastados con R01; muestra de 2026-05-24 importada sin materializar los CSV completos. A0 reproduce su margen en la muestra; P3 reproduce 924 segmentos y 62 barrios. Diferencia total contra CSV: 3.41e-13, tolerancia 1e-6.
- Features propias contrastadas con bloques originales en 2.508 filas de fixture, incluyendo pertenencia al universo antiguo de 90 observaciones. Preservadas ventanas por observaciones D-2, q7/q60 y orden de cinco variables.
- Ejecutadas pruebas de no leakage D/D-1, fallback de segmento, rechazo de barrio nuevo y de A0 final en train. Puente canonico y preparacion probados sin una carpeta de app. Entrenamiento pequeno con nueve folds OOF y CLI validado.
- Pendiente obligatorio: preparacion completa desde los insumos actuales y entrenamiento completo a cargo del usuario, y revision posterior de OOF, exposicion y metricas. No se ejecutaron corridas extensas ni se promovieron modelos.

[Alcance, evidencia y comandos exactos](../cerebro_rf/agregado_r07.md). La tarea sigue en proceso; no ejecutar R08.

[Registro de comprobaciones y hashes de los archivos probados](../config/validacion_r07.json).

## Criterio de finalizacion

Inferencia y entrenamiento compuesto validados; bundle A0 compatible identificado.

## Cierre 2026-10-22

Corrida completa del usuario en `runtime/r07_entrenamiento_20261022_111500/`: 3.951.011 filas canonicas, 469.817 filas A0 y 380.815 filas P3. Entrenamiento: 264.97 segundos; P3 selecciono 44 iteraciones. Candidato no promovido.

Revision de archivos aprobada: nueve folds OOF usan solo fechas anteriores al primer dia del mes objetivo; A0 final termina en 2025-12-31. Claves unicas, exposiciones positivas, observados dentro de la exposicion y probabilidades finitas entre cero y uno. Las sumas por barrio coinciden con Montevideo en prediccion, observados y exposicion.

MAE/RMSE de validacion: 109.8434 / 147.8380; de test: 139.8526 / 169.6433. Sesgo de test -43.99863 (subestimacion media diaria). Estas metricas validan la ejecucion; no constituyen aprobacion para promover el candidato.

No quedan corridas obligatorias pendientes para este alcance. R08 es la siguiente tarea pendiente y no se ejecuto.

## Notas y decisiones pendientes

No usar margen in-sample en lugar de OOF ni copiar candidatos de reevaluacion; corrida larga para usuario.

Aplicar [politica de pruebas y corridas largas](../cerebro_rf/reglas_trabajo.md). No finalizar con validaciones obligatorias pendientes. No ejecutar la tarea siguiente sin instruccion.

[Volver al indice](index.md)

