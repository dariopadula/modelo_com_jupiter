# Scoring Operativo

Ver tambien [[tareas_por_tipo]], [[datos_y_leakage]], [[componentes]], [[arquitectura]], [[app_operativa]] y [[decisiones]].

## Para Que Sirve Esta Nota

Usar esta nota cuando la tarea involucre predicciones diarias, frescura de fuentes, tabla acumulada para la app, reprocesos, estado historico o app operativa.

## Que Leer Primero

1. `documentacion/proceso_scoring_operativo.qmd`
2. `AGENTS.md`, seccion Datos, Modelos y App
3. `app_operativa/README.md`, si la tarea toca la app
4. `documentacion/HITOS.md`, secciones de scoring operativo y app
5. `TAREAS.md`, tareas relacionadas con app/scoring

## Regla Temporal Vigente

Para predecir un dia objetivo `D`:

- levantes: informacion disponible hasta `D 01:00`;
- reclamos historicos: COM cerrado hasta `D-2`;
- reclamos de `D`: nunca entran como features;
- reclamos observados de `D`: se completan despues, cuando COM queda cerrado.

Esta regla existe para evitar leakage y para respetar la frecuencia real de actualizacion de fuentes.

## Arquitectura Operativa

El scoring corre fuera de la app:

```text
fuentes materializadas
  -> controles de frescura
  -> ventana reciente
  -> estado historico por cluster
  -> features operativas
  -> modelo
  -> predicciones congeladas
  -> observados cerrados
  -> app de solo lectura
```

## Scripts Principales

- `scripts/construir_estado_historico_cluster.R`
- `scripts/validar_estado_historico_incremental.R`
- `scripts/emular_scoring_operativo_cluster_dia.R`
- `scripts/emular_scoring_operativo_ventana_cluster_dia.R`
- `scripts/emular_scoring_operativo_bloque_cluster_dia.R`
- `scripts/proceso_scoring_operativo_cluster_dia.R`
- `scripts/validar_proceso_scoring_operativo.R`
- `scripts/construir_app_modelos_largo_historico.R`

Funciones relacionadas:

- `funciones/scoring_operativo_utils.R`
- `funciones/modelos_utils.R`
- `funciones/construir_base_cluster_dia.R`
- `funciones/construir_features_historicas_cluster_dia.R`

## Salidas Esperadas

En emulacion:

- `data/processed/app_emulacion*/predicciones_operativas_cluster_dia/`
- `data/processed/app_emulacion*/control_scoring/`
- `data/processed/app_emulacion*/metricas_diarias/`
- `data/processed/app_emulacion*/estado_historico_cluster/`

En proceso persistente:

- ruta definida por `OUT_BASE_APP`;
- staging en `.staging/<run_id>`;
- backups en `.backups/<run_id>`;
- lock `.scoring_operativo.lock`.

Salida historica multi-modelo para app:

- `app_operativa_v2/data/operacional/predicciones_operativas_cluster_dia/`
- `app_operativa_v2/data/operacional/control_scoring/`
- `app_operativa_v2/data/operacional/metricas_diarias/`

Unidad de fila: `cluster_id`, `dia_objetivo`, `modelo_id`, `version_modelo`.

Modelos actuales: `com_reclamo` y `zl_problema`.

## App Operativa

Archivos vigentes:

- `app_operativa_v2/app.R`
- `app_operativa_v2/R/datos_app.R`
- `app_operativa_v2/run_app.R`

La app:

- lee predicciones ya publicadas;
- muestra resumen, mapa, historico y estado de datos;
- no calcula features;
- no aplica modelos;
- no decide frescura de fuentes.
- permite seleccionar score COM o score ZL cuando consume
  `app_operativa_v2/data/operacional`.

## Que Documentar Si Se Cambia Algo

- `documentacion/proceso_scoring_operativo.qmd` si cambia regla, flujo, salida o control.
- `app_operativa/README.md` si cambia forma de ejecucion o variables de entorno.
- `documentacion/HITOS.md` si cambia una decision operativa estable.
- `TAREAS.md` si se abre/cierra trabajo.
- [[datos_y_leakage]] si cambia una regla temporal.

## Riesgos

- Recalcular predicciones historicas sin versionado.
- Publicar predicciones con fuentes incompletas.
- Mover logica de features/modelos a la app.
- Cambiar D-2 o D 01:00 sin documentar impacto en leakage.
- Mezclar emulacion con ruta productiva.

## Pendiente De Confirmar

- Ruta productiva final frente a rutas de emulacion.
- Convencion definitiva de version de modelo operativo.
- Convencion definitiva de version de modelo operativo.
