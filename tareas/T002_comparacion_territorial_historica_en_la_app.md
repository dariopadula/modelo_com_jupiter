# T002 - Comparacion territorial historica en la app

Estado: pendiente

Prioridad: alta

Area: app / visualizacion

Fecha de creacion: 2026-06-30

### Contexto

En la vista historica de la app se quiere comparar la seleccion sugerida por el
modelo con los resultados observados. El primer ensayo con tres mapas por
hexagonos resulto pequeno, dificil de interpretar y sin una decision operativa
clara, por lo que se retiro de la interfaz.

### Plan propuesto

- Mantener un mapa categorico legible de seleccion y observados.
- Comparar en una tabla todas las estrategias disponibles para COM o ZL.
- Mostrar cantidad seleccionada, evaluables, observados capturados, precision,
  cobertura y lift.
- Para ZL, calcular precision y lift solo dentro de seleccionados visitados.
- Validar con usuarios si esta lectura cubre la necesidad territorial historica
  o si hace falta otra agregacion.

### Criterio de finalizacion

La app permite elegir un dia historico, comparar estrategias y entender en el
mapa que casos fueron capturados o quedaron fuera, con una lectura validada por
usuarios.

### Notas

Existe un prototipo funcional con tabla comparativa y mapa categorico. La tarea
sigue pendiente hasta validar la lectura con usuarios. No reintroducir los tres
mapas hexagonales sin una nueva justificacion operativa.
