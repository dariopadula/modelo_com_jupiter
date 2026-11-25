# Agregado A0 + P3 (R07)

Estado: R07 finalizada. Corrida completa 20261022_111500 ejecutada por el usuario y revisada: nueve folds OOF correctos, 44 iteraciones P3 y 264,97 s de entrenamiento. Claves, exposición, probabilidades y sumas barrio/Montevideo verificadas. Candidato no promovido. Los comandos siguientes quedan como referencia reproducible; no hace falta repetirlos.

## Recorrido migrado

1. [Importar insumos](../herramientas_migracion/importar_insumos_agregado_r07.R): features COM canónicas de clusters existentes, territorio y feriados. Lee columnas/períodos explícitos; no consulta predicciones ni observados de la app. Es un puente de migración, no una dependencia del procesamiento propio.
2. [Preparar agregado](../scripts/preparar_agregado.R): construye el target desde `tuvo_reclamo`, exposición A0 y las cinco variables P3 mediante [receta propia](../R/features/agregado_receta.R).
3. [Predecir](../scripts/predecir_agregado.R): aplica A0 final y P3 con margen explícito; devuelve tablas por segmento, barrio y Montevideo. Rechaza usar A0 final sobre fechas de entrenamiento. [Adaptador](../R/modelos/agregado_a0_p3.R).
4. [Entrenar](../scripts/entrenar_agregado.R): A0 OOF por mes con entrenamiento estrictamente anterior; A0 final solo con train; selección P3 antes/después del 01/11/2025 dentro de train y refit con la mejor iteración. No ajusta candidatos alternativos. [Entrenador](../R/entrenamiento/agregado_a0_p3.R).

El predictor acepta una fecha objetivo opcional como cuarto argumento para seleccionar un día de un paquete histórico completo. Sin fecha, todas las filas solicitadas deben estar fuera del entrenamiento; nunca se eliminan silenciosamente las fechas de train para aplicarles A0 final.

## Contratos y decisiones confirmadas

- P3: `media_tiempo_levante`, `rms_q_7`, `rms_w_7`, `delta_q_7_60`, `es_feriado`, en ese orden; `base_margin` es el logit A0, acotando la probabilidad a `[1e-5, 1-1e-5]` como el legado.
- Las ventanas son de **observaciones** a D-2. El legado exige cobertura finita en 7, 15, 30, 60 y 90 aunque P3 use 7/60. No sustituir por q30 ni reinterpretar los saltos como días calendario.
- El prior de cluster usa fuerza 30 y el barrial fuerza 200; exceso positivo limitado a 3. Se conserva también la pertenencia a grupos segmento/día de la base antigua de 90 observaciones que anclaba los márgenes OOF.
- A0 se entrena sobre su universo amplio de clusters existentes; la exposición P3 cuenta únicamente los clusters elegibles de cada segmento/día. No intercambiar ambas exposiciones.
- Barrios nuevos se rechazan. Segmentos nuevos omiten el efecto aleatorio del segmento, conservando el fallback original. Los factores se leen en UTF-8; se fija el calendario español para que no dependa del idioma del sistema.
- Los targets desconocidos siguen NA. El snapshot importado no certifica cierre operativo ni habilita por sí solo scoring diario. La actualización/publicación integral se completa después, en R08-R10.
- El entrenamiento seleccionado fija las semillas 20260826 (A0) y 20260827 (P3) y registra un candidato independiente. No reproduce el consumo de aleatoriedad de las variantes descartadas que precedían a P3 en el script comparativo; no se exige identidad binaria de un reentrenamiento con los pesos históricos ni se promueve automáticamente su resultado. La paridad numérica se comprueba con los artefactos fijos.

## Evidencia ejecutada

Se importaron modelos con hashes iguales a R01 y solo el día 24/05/2026 de los CSV, leídos por bloques. El bundle A0 final es compatible en la muestra: máxima diferencia de probabilidad de aproximadamente `5,3e-16`. P3 reproduce 924 segmentos, 62 barrios y Montevideo (7.849 clusters evaluados); diferencia total contra el CSV `3,41e-13`, tolerancia `1e-6`.

`tests/test_agregado_r07.R` compara la receta nueva con bloques originales ejecutados sobre las mismas fixtures: 2.508 filas equivalentes. Cambiar los targets de D y D-1 no altera los predictores de D. Prueba fallback territorial y rechazo de A0 final en train, importación/preparación sin carpeta app y entrenamiento pequeño con nueve folds OOF. Esto valida implementación y separación temporal; no reemplaza la corrida completa.

Fuentes: `scripts/benchmark_modelo_segmento_barrio_com.R`, `scripts/explorar_carga_atraso_ponderada_propension_com.R`, `scripts/comparar_ventanas_propension_xgboost_com.R`, `scripts/probar_xgboost_correccion_estructural_com.R` y `scripts/comparar_poda_xgboost_com.R`. La capa `construir_features_compartidas_modelos.R` usa q30 y no reemplaza el recorrido seleccionado.

## Corrida completa del usuario

Requisitos: R 4.5.1 y paquetes existentes `arrow`, `dplyr`, `data.table`, `jsonlite`, `mgcv` y `xgboost`. Para importar la referencia fija se usa además `openssl`; ya fue ejecutado. Puede indicarse una biblioteca alternativa con `RF_R_LIBRARY`. No instalar dependencias ni consultar Impala.

La preparación completa necesita memoria para la historia cluster/día. El entrenamiento ajusta un A0 por mes OOF y otro final: los diagnósticos originales registran aproximadamente 15-22 segundos en varios folds, además del refit P3. No hay una estimación fiable para la máquina actual; la corrida completa y la preparación extensa quedan a cargo del usuario.

Desde PowerShell, en un destino nuevo y aislado:

```powershell
Set-Location 'C:\DARIO\Git\modelo_com_jupiter\reconstruccion'
$r07Rscript = 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe'
$r07Original = 'C:\DARIO\Git\modelo_com_jupiter'
$r07Run = Join-Path 'runtime' ('r07_entrenamiento_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $r07Run -ErrorAction Stop | Out-Null

& $r07Rscript --vanilla herramientas_migracion/importar_insumos_agregado_r07.R $r07Original 2026-05-24 (Join-Path $r07Run 'insumos.rds')
if ($LASTEXITCODE -ne 0) { throw 'Fallo la importacion R07; detener y compartir la salida' }
& $r07Rscript --vanilla scripts/preparar_agregado.R (Join-Path $r07Run 'insumos.rds') (Join-Path $r07Run 'bases.rds')
if ($LASTEXITCODE -ne 0) { throw 'Fallo la preparacion R07; detener y compartir la salida' }
& $r07Rscript --vanilla scripts/entrenar_agregado.R (Join-Path $r07Run 'bases.rds') (Join-Path $r07Run 'candidato')
if ($LASTEXITCODE -ne 0) { throw 'Fallo el entrenamiento R07; detener y compartir la salida' }
```

Se esperan `R07_INPUT_OK`, `R07_FEATURES_OK` y `R07_TRAINING_OK: status=candidato_no_promovido`. El directorio `candidato/` contiene `resultado.rds`, `bundle_candidato.rds`, `metricas.csv`, `auditoria_oof.csv`, `predicciones_diarias.csv` y `predicciones_barrio_dia.csv`. El resultado guarda semilla, parámetros, iteración seleccionada, procedencia, hash del paquete de entrada, versiones y duración. Se rechaza sobrescribir destinos.

Compartir salida de consola, `metricas.csv` y `auditoria_oof.csv`. Codex verificará los cortes OOF, exposición/universo de las bases y las métricas antes de cerrar R07. Los nuevos insumos pueden diferir del snapshot antiguo; no se atribuirá una diferencia a una causa sin evidencia ni se promoverá un modelo automáticamente. La ejecución 20261022_111500 ya fue revisada y R07 está finalizada. R08 requiere una nueva instrucción.

[Ficha R07](../tareas/R07_agregado_compuesto.md) | [Estado](estado_actual.md)
