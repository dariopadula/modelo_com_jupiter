# Entrenamiento seleccionado COM/ZL (R06)

Estado: R06 finalizada. Preparación y entrenamiento completos ejecutados por el usuario en `runtime/r06_entrenamiento_20261022_102731/` y revisados. COM ajustó en 21,15 s y ZL en 8,61 s. Los modelos son candidatos aislados y no cambian la app ni la selección activa. Se corrigió el desbordamiento entero del AUC COM y se recalcularon métricas sin reentrenar: consultar `metricas_corregidas.csv` en cada carpeta. Los RDS y CSV originales se conservan; el resultado COM original mantiene AUC NA. Los comandos siguientes quedan como referencia reproducible, no como una corrida pendiente.

## Alcance

- COM: logística reducida D-2, 15 variables, fechas y meses de train/validación/test fijados en `config/referencia_local_r01.json`. La historia se rezaga antes de cortar la fecha mínima. Imputación y estandarización se ajustan únicamente con train.
- ZL: `operativo_segmento`, 36 variables, 120 rondas y parámetros del bundle R01. Se excluyen visitas no efectivas y Voluminosos. Split `random_dia_estratificado_mes`, semilla 20260703 y días completos dentro de un solo split. La imputación se aprende únicamente en train.
- No se entrenan candidatos T032, variantes demográficas, ventanas móviles ni A0/P3. No se busca una configuración mejor ni se promueve el candidato generado.
- La entrada conserva el orden de primera aparición de los días para reproducir el algoritmo original del split ZL. Se guardan las asignaciones efectivas en `splits.csv`. Un cambio del snapshot/orden puede cambiar el ajuste: estos candidatos no se presentan como copias binarias del modelo histórico.

Funciones: [entrenamiento](../R/entrenamiento/com_zl.R). Entrada operativa: [entrenar_modelo.R](../scripts/entrenar_modelo.R). El [preparador de migración](../herramientas_migracion/preparar_entrenamiento_r06.R) lee las fuentes locales originales por columnas/períodos y produce paquetes RDS propios. La función de entrenamiento y su ejecutable no llaman al código antiguo.

El preparador consume las features históricas y la comparación COM/ZL ya existentes; no descarga datos ni reconstruye fuentes crudas. Esto tampoco certifica todavía la actualización integral de fuentes ZL.

## Comprobaciones ejecutadas

- Comparación del publicador original y el adaptador ZL con el mismo bundle y ocho filas actuales: diferencia de scores cero; matriz de 36 variables, rankings y flags top iguales. Comando: `herramientas_migracion/comparar_inferencia_zl_r06.R <raiz_original>`.
- `tests/test_entrenamiento_r06.R`: ejecuta los dos entrenamientos y sus CLI con fixtures pequeñas; verifica probabilidades, tres splits, estado candidato y split ZL por día. Verifica ambos preparadores contra Parquet de prueba, incluyendo exclusión de Voluminosos y visitas no efectivas. Son pruebas de implementación, no equivalencia científica de un entrenamiento completo.
- La comparación con la publicación de mayo conserva tres desvíos y su causa no está determinada. Desde el acuerdo del 22/10/2026 queda como pendiente de procedencia y de aceptación antes de sustituir el sistema vigente; no bloquea por sí sola R06.

## Corridas completas a cargo del usuario

Requisitos: R 4.5.1 y los paquetes ya instalados `data.table`, `arrow`, `dplyr`, `jsonlite` y `xgboost` (referencia 1.7.11.1). Si la biblioteca no está en su ubicación habitual de Windows, definir `RF_R_LIBRARY`. Deben existir las fuentes Parquet originales y los artefactos R01/R06 en `runtime/`. No instalar paquetes ni consultar Impala para estas corridas.

El dataset COM completo puede requerir bastante memoria al construir matrices y ajustar la logística. No hay una estimación fiable de duración ni memoria para esta máquina; por eso la preparación y los ajustes completos no se iniciaron desde Codex. La ruta siguiente es nueva y aislada; los scripts rechazan sobrescribir archivos o directorios existentes.

Desde PowerShell:

```powershell
Set-Location 'C:\DARIO\Git\modelo_com_jupiter\reconstruccion'
$r06Rscript = 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe'
$r06Original = 'C:\DARIO\Git\modelo_com_jupiter'
$r06Run = Join-Path 'runtime' ('r06_entrenamiento_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $r06Run -ErrorAction Stop | Out-Null

& $r06Rscript --vanilla herramientas_migracion/preparar_entrenamiento_r06.R com $r06Original (Join-Path $r06Run 'entrada_com.rds')
if ($LASTEXITCODE -ne 0) { throw 'Fallo la preparacion COM; detener y compartir la salida' }
& $r06Rscript --vanilla scripts/entrenar_modelo.R (Join-Path $r06Run 'entrada_com.rds') (Join-Path $r06Run 'com')
if ($LASTEXITCODE -ne 0) { throw 'Fallo el entrenamiento COM; detener y compartir la salida' }

& $r06Rscript --vanilla herramientas_migracion/preparar_entrenamiento_r06.R zl $r06Original (Join-Path $r06Run 'entrada_zl.rds')
if ($LASTEXITCODE -ne 0) { throw 'Fallo la preparacion ZL; detener y compartir la salida' }
& $r06Rscript --vanilla scripts/entrenar_modelo.R (Join-Path $r06Run 'entrada_zl.rds') (Join-Path $r06Run 'zl')
if ($LASTEXITCODE -ne 0) { throw 'Fallo el entrenamiento ZL; detener y compartir la salida' }
```

Resultado esperado: cada preparador imprime `R06_TRAINING_INPUT_OK` y cada entrenamiento `R06_TRAINING_OK` con `status=candidato_no_promovido`. Cada carpeta `com/` y `zl/` contiene `resultado.rds`, `modelo_candidato.rds`, `metricas.csv` y `splits.csv`. El resultado registra procedencia, hash MD5 del paquete de entrada, semilla, versiones y duración. Ninguno se activa automáticamente.

Compartir la salida de consola y ambos `metricas.csv`. Codex revisará tamaños, meses, clases, convergencia, métricas y la evidencia antes de dar por validada la corrida. Si falla o falta esta ejecución obligatoria, R06 continúa en proceso. No ejecutar R07 como parte de estos comandos.

[Ficha R06](../tareas/R06_zona_limpia_entrenamiento.md) | [Decisiones](decisiones.md)
