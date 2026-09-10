# T011 - Reporte visual Zona Limpia vs modelo

Estado: finalizada

Prioridad: alta

Area: zona limpia / visualizacion / comunicacion

Fecha de creacion: 2026-07-02 Fecha de cierre: 2026-07-02

### Contexto

Luego de construir la comparacion diaria a igual N, se necesita una
pieza visual para comunicar que Zona Limpia y el modelo optimizan
objetivos distintos: problemas observados en campo frente a reclamos
COM.

### Plan propuesto

- Crear un reporte Quarto con lectura narrativa.

- Mostrar tasas diarias por objetivo.

- Comparar tasas mensuales agregadas.

- Mostrar diferencias diarias modelo menos Zona Limpia.

- Visualizar la tension entre objetivo de problema real observado y objetivo COM.

- Mostrar el solapamiento entre visitas efectivas de Zona Limpia y top N del modelo.

### Criterio de finalizacion

Existe un `.qmd` reproducible que consume las salidas
diarias/mensuales y genera visualizaciones listas para comunicar el
resultado.

### Notas

Se creo
`zona_limpia/07_visualizar_seleccion_zl_vs_modelo.qmd`. En
esta maquina `quarto` no esta disponible en el PATH, por lo
que no se renderizo el HTML desde consola.

