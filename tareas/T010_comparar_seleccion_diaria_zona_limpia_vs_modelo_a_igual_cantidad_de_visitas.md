# T010 - Comparar seleccion diaria Zona Limpia vs modelo a igual cantidad de visitas

Estado: finalizada

Prioridad: alta

Area: zona limpia / modelos / evaluacion operativa

Fecha de creacion: 2026-07-02 Fecha de cierre: 2026-07-02

### Contexto

Se necesita una comparacion comunicable entre la seleccion efectiva
de puntos visitados por Zona Limpia y una seleccion alternativa sugerida
por el modelo. La comparacion debe ser diaria y usar la misma cantidad
de clusters: si Zona Limpia visito `N` clusters un dia, el
contrafactual del modelo toma los `N` clusters con mayor
riesgo ese mismo dia.

### Plan propuesto

- Usar marzo, abril y mayo de 2026.

- Usar el modelo `logistico_reducido_d2`.

- Definir problema real observado como reclamo COM valido o problema comparable observado por Zona Limpia.

- Excluir `Voluminosos` de la metrica principal.

- Generar metricas diarias con n, tasas, diferencias y solapamiento entre seleccion Zona Limpia y top modelo.

### Criterio de finalizacion

Existe una tabla diaria reproducible, apta para visualizaciones, que
compara la tasa de problemas observados en los clusters visitados por
Zona Limpia contra el top N diario sugerido por el modelo.

### Notas

Se creo
`zona_limpia/06_comparar_seleccion_zl_vs_modelo_diario.R`.
Las salidas son:

- `zona_limpia/outputs/seleccion_zl_vs_modelo_diario_logistico_reducido_d2.csv`

- `zona_limpia/outputs/seleccion_zl_vs_modelo_mensual_logistico_reducido_d2.csv`

La comparacion es conservadora para el modelo porque los problemas
sin reclamo COM solo son observables donde Zona Limpia efectivamente
visito.

Luego se agregaron metricas COM-only al mismo archivo diario y
mensual. Estas columnas evalúan estrictamente la captura de reclamos
COM, separada de la metrica de problema real observado.

