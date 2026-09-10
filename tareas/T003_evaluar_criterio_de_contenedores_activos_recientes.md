# T003 - Evaluar criterio de contenedores activos recientes

Estado: pendiente

Prioridad: media

Area: datos / features / modelo

Fecha de creacion: 2026-06-30

### Contexto

Se observo que en predicciones aparecen clusters con tiempos desde
ultimo levante mayores a 6 o 7 dias. Existe un criterio operativo
alternativo usado por otros equipos: considerar activos solo
contenedores con levante reciente en una ventana fija, por ejemplo 7
dias.

### Plan propuesto

- Documentar claramente la regla actual de elegibilidad y tiempos desde ultimo levante.

- Explorar indicadores como `tuvo_levante_ultimos_7d`.

- Evaluar ventanas de 5, 7 y 10 dias.

- Comparar impacto sobre cantidad de clusters elegibles, reclamos cubiertos y desempeno del modelo.

### Criterio de finalizacion

Queda tomada y documentada una decision sobre si usar solo la regla
actual, agregar indicadores de actividad reciente o filtrar
contenedores/clusters antes del modelado.

### Notas

Por ahora no se cambia el modelo; el tema queda documentado como
posible mejora.

