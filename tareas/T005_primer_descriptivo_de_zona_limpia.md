# T005 - Primer descriptivo de Zona Limpia

Estado: finalizada

Prioridad: alta

Area: zona limpia / analisis exploratorio

Fecha de creacion: 2026-07-01 Fecha de cierre: 2026-07-01

### Contexto

Luego de generar `data/parquet/com_completo/` y definir el
mapeo canonico de etiquetas Zona Limpia, se necesita una primera lectura
agregada para entender composicion, visitas efectivas y tasa de
hallazgo.

### Plan propuesto

- Construir resumen total por categoria canonica.

- Construir resumen mensual por categoria canonica.

- Calcular visitas efectivas como registros limpios o con problema encontrado.

- Calcular hallazgos problematicos usando basura fuera, contenedor desbordado y voluminosos.

- Guardar resultados tabulares en `zona_limpia/outputs/`.

### Criterio de finalizacion

Existen tablas reproducibles con composicion total, composicion
mensual y metricas de tasa de hallazgo de Zona Limpia.

### Notas

Se creo
`zona_limpia/03_analisis_descriptivo_zona_limpia.R`. Las
salidas principales son:

- `zona_limpia/outputs/analisis_descriptivo_resumen_total_categoria.csv`

- `zona_limpia/outputs/analisis_descriptivo_resumen_mensual_categoria.csv`

- `zona_limpia/outputs/analisis_descriptivo_metricas_total.csv`

- `zona_limpia/outputs/analisis_descriptivo_metricas_mensuales.csv`

