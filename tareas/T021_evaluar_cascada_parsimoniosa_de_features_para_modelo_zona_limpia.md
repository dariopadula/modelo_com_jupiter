# T021 - Evaluar cascada parsimoniosa de features para modelo Zona Limpia

Estado: finalizada
Prioridad: alta
Area: zona limpia / modelos / features
Fecha de creacion: 2026-07-13
Fecha de cierre: 2026-07-13

### Contexto

El modelo ZL amplio combina muchas capas territoriales y puede capturar seleccion o cobertura. Se necesita comparar alternativas mas parsimoniosas.

### Plan propuesto

1. Mantener target y universo fijos.
2. Comparar operativo minimo, operativo segmento, operativo clima, segmento clima y amplio actual.
3. Usar los mismos splits aleatorios, por dia y temporales.
4. Consolidar metricas, lift, cantidad de columnas e importancia.

### Criterio de finalizacion

Existe una comparacion reproducible que permite seleccionar un candidato ZL controlado.

### Notas

`operativo_segmento` quedo como candidato parsimonioso: usa 36 columnas, evita municipio/CCZ/barrio nominal y supera levemente a `amplio_actual` en AUC temporal de test, 0,601 frente a 0,599. `amplio_actual` queda como diagnostico territorial.

