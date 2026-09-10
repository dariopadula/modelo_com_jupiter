# T024 - Definir contrato conceptual y visual conjunto COM-Zona Limpia

Estado: pendiente
Prioridad: alta
Area: app / modelos / decision operativa
Fecha de creacion: 2026-08-20

### Contexto

La app permite configurar COM y ZL por separado y tiene un prototipo de capas
superpuestas. Falta validar una representacion conjunta que ayude a decidir sin
mezclar targets ni forzar reglas de seleccion simetricas.

### Plan propuesto

1. Documentar significado y limites de cada score.
2. Definir una matriz COM/ZL con categorias comparables.
3. Explorar visualizaciones de coincidencias y divergencias.
4. Evitar interpretar ausencia de visita ZL como ausencia de problema.
5. Validar la lectura con usuarios del negocio.
6. Decidir si sera ayuda visual o politica formal de priorizacion.

### Criterio de finalizacion

Existe un contrato conceptual y una visualizacion conjunta validados, con decisiones permitidas y no permitidas explicitadas.

### Notas

No sumar probabilidades ni crear un score combinado sin justificacion estadistica y operativa. El modelo ZL sigue exploratorio y Municipio B tiene cobertura incompleta.

El prototipo actual usa puntos rellenos para COM y anillos para ZL, con
estrategias independientes. Esta solucion es evidencia de diseno, no cierre de
la tarea: falta validarla con usuarios y documentar decisiones permitidas.
