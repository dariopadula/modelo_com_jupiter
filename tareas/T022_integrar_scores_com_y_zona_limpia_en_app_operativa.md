# T022 - Integrar scores COM y Zona Limpia en app operativa

Estado: finalizada
Prioridad: alta
Area: app / scoring operativo / zona limpia
Fecha de creacion: 2026-07-13
Fecha de cierre: 2026-07-13

### Contexto

La app necesita mostrar dos lecturas distintas sin recalcular modelos: riesgo de reclamo COM y riesgo exploratorio de problema observado ZL.

### Plan propuesto

1. Crear una salida historica larga multi-modelo.
2. Integrar `com_reclamo` y `zl_problema`.
3. Adaptar Predicciones, Mapa e Historico.
4. Mantener la app como solo lectura.
5. Evitar mezcla de targets y modelos.

### Criterio de finalizacion

La app cambia entre ambos scores sin mezclar filas ni observados.

### Notas

Se creo `scripts/construir_app_modelos_largo_historico.R` y `data/processed/app_modelos_largo/`. Cada modelo contiene 509 dias y 3.951.029 filas entre 2025-01-01 y 2026-05-24. La prueba `app_operativa/tests/test_app.R` termino en `SESSION_OK`. Se agrego la capa de mapa Cruce COM/ZL.

