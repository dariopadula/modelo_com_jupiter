# T023 - Evaluar territorialmente el modelo COM por CCZ

Estado: finalizada
Prioridad: alta
Area: modelos / COM / territorio / evaluacion
Fecha de creacion: 2026-07-16
Fecha de cierre: 2026-07-16

### Contexto

Se necesita auditar discriminacion, calibracion y utilidad operativa del modelo COM global entre CCZ sin entrenar modelos territoriales ni usar CCZ como predictor.

### Plan propuesto

1. Reconstruir predicciones del logistico reducido D-2 sin reentrenar.
2. Cruzar con la capa administrativa versionada.
3. Calcular metricas, calibracion, volumen y estabilidad por CCZ.
4. Separar ranking global y ranking local.
5. Incorporar incertidumbre mediante remuestreo temporal.

### Criterio de finalizacion

Existe un diagnostico reproducible de validacion y test para los 18 CCZ, sin modificar entrenamiento ni scoring.

### Notas

Se creo `scripts/diagnostico_territorial_modelo_com_ccz.R`. La evaluacion cubre los 18 CCZ, reproduce las metricas globales y usa 1.000 remuestreos de dias. Los resultados estan en `documentacion/analisis_territorial_pred.qmd`.

