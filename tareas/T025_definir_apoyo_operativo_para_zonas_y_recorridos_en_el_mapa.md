# T025 - Definir apoyo operativo para zonas y recorridos en el mapa

Estado: pendiente
Prioridad: alta
Area: app / operativa / optimizacion territorial
Fecha de creacion: 2026-08-20

### Contexto

Una posibilidad es que la persona usuaria observe ambos scores y disene zonas para recorrer. Falta definir la unidad real de trabajo y las restricciones de campo.

### Plan propuesto

1. Relevar como se planifican hoy zonas y recorridos.
2. Identificar equipos, tiempos, capacidad, continuidad y prioridades.
3. Elegir entre seleccion manual, dibujo, agrupacion sugerida o rutas.
4. Prototipar un flujo asistido.
5. Definir guardado, exportacion y evaluacion posterior.
6. Acordar metricas de cobertura, hallazgos, distancia y tiempo.

### Criterio de finalizacion

Existe una decision documentada sobre la accion que soportara la app y un prototipo validado antes de automatizar ruteo.

### Notas

Depende de T024. Un top N de clusters no se considera automaticamente una zona recorrible.

La app ya permite ensayar porcentaje, cantidad fija, total estimado y cupos por
barrio para COM, ademas de reglas propias para ZL. Estas selecciones ayudan a
explorar capacidad y cobertura, pero todavia no resuelven agrupacion en zonas,
continuidad espacial ni ruteo.
