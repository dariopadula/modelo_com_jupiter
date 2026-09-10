# T014 - Evaluar criterio de levante en seleccion Zona Limpia

Estado: finalizada
Prioridad: alta
Area: zona limpia / features / operativa
Fecha de creacion: 2026-07-03
Fecha de cierre: 2026-07-03

### Contexto

Existe la hipotesis de que la seleccion de Zona Limpia usa, directa o indirectamente, un criterio asociado al atraso respecto al periodo teorico de levante.

### Plan propuesto

1. Construir variables de exceso entre tiempo desde ultimo levante y periodo teorico.
2. Truncar el exceso en cero y limitar extremos a siete dias.
3. Comparar visita, problema observado y COM por bins y deciles.
4. Revisar diferencias por municipio y CCZ.

### Criterio de finalizacion

Existe un diagnostico reproducible que indica si las visitas efectivas se asocian con atraso sobre el periodo teorico de levante.

### Notas

Se creo `zona_limpia/09_diagnostico_criterio_levante_zl.R`. Los cluster-dias visitados muestran mayor tiempo desde ultimo levante, ratio tiempo/periodo y exceso positivo. La tasa de visita crece con excesos moderados, especialmente entre cero y tres dias, pero no linealmente en los extremos. Las variables se incorporaron luego al baseline ZL y se evaluaron por separado en COM mediante T020.

