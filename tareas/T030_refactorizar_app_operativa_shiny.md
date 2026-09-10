# T030 - Refactorizar la app operativa Shiny

Estado: en proceso
Prioridad: alta
Area: app / diseno operativo / scoring
Fecha de creacion: 2026-08-31

### Contexto

La app vigente integra predicciones COM y ZL, mapas, estrategias de seleccion,
observados y diagnosticos, pero mezcla tres propositos: tomar decisiones para el
ultimo dia operativo, explorar estrategias y evaluar retrospectivamente los
modelos. Los ajustes visuales incrementales no resolvieron esa mezcla y se
decidio detener los parches para hacer un refactor planificado.

La app actual funciona y debe conservarse como referencia tecnica y funcional.
La nueva version reutilizara solamente la carga, funciones y calculos que se
validen como necesarios.

Para todo trabajo Shiny se debe leer y seguir `skills/shiny_skill.md`, segun la
regla agregada a `AGENTS.md`.

### Decisiones acordadas

- Congelar la app vigente como version de referencia antes de refactorizar.
- Definir por escrito las preguntas que responde cada pestana.
- Acordar tarjetas, controles y visualizaciones antes de escribir codigo.
- Definir el contrato de datos requerido por la nueva app.
- Preparar wireframes sin logica y validarlos con el usuario.
- Implementar recien despues de validar el diseno funcional.
- Comparar ambas versiones antes de reemplazar la app actual.
- Mantener la app como consumidora de salidas calculadas; no mover features ni
  modelos a Shiny.

### Definicion funcional inicial

La estructura propuesta tiene tres espacios:

1. `Operacion del dia`: orientada a quien toma decisiones para el ultimo dia
   con predicciones. Debe mostrar fecha y actualizacion, clusters evaluados,
   clusters seleccionados, clusters con reclamo esperados, mapa operativo y
   lista priorizada. No debe mostrar observados del dia ni metricas
   retrospectivas.
2. `Historico`: orientada a evaluar fechas cerradas. Debe comparar estimados y
   observados, incluir una serie temporal y permitir analizar desempeno y error
   territorial con una visualizacion aun por definir.
3. `Diagnostico`: espacio secundario para distribucion de scores, umbrales,
   estrategias, versiones, frescura y controles tecnicos.

La separacion exacta entre COM y Zona Limpia todavia debe discutirse. No se debe
presentar ambos targets como si midieran lo mismo.

### Plan propuesto

1. Crear una copia identificada e inmutable de la app vigente como referencia.
2. Cerrar usuarios, decisiones y preguntas de cada pestana.
3. Resolver la diferencia conceptual entre `clusters con reclamo esperados` y
   `total de reclamos esperados`; el candidato agregado actual representa la
   primera cantidad.
4. Acordar indicadores, controles y visualizaciones de `Operacion del dia`.
5. Definir preguntas y visualizaciones de `Historico`, especialmente la lectura
   territorial.
6. Definir el lugar de COM y ZL en la experiencia operativa.
7. Especificar el contrato de datos y estados pendiente/cerrado.
8. Preparar y validar wireframes.
9. Disenar una arquitectura Shiny modular con `NS()` y `moduleServer()`, UI y
   server separados, componentes `bslib` y pruebas reproducibles.
10. Implementar la nueva version y compararla con la referencia.

### Criterio de finalizacion

- Existe una app nueva modular y validada que separa claramente operacion diaria,
  evaluacion historica y diagnostico tecnico.
- La pantalla operativa no muestra observados de un dia aun no cerrado.
- Las cantidades estimadas y observadas tienen nombres y fuentes inequivocas.
- El contrato de datos esta documentado y la app sigue siendo de solo lectura.
- La nueva version fue comparada con la referencia y aprobada antes del reemplazo.

### Punto de retomada

Retomar por la revision visual completa de Historico. En Evolucion temporal,
verificar la lectura de los puntos que marcan los lunes. En Evaluacion del dia
COM, revisar sincronizacion, escala comun, capas de puntos y tabla de ocho
estrategias. En Evaluacion del dia ZL, revisar contraste y leyenda de los cinco
estados combinados de seleccion, visita y problema, junto con la tabla de cinco
estrategias. Luego definir metricas territoriales adicionales y la lectura
barrial de la serie. La app de referencia se conserva; T030 sigue en proceso.

### Avance 2026-09-01

Se crea `app_operativa_v2/` sin modificar `app_operativa/`, que queda como
referencia funcional. La primera version implementa `Operacion del dia` con:

- ultimo dia con predicciones seleccionado automaticamente;
- resumen del dia cerrado por defecto;
- mapa Leaflet como vista principal;
- controles COM y ZL plegables con sus logicas de seleccion separadas;
- capas COM y ZL independientes y superpuestas;
- capa adicional de estimacion COM por barrio;
- lista de clusters en una subpestana separada;
- carga Arrow limitada al ultimo dia para no materializar todo el historico.

La prueba `app_operativa_v2/tests/test_app.R` finaliza con `SESSION_OK`. La
interfaz fue validada visualmente en navegador: COM, ZL y estimacion barrial se
pueden prender y apagar de forma independiente.

### Avance 2026-09-01 - seleccion por umbral

Se incorpora el criterio `Umbral de score` a los controles de COM y Zona
Limpia. El mismo valor gobierna la seleccion que consumen el mapa y la lista.

Se agrega la subpestana `Scores y umbrales`, con selector para analizar COM o
Zona Limpia por separado. Incluye:

- histograma de la distribucion de scores, con el umbral marcado y los tramos
  seleccionados diferenciados;
- curva decreciente de cantidad de clusters seleccionados segun el umbral;
- cantidad y porcentaje seleccionados para el umbral vigente;
- indicacion explicita de si el umbral es el criterio de seleccion activo o
  solo una referencia.

La prueba automatizada cubre ademas la seleccion COM por umbral y conserva el
resultado `SESSION_OK`.

### Avance 2026-09-01 - contrato historico liviano

Se implementa `scripts/construir_tablas_historicas_app_v2.R` y se publican dos
salidas aisladas en `data/processed/app_operativa_v2_historico/`:

- `serie_historica_com`: 26.280 filas con estimado y observado para Montevideo
  y barrios;
- `detalle_cluster_dia`: 7.902.058 filas reducidas a las columnas necesarias y
  particionadas por `dia_objetivo/modelo_id`.

El detalle ocupa aproximadamente 170,44 MB, frente a 242 MB de la fuente larga,
y no se carga completo: la app debera materializar solo la fecha y el modelo
consultados. Barrio y coordenadas se resolveran contra el maestro territorial
para no repetir atributos estables en millones de filas.

El contrato queda en `documentacion/contrato_datos_app_operativa_v2.qmd`. La
prueba `app_operativa_v2/tests/test_datos_historicos.R` finaliza con
`HISTORICO_OK`. Las tablas aun no estan conectadas a la interfaz.

El siguiente paso es revisar esta primera version con el usuario y ajustar el
diseno funcional de Historico antes de conectarlo a estas salidas.

### Definicion preliminar de Historico al cierre 2026-09-01

Se acuerda explorar dos espacios, todavia sin wireframe ni implementacion:

1. Una vista de serie temporal para comparar clusters con reclamo estimados y
   observados, con seleccion de periodo. Debe incluir el total de Montevideo y
   alguna lectura por barrio aun por definir.
2. Una vista de detalle para un dia cerrado. Debe permitir seleccionar clusters
   con los mismos metodos de `Operacion del dia`, verlos territorialmente y
   disponer de una subpestana de metricas para comparar los metodos de
   seleccion.

Antes de implementar falta acordar:

- como elegir y comparar barrios sin saturar la serie;
- que metricas mostrar y con que denominadores;
- si COM y Zona Limpia participan en esta primera version historica;
- el wireframe y la jerarquia entre serie, mapa y comparacion de estrategias.
### Avance 2026-09-02 - evolucion temporal

Se implementa `Historico > Evolucion temporal` para Montevideo con la serie
agregada P3_compacto, filtrada a validacion y test antes de collect(). No carga
el detalle por cluster ni muestra entrenamiento.

El periodo controla el grafico estimado/observado y la primera columna de
metricas. La segunda conserva toda la evaluacion. Se muestran fechas, dias
evaluados, correlacion, R2 predictivo, RMSE y MAE. R2 usa 1 - SSE/SST con la
media observada de cada periodo, puede ser negativo y no es correlacion al
cuadrado. Los casos no calculables se indican explicitamente.

Pruebas: `test_evolucion.R` (`EVOLUCION_OK`) y `test_app.R` (`SESSION_OK`).
Pendiente la revision visual con el usuario. No se implementaron barrios ni
el mapa historico.

La serie marca con puntos los valores observados y estimados de cada lunes para
facilitar la lectura del comienzo de semana; los demas dias conservan solo las
lineas.
### Avance 2026-09-02 - distribucion territorial COM

Se implementa Evaluacion del dia COM con dos mapas de hexagonos sincronizados,
misma grilla y escala, porcentaje del total seleccionado frente al porcentaje
del total observado. No se exige coincidencia por cluster para esta lectura.
Los controles reutilizan los criterios COM operativos. Solo se materializa el
dia consultado; se valida cierre, version territorial y cobertura espacial.
La grilla usa el maestro territorial y anchos 500/1000/2000 m.
Pendientes: revision visual de mapas y sincronizacion, y definicion de la tabla
comparativa de metricas (no incluida en esta entrega territorial).

### Cierre de sesion 2026-09-02

- Evolucion temporal: Montevideo, validacion y test, periodo seleccionable,
  correlacion, R2 predictivo, RMSE y MAE contra toda la evaluacion.
- Evaluacion diaria COM: ocho criterios operativos; distribuciones porcentuales
  por hexagono con denominadores independientes y escala comun. No mide acierto
  punto a punto ni presenta seleccionados como un pronostico de cantidad.
- Pruebas ejecutadas durante la implementacion: EVOLUCION_OK, SESSION_OK y
  DIA_COM_OK. Esta ultima cubre los ocho criterios, sumas al 100 %, conteos y
  seleccion vacia. HISTORICO_OK corresponde a la validacion previa de tablas.
- No se realizo la validacion visual de las vistas nuevas ni de la
  sincronizacion en navegador. No declarar el refactor terminado.
- No se modificaron modelos ni se regeneraron tablas durante este cierre.

Para ejecutar desde la raiz: `shiny::runApp("app_operativa_v2")`.
Pruebas desde `app_operativa_v2/tests`: `test_app.R`, `test_evolucion.R`,
`test_dia_com.R` y `test_datos_historicos.R`, cada una en un proceso R separado.

### Avance 2026-09-08 - puntos y comparacion de estrategias

Evaluacion del dia COM incorpora controles independientes para superponer puntos
seleccionados y observados en sus respectivos mapas. Debajo aparece la tabla de
los ocho criterios, incluido umbral, con parametro, seleccionados, evaluables,
observados capturados, precision, cobertura y lift. Usa las mismas funciones y
parametros que la seleccion activa; la comparacion mide coincidencia por cluster.
Los hexagonos conservan su lectura de distribucion territorial.

Validacion: DIA_COM_OK y SESSION_OK. Se comprobaron los ocho criterios contra
la seleccion activa y el caso de seleccion vacia. La revision visual general de
Historico sigue pendiente, al igual que la lectura barrial y la definicion de
metricas territoriales adicionales. T030 permanece en proceso.

El resumen de Evaluacion del dia COM muestra tambien el total estimado de
clusters con reclamo, junto con evaluados, seleccionados y observados. El valor
proviene del pronostico agregado de Montevideo usado por el criterio de total
sugerido y se presenta redondeado como cantidad de clusters.

### Avance 2026-09-08 - Evaluacion del dia ZL

Historico incorpora una vista diaria ZL con un unico mapa de los puntos
seleccionados por el modelo. Usa capas superpuestas: aro gris exterior para
seleccion, aro verde interior para visita efectiva y punto naranja para problema
observado. Asi representa tres combinaciones: seleccionado sin visita,
seleccionado y visitado sin problema, y seleccionado, visitado y con problema.
La leyenda incluye las tres referencias completas con estilos embebidos.
Para aumentar el contraste, el aro exterior queda mas grande, oscuro y
discontinuo; el aro de visita es continuo y tiene relleno verde tenue.
El resumen agrega el porcentaje de visitados que registraron problema como
referencia de prevalencia para interpretar precision y lift.
Tambien se muestran las visitas no seleccionadas: aro azul solo cuando no hubo
problema y aro azul con punto naranja cuando hubo problema. El resumen informa
cuantos visitados quedaron fuera de la seleccion activa.

La tabla compara los cinco criterios ZL y separa seleccionados sin visita,
seleccionados visitados y problemas capturados. Precision y lift se calculan
solo entre seleccionados con visita efectiva; cobertura usa todos los problemas
observados del dia. Validacion: DIA_ZL_OK, DIA_COM_OK y SESSION_OK. La revision
visual en navegador queda pendiente y T030 permanece en proceso.

### Avance 2026-09-10 - cierre D-2 consistente en COM y ZL

La reserva de validacion de la salida historica cambia de siete a dos dias, en
linea con el rezago operativo COM `D-2`. Evaluacion del dia ZL pasa a filtrar
tambien `estado_periodo_app == "historico_cerrado"`, por lo que deja de ofrecer
fechas pendientes. Con la publicacion que termina el 2026-05-24, ambos selectores
deben llegar hasta el 2026-05-22.

### Avance 2026-09-10 - app v2 independiente de la version anterior

Las seis utilidades que la v2 utilizaba desde `app_operativa/R/datos_app.R`
pasan a `app_operativa_v2/R/datos_app.R`. `app.R` carga solamente codigo local
de la v2 y deja de depender de la carpeta de la app anterior. No se copiaron
funciones antiguas sin consumidores en la nueva interfaz.

### Avance 2026-09-10 - datos de ejecucion dentro de la app v2

Los datos especificos de ejecucion pasan a rutas canonicas dentro de
`app_operativa_v2/data/`: `operacional/`, `historico/` y `referencia/`. Los
generadores de predicciones, historico y maestro territorial publican
directamente alli. Se movieron las publicaciones existentes de operacional e
historico, sin conservar las carpetas anteriores bajo `data/processed/`.

La app obtiene los agregados diarios y barriales desde la serie historica
interna, por lo que no fue necesario copiar CSV experimentales de otros
procesos. El maestro territorial se redujo a las columnas necesarias para la
app. El shape de barrios se copia en `data/referencia/` porque no se genera en
el proyecto.

Validacion posterior al cambio: `SESSION_OK`, `HISTORICO_OK`, `DIA_COM_OK`,
`DIA_ZL_OK` y `EVOLUCION_OK`. No se recalcularon modelos ni predicciones.
