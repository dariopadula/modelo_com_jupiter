# T018 - Descargar variables climaticas INUMET para Zona Limpia

Estado: finalizada
Prioridad: media
Area: datos / clima / zona limpia
Fecha de creacion: 2026-07-13
Fecha de cierre: 2026-07-13

### Contexto

Se requieren variables ex ante de precipitacion y temperatura para explorar mejoras del modelo de problema observado Zona Limpia.

### Plan propuesto

1. Procesar temperatura y precipitacion horaria de Melilla G3.
2. Guardar tablas crudas, horarias y diarias.
3. Crear features disponibles antes del dia objetivo.
4. Documentar cobertura y limitaciones.

### Criterio de finalizacion

Existe una salida diaria reproducible desde 2025-01-01, lista para cruzar por dia y sin usar informacion posterior.

### Notas

Se creo `scripts/descargar_clima_inumet_melilla_g3.R`. La salida `clima_inumet_melilla_g3_features_diarias.csv` usa para predecir D solamente clima hasta D-1 y ventanas cerradas en D-1. La cobertura procesada llega hasta 2026-07-13.

