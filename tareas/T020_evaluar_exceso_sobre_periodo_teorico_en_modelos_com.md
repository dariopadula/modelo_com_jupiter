# T020 - Evaluar exceso sobre periodo teorico en modelos COM

Estado: finalizada
Prioridad: media
Area: modelos / COM / features
Fecha de creacion: 2026-07-13
Fecha de cierre: 2026-07-13

### Contexto

Se evalua si resumir cuanto excede el tiempo desde ultimo levante al periodo teorico mejora el ranking COM.

### Plan propuesto

1. Crear funciones compartidas de exceso positivo y truncado.
2. Agregar soporte opcional en modelos COM.
3. Comparar baselines frente a variantes con exceso.
4. Consolidar metricas, lift e importancia.

### Criterio de finalizacion

Existen salidas reproducibles que permiten decidir si incorporar la variable sin cambiar el baseline por defecto.

### Notas

Se agregaron exceso positivo y exceso truncado a siete dias, activables mediante `USAR_EXCESO_LEVANTE`. La mejora de AUC en validacion fue del orden de 0,00003 a 0,00005 y bajo levemente en test. No se promueve al baseline.

