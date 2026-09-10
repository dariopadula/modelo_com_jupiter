# T027 - Fortalecer pruebas, contratos y monitoreo operativo

Estado: pendiente
Prioridad: media
Area: calidad / datos / scoring / app
Fecha de creacion: 2026-08-20

### Contexto

Existen validaciones puntuales, pero no una suite central para todo el pipeline multi-modelo.

### Plan propuesto

1. Inventariar validaciones y brechas.
2. Controlar claves, esquemas, fechas y frescura.
3. Verificar correspondencia entre modelo, target y version.
4. Probar cortes D 01:00, D-1 y D-2.
5. Monitorear cobertura, drift, calibracion y desempeno territorial.
6. Evaluar reproducibilidad de dependencias R.

### Criterio de finalizacion

Existe una suite minima que detecta contratos rotos, falta de frescura, leakage y mezcla de modelos antes de publicar.

### Notas

Implementar por etapas, priorizando controles que eviten publicaciones incorrectas.

