# T016 - Diagnosticar correspondencia territorial entre COM y problemas Zona Limpia

Estado: finalizada
Prioridad: alta
Area: zona limpia / sesgo de reclamo / territorio
Fecha de creacion: 2026-07-03
Fecha de cierre: 2026-07-03

### Contexto

Se necesita medir en que territorios los problemas observados por Zona Limpia se convierten o no en reclamos COM.

### Plan propuesto

1. Usar visitas efectivas y problemas comparables.
2. Excluir Voluminosos y Municipio B por fuente incompleta.
3. Calcular problemas ZL, COM, coincidencias y brechas por territorio.
4. Medir tasas de COM y no COM dado un problema ZL.

### Criterio de finalizacion

Existen salidas reproducibles por municipio, CCZ y barrio sobre la proporcion de problemas observados que tiene COM asociado.

### Notas

Se creo `zona_limpia/11_diagnostico_correspondencia_com_zl_territorio.R`. Excluyendo Municipio B, aproximadamente 10,8% de los problemas comparables ZL tienen COM asociado en el mismo cluster-dia. La correspondencia varia territorialmente y no debe interpretarse sin considerar seleccion y cobertura.

