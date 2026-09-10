# T029 - Explicar los dias con alta afectacion territorial COM

Estado: pendiente
Prioridad: media
Area: modelos / COM / series temporales / inferencia
Fecha de creacion: 2026-08-28

## Contexto

T028 desarrolla un modelo predictivo para anticipar cuantos clusters tendran al
menos un reclamo COM. En paralelo existe interes en entender que factores se
asocian con los apartamientos respecto del patron estructural y con los dias de
alta afectacion territorial.

Esta linea se separa para evitar que la integracion operativa del pronostico en
la app quede bloqueada por un trabajo inferencial de alcance diferente. Los
resultados predictivos y sus interacciones no deben interpretarse como evidencia
causal.

## Plan Propuesto

1. Definir un conjunto parsimonioso de variables interpretables, independiente
   de las features opacas o compuestas del modelo predictivo.
2. Separar estructura, shock operativo de levante y sensibilidad territorial.
3. Estudiar dias extremos y diagnosticos temporales con modelos de conteo o GAM.
4. Distinguir asociaciones con extension territorial de las asociadas con total
   de reclamos o repeticion.
5. Documentar limites de identificacion y evitar lenguaje causal sin un diseno
   que lo sostenga.

## Criterio De Finalizacion

La tarea finaliza cuando exista un analisis reproducible e interpretable de los
dias con alta afectacion territorial, con variables y alcance definidos,
diagnosticos temporales y limites de identificacion documentados.

## Notas Y Decisiones Pendientes

- Definir las variables y el alcance definitivos del modelo inferencial.
- Acordar si `dia complicado` se usa como resultado operativo de T028, como
  objeto de explicacion en esta tarea o con ambas funciones diferenciadas.
- Mantener separadas extension territorial, total de reclamos y repeticion.

## Fuentes Y Navegacion

- Tarea predictiva relacionada:
  `tareas/T028_pronosticar_y_explicar_volumen_diario_reclamos_com.md`.
- Informe principal:
  `documentacion/pronostico_diario_clusters_reclamo_com.qmd`.
- Sintesis de modelos: `knowledge/wiki/modelos_agregados_com.md`.
