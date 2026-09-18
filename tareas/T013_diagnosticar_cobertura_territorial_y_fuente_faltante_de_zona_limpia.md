# T013 - Diagnosticar cobertura territorial de Zona Limpia

Estado: en proceso

Prioridad: alta

Area: zona limpia / calidad de datos / territorio

Fecha de creacion: 2026-07-03

### Contexto

El analisis preliminar mostraba al Municipio B muy subrepresentado y se habia
interpretado que sus registros estaban en otra tabla no integrada.

La auditoria del 2026-09-17 corrigio esa lectura. Los registros de B estan
presentes, pero el campo `municipio` original esta vacio para una proporcion
importante. La asignacion espacial mediante `cluster_id` y
`cluster_admin_territorial` recupera las visitas que muestra la aplicacion.

En particular, el 2026-05-21 la aplicacion muestra 82 clusters visitados en B,
29 de ellos con problema. La actividad intensa y continua comienza el
2026-05-14, aunque existen antecedentes desde el 2025-09-11.

### Plan propuesto

- Usar la asignacion espacial del cluster en todos los resumenes territoriales.
- Recalcular los diagnosticos historicos que excluyeron B por la hipotesis de
  fuente faltante.
- Verificar si el vacio del campo `municipio` afecta otros productos o controles
  de calidad.
- Reevaluar el modelo Zona Limpia si la reincorporacion de B cambia la
  distribucion territorial o temporal.

### Criterio de finalizacion

Todos los diagnosticos territoriales vigentes usan el municipio del cluster,
la cobertura de B queda auditada y se determina si corresponde recalcular los
modelos o resultados historicos que lo excluyeron.

### Avance 2026-09-17

- Se genero `zona_limpia/reportes/14_cobertura_municipal_zona_limpia.qmd`.
- Se documento la diferencia entre municipio informado y municipio espacial.
- Se calcularon visitas y porcentaje de problemas por municipio con unidad
  cluster-dia.
- Resta revisar y, si corresponde, recalcular los analisis historicos que
  excluyeron B.
