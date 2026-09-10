# T028 - Pronosticar el volumen diario de clusters con reclamo COM

Estado: en proceso
Prioridad: alta
Area: modelos / COM / series temporales / app
Fecha de creacion: 2026-08-20

## Contexto

El modelo COM actual estima para cada `cluster_id`/`dia` la probabilidad de que
el cluster tenga al menos un reclamo. El negocio necesita tambien anticipar si
el dia sera complicado por la cantidad total de clusters afectados. Esta tarea
queda acotada al desarrollo predictivo, su contrato operativo y su integracion
en la app.

La explicacion inferencial de los apartamientos respecto del patron estructural
se separa en T029. Esa linea no bloquea el cierre predictivo ni la integracion
del pronostico agregado en la app.

## Targets Y Uso

Target principal:

- `n_clusters_con_reclamo = sum(tuvo_reclamo)` por dia.

Resultados secundarios:

- cantidad total de reclamos;
- reclamos adicionales dentro de clusters ya afectados;
- reclamos por cluster afectado;
- indicador de `dia complicado`, cuya definicion operativa sigue pendiente con
  el negocio.

La cantidad de clusters afectados representa extension territorial. El total
de reclamos representa carga administrativa y repeticion. No deben confundirse.

## Decisiones Vigentes

- La validacion es temporal y debe respetar disponibilidad operativa: levantes
  hasta `D 01:00`, COM cerrado hasta `D-2` y ninguna informacion futura.
- A0 es la referencia estructural: fila `segmento/dia`, dia de semana e
  interceptos penalizados anidados de barrio y segmento.
- La suma diaria de scores COM se conserva como baseline, pero fluctua poco y
  no reproduce adecuadamente los shocks diarios.
- E1 se conserva como referencia dinamica anterior.
- El candidato predictivo actual es XGBoost como correccion de A0 mediante
  `base_margin`, con variables operativas, propension historica W7 y diferencia
  `q7 - q60`.
- El indicador de feriado se evalua en la correccion dinamica, no en A0. La
  primera prueba mejora el resultado combinado; postferiado no agrega una
  mejora estable y queda como hipotesis no confirmada.
- La propension usa historia cerrada en `D-2` y shrinkage
  `cluster -> barrio -> global`.
- La evidencia de interacciones en XGBoost es predictiva, no causal.
- No se incorporan aun NBI, CCZ ni municipio en el candidato actual.
- Ningun modelo agregado fue promovido todavia al scoring ni a la app.

## Estado Actual

Se completaron:

- diagnostico de suma de scores;
- modelos barrio/dia y CCZ/dia;
- jerarquia barrio/segmento con calendario y resumenes dinamicos;
- experimentos con exceso de levante, colas altas, propension e interacciones;
- contraste de cargas de atraso ponderadas y no ponderadas;
- pendientes aleatorias por barrio, descartadas en su forma ensayada;
- XGBoost como correccion de A0 con A0 OOF temporal en entrenamiento;
- sensibilidad de propension W7, W15, W30, W60 y W90;
- contraste parsimonioso `q7 - q30` y `q7 - q60`.
- contraste de feriado y postferiado sobre W7 + `q7 - q60`.
- contraste de severidad extrema `top20_h` sobre el candidato con feriado;
  no mejora el resultado combinado ni los picos extremos y queda descartado
  en esta forma.
- contraste de cambio global COM mediante diferencia y ratio de promedios
  diarios 7/60, cerrados en `D-2`; ambas variantes empeoran la generalizacion
  y quedan descartadas.
- evaluacion territorial barrio/dia de A0, X2 y X2 con feriado: X2 mejora A0
  en 53 de 62 barrios y el candidato con feriado tambien supera A0 en 53.
- contraste de propension barrial W7 y cambio W7-W60: W7 barrial mejora test
  pero no el combinado; agregar el cambio barrial sobreajusta y empeora test.
- poda de variables dinamicas: se selecciona la version compacta de cinco
  variables. Obtiene RMSE combinado `156,0`, correlacion `0,691` y reproduce
  `83,0%` de la variabilidad, con mejor test que la especificacion completa.
- prototipo retrospectivo en la app con total estimado, mapa barrial, cupos
  dinamicos COM, seleccion ZL independiente y capas superpuestas. No implica
  promocion operativa del modelo agregado.

La variante W7 + `q7 - q60` + feriado reduce el RMSE combinado de `157,1` a
`155,0` y deja el sesgo combinado practicamente en cero. Agregar postferiado
lleva el RMSE a `156,0`, por lo que no desplaza a la variante con solo feriado.
Las metricas, graficos y resultados por periodo se mantienen exclusivamente en
el informe principal.

## Plan Pendiente

1. Auditar estabilidad temporal y desempeno en dias extremos del candidato.
2. Revisar calibracion, sesgo, amplitud y cobertura de clusters sin historia.
3. Comparar formalmente contra A0, suma de scores y referencias dinamicas.
4. Definir intervalos predictivos y probabilidad de superar el umbral de dia
   complicado.
5. Fijar el contrato operativo: hora de corrida, datos disponibles, salida,
   monitoreo y tratamiento de faltantes.
6. Disenar la tarjeta y serie temporal para la app, sin mezclarla con el ranking
   espacial por cluster.

## Criterio De Finalizacion

La tarea finaliza cuando existan:

1. un pronostico diario validado temporalmente, con baselines, intervalos y
   contrato operativo;
2. una definicion acordada de `dia complicado`;
3. una propuesta validada para mostrar el resultado agregado en la app.

El analisis inferencial queda fuera de este criterio y se gestiona en T029.

## Fuentes Y Navegacion

- Informe, metricas, graficos y registro detallado:
  `documentacion/pronostico_diario_clusters_reclamo_com.qmd`.
- Informe breve para compartir con el equipo:
  `documentacion/resumen_pronostico_diario_com.qmd`.
- Sintesis de modelos para retomar rapidamente:
  `knowledge/wiki/modelos_agregados_com.md`.
- Estado transversal del proyecto: `knowledge/wiki/estado_actual.md`.
- Scripts reproducibles: `scripts/*agregado*_com.R`,
  `scripts/experimentar_*_com.R`, `scripts/explorar_*_com.R`,
  `scripts/probar_*_com.R` y `scripts/comparar_*_com.R`.
- Salidas experimentales: `outputs/` en las carpetas homonimas de cada script.

## Notas Pendientes De Decision

- Umbral operativo y categorias para un dia complicado.
- Criterio minimo para promover el candidato predictivo.
- Tratamiento productivo de clusters sin historia suficiente.
- Forma de incorporar el pronostico agregado en la app.
- Coordinacion futura con T029 para mantener separadas prediccion e inferencia.
