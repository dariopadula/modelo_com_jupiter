# T029 - Explicar los dias con alta afectacion territorial COM

Estado: en proceso
Prioridad: media
Area: modelos / COM / series temporales / inferencia
Fecha de creacion: 2026-08-28

## Contexto

T028 desarrolla un modelo predictivo para anticipar cuantos clusters tendran al
menos un reclamo COM. En paralelo existe interes en entender que factores se
asocian con los apartamientos respecto del patron estructural y con los dias de
alta afectacion territorial.

Esta linea se separa para evitar que la integracion operativa del pronostico en
la app quede bloqueada por un trabajo inferencial de alcance diferente. Los
resultados predictivos y sus interacciones no deben interpretarse como evidencia
causal.

## Plan Propuesto

1. Definir un conjunto parsimonioso de variables interpretables, independiente
   de las features opacas o compuestas del modelo predictivo.
2. Separar estructura, shock operativo de levante y sensibilidad territorial.
3. Estudiar dias extremos y diagnosticos temporales con modelos de conteo o GAM.
4. Distinguir asociaciones con extension territorial de las asociadas con total
   de reclamos o repeticion.
5. Documentar limites de identificacion y evitar lenguaje causal sin un diseno
   que lo sostenga.

## Criterio De Finalizacion

La tarea finaliza cuando exista un analisis reproducible e interpretable de los
dias con alta afectacion territorial, con variables y alcance definidos,
diagnosticos temporales y limites de identificacion documentados.

## Notas Y Decisiones Pendientes

- La especificacion inferencial de referencia queda fijada en el avance del
  2026-09-14. Cualquier extension debe compararse contra esa referencia antes
  de repetir el bootstrap.
- Acordar si `dia complicado` se usa como resultado operativo de T028, como
  objeto de explicacion en esta tarea o con ambas funciones diferenciadas.
- Mantener separadas extension territorial, total de reclamos y repeticion.
- Explorar si lluvia, temperatura y viento explican shocks diarios residuales.
  Para inferencia retrospectiva puede usarse clima observado; para una eventual
  aplicacion predictiva solo corresponde informacion disponible al puntuar.
  El ensayo previo de clima `D-1` en XGBoost COM a nivel cluster/dia no mostro
  mejora, pero no responde esta pregunta sobre la variacion diaria agregada.

## Avance 2026-09-14 - cascada inferencial segmento/dia

Se descarta `ciudad/dia` como escala principal luego de una prueba rapida: los
modelos agregados capturan parte de la amplitud, pero pierden composicion
territorial y quedan por debajo de A0 y del XGBoost desagregado fuera de muestra.

Se implementa una primera cascada binomial con `mgcv::bam()` a nivel
`segmento/dia`. El target sigue siendo la cantidad de clusters con al menos un
reclamo dentro de los clusters evaluables del segmento. La estructura incluye
dia de semana, feriado, log de densidad poblacional, porcentaje de NBI y efectos
penalizados de barrio y segmento.

Etapas evaluadas:

1. `I0_estructura`: estructura territorial y calendario;
2. `I1_operacion`: agrega exceso medio sobre periodo teorico;
3. `I2_historia`: agrega propension historica a 60 dias y cambio `q7 - q60`;
4. `I3_sensibilidad`: agrega atraso por propension historica;
5. `I4_calendario`: agrega pendientes del atraso por dia de semana y feriado.

Resultados diarios combinados de validacion y test:

| Escenario | RMSE | Correlacion | R2 predictivo |
|---|---:|---:|---:|
| I0 estructura | 174,3 | 0,585 | 0,324 |
| I1 operacion | 161,4 | 0,658 | 0,420 |
| I2 historia | 156,5 | 0,688 | 0,455 |
| I3 sensibilidad | 158,0 | 0,687 | 0,444 |
| I4 calendario | 155,2 | 0,696 | 0,464 |
| XGBoost de referencia | 156,0 | 0,691 | 0,458 |

`I4_calendario` mejora validacion frente al XGBoost, pero no test: RMSE 138,7
en validacion y 179,4 en test, contra 146,3 y 171,0 del XGBoost. La interaccion
atraso por propension no aporta estabilidad por si sola. La interaccion atraso
por feriado es practicamente nula en la especificacion completa.

Los signos de densidad, NBI, atraso e historia son estables entre etapas, pero
los errores estandar ordinarios no son aun inferencia final. La dispersion de
Pearson queda cerca de 1,20 en I4 y los errores diarios conservan autocorrelacion,
especialmente en entrenamiento y test. Antes de interpretar efectos se requiere
incertidumbre por bloques temporales y analisis de sensibilidad.

Implementacion y salidas:

- `scripts/experimentar_modelo_inferencial_segmento_com.R`;
- `outputs/modelo_inferencial_segmento_com/`.

## Avance 2026-09-14 - diagnostico temporal y bootstrap piloto

Se explora la diferencia entre validacion y test en cuatro pasos reproducibles:

1. comparacion diaria, mensual y por condiciones de los errores de `I2`, `I4` y
   XGBoost;
2. evaluacion mensual con origen expansivo para `I2` e `I4`;
3. seguimiento de los coeficientes al incorporar cada nuevo mes;
4. bootstrap piloto de 50 replicas, remuestreando las 40 semanas completas del
   entrenamiento y conservando juntos todos los dias y segmentos de cada bloque.

La diferencia entre validacion y test se concentra temporalmente. Febrero es
muy favorable a los `bam()` (`RMSE` cercano a 62 frente a 98 de XGBoost), marzo
queda mas parejo, abril es dificil para los tres modelos (`RMSE` cercano a 190)
y mayo favorece a XGBoost (`RMSE` 144 frente a 163-164). La actualizacion
mensual de `I2` e `I4` no corrige abril y mejora poco mayo. Esto no prueba la
causa, pero hace menos plausible que la brecha se deba solamente a mantener
congelados los coeficientes estimados hasta diciembre.

Los coeficientes son estables en los cinco origenes expansivos. En particular,
`media_q_60` permanece cerca de 0,51; densidad entre 0,18 y 0,20; NBI entre
-0,11 y -0,12. La interaccion entre atraso y feriado es inestable y se mueve
aproximadamente entre 0 y -0,03.

Las 50 replicas del bootstrap convergen. Para `I4`, los intervalos percentiles
piloto son:

| Termino | Estimacion original | Percentil 2,5% | Percentil 97,5% | Razon EE bootstrap / convencional |
|---|---:|---:|---:|---:|
| `media_h` | 0,117 | 0,069 | 0,171 | 3,73 |
| `media_q_60` | 0,508 | 0,442 | 0,570 | 6,76 |
| `delta_q_7_60` | 0,242 | 0,198 | 0,280 | 7,22 |
| `media_h:media_q_60` | -0,077 | -0,088 | -0,065 | 2,68 |
| `media_h:feriado` | 0,005 | -0,113 | 0,116 | 6,33 |

La interaccion de `media_h` con lunes tambien incluye cero en el piloto; las
interacciones con los otros dias conservan signo positivo. Los intervalos son
solo diagnosticos porque 50 replicas dan percentiles extremos poco estables.

El bootstrap semanal no resuelve la incertidumbre territorial de densidad y
NBI: como esas variables son constantes por segmento, remuestrear semanas no
altera su composicion territorial. Sus intervalos requieren mas adelante un
remuestreo por segmentos o unidades territoriales. Por lo tanto, la menor
dispersion semanal observada para esos coeficientes no se interpreta como mayor
precision inferencial.

Implementacion y salidas:

- `scripts/diagnosticar_cambio_temporal_inferencia_com.R`;
- `outputs/modelo_inferencial_segmento_com/diagnostico_temporal/`;
- `documentacion/informe_diagnostico_temporal_modelo_inferencial_com.qmd`.

## Avance 2026-09-14 - modelo final y bootstrap conjunto

Antes de fijar el modelo se comparan interacciones alternativas y suavizados
penalizados. La interaccion `media_h:media_q_7` queda por debajo de la version
con `media_q_60`. La interaccion `media_h:delta_q_7_60` mejora ligeramente
validacion y test y tiene una interpretacion mas directa. Los suavizados
encuentran curvatura dentro del entrenamiento, pero no producen una mejora
estable fuera de muestra. Se mantienen por tanto efectos continuos lineales.

El modelo final conserva:

- dia de semana y feriado;
- log de densidad y porcentaje de NBI;
- atraso medio, propension a 60 dias y cambio `q_7-q_60`;
- interaccion entre atraso y cambio reciente;
- interacciones entre atraso y dia de semana;
- efectos penalizados de barrio y segmento.

Se elimina la interaccion atraso por feriado. El RMSE diario final es 137,22 en
validacion, 178,01 en test y 153,79 en el periodo combinado. La simplificacion
cambia menos de 0,1 puntos el RMSE combinado respecto del candidato previo.

Con la formula congelada se ejecutan 50 replicas de un bootstrap conjunto. Cada
replica remuestrea con reposicion las 40 semanas completas y los 951 segmentos
completos. Los segmentos repetidos reciben identificadores nuevos para volver a
estimar sus efectos aleatorios. Las 50 replicas convergen.

Resultados seleccionados:

| Termino | Estimacion | Percentil 2,5% | Percentil 97,5% | Mismo signo |
|---|---:|---:|---:|---:|
| Log densidad | 0,195 | 0,107 | 0,253 | 50/50 positivo |
| Porcentaje NBI | -0,114 | -0,151 | -0,049 | 50/50 negativo |
| Atraso medio | 0,108 | 0,053 | 0,190 | 50/50 positivo |
| Propension 60 dias | 0,511 | 0,443 | 0,581 | 50/50 positivo |
| Cambio `q_7-q_60` | 0,242 | 0,196 | 0,279 | 50/50 positivo |
| Atraso por cambio | 0,011 | -0,005 | 0,030 | 43/50 positivo |

Densidad y NBI conservan sus signos al variar simultaneamente semanas y
segmentos. La asociacion negativa de NBI describe reclamos registrados y no se
interpreta como efecto causal sobre la presencia de problemas. La interaccion
atraso por cambio queda en el modelo por la decision predictiva previa y por
jerarquia, pero su intervalo conjunto incluye cero y no se presenta como efecto
inferencial estable.

El remuestreo territorial usa segmentos y conserva los barrios observados. Los
intervalos describen estabilidad ante cambios de composicion dentro de la ciudad
y no generalizacion a barrios nuevos.

Implementacion y salidas:

- `scripts/estimar_modelo_inferencial_final_com.R`;
- `outputs/modelo_inferencial_segmento_com/modelo_final_delta/`;
- `documentacion/informe_diagnostico_temporal_modelo_inferencial_com.qmd`.

## Avance 2026-09-15 - exploracion de clima D-1

Se prueba temperatura, precipitacion y viento de Melilla G3 cerrados en D-1,
sin modificar el modelo final y sin ejecutar bootstrap. Para que la comparacion
sea comun, se conservan solamente dias con 24 observaciones de temperatura y
precipitacion y 12 observaciones de viento en D-1. Quedan 254 dias de
entrenamiento, 89 de validacion y 41 de test; se excluyen respectivamente 20, 1
y 13 dias.

Se comparan cinco modelos sobre esa misma muestra:

| Modelo | RMSE validacion | RMSE test | RMSE combinado |
|---|---:|---:|---:|
| Referencia reestimada | 139,51 | 182,90 | 154,51 |
| Temperatura D-1 | 141,92 | 177,72 | 154,11 |
| Lluvia D-1 | 142,26 | 175,93 | 153,68 |
| Viento D-1 | 140,28 | 170,33 | 150,41 |
| Viento maximo D-1 | 141,39 | 162,66 | 148,43 |
| Clima D-1 completo | 149,99 | 161,51 | 153,72 |
| Clima D-1 con viento maximo | 146,46 | 156,24 | 149,62 |

El bloque completo mejora con fuerza test, pero empeora validacion y presenta
sesgo positivo alto. No se considera estable. Temperatura y lluvia producen
cambios combinados pequenos y tambien empeoran validacion. El viento maximo
D-1 supera al viento medio: empeora 1,88 puntos de RMSE en validacion, mejora
20,23 en test y mejora 6,09 en el periodo combinado frente a la referencia.
La mejora se concentra especialmente en abril; marzo empeora. El suavizado usa
aproximadamente 2,8 grados de libertad y la relacion estimada es decreciente:
mayor maximo de viento D-1 queda asociado con menos reclamos predichos. Este
signo no respalda por ahora la hipotesis de dano seguido por mas reclamos.

Los valores p convencionales no se interpretan porque el clima se repite en
todos los segmentos de un dia. La perdida de 13 de los 54 dias de test por el
criterio de cobertura tambien limita la conclusion. Antes de cualquier
bootstrap se debe revisar la sensibilidad del viento maximo al tratamiento de
dias incompletos y decidir si conviene una forma mas simple o un indicador de
viento fuerte.

Implementacion y salidas:

- `scripts/explorar_clima_d1_modelo_inferencial_com.R`;
- `outputs/modelo_inferencial_segmento_com/exploracion_clima_d1/`.

## Avance 2026-09-15 - q30, ciclo anual y viento D-1

Se reconstruye la base usando solamente q7 y q30, sin heredar el corte de la
comparacion de ventanas hasta q90. Con historia completa en D-2, la base puede
comenzar el 2025-02-01. Se redefine el cambio reciente como `q7-q30` y se usa:

- entrenamiento: 2025-02-01 a 2026-01-31, 365 dias;
- validacion: 2026-02-01 a 2026-03-31, 59 dias;
- test: 2026-04-01 a 2026-05-24, 54 dias.

Se comparan una onda anual seno/coseno, mes calendario y viento maximo D-1. Los
dias sin las 12 mediciones de viento se conservan mediante mediana aprendida en
entrenamiento e indicador de ausencia. Hay 18 dias faltantes en entrenamiento,
1 en validacion y 9 en test.

| Modelo | RMSE validacion | RMSE test | RMSE combinado |
|---|---:|---:|---:|
| q60 final anterior, mismos meses | 113,79 | 178,01 | 148,00 |
| q30 referencia | 111,56 | 179,12 | 147,75 |
| q30 + ciclo armonico | 115,50 | 173,23 | 145,97 |
| q30 + ciclo armonico + viento maximo D-1 | 123,53 | 158,10 | 141,11 |
| q30 + mes | 194,96 | 188,46 | 191,88 |
| q30 + mes + viento maximo D-1 | 203,29 | 178,99 | 192,06 |

q30 conserva el desempeno de q60 y agrega febrero 2025 y enero 2026 al
entrenamiento. El factor mes sobreajusta fuertemente y se descarta. El ciclo
armonico mejora test, pero empeora validacion. Agregar viento maximo vuelve a
mejorar con fuerza test y empeora validacion; la diferencia sigue siendo
temporalmente inestable.

En los 45 dias de test con viento completo, el ciclo armonico tiene RMSE 173,36
y la variante con viento 152,22. En los 9 dias con viento imputado, viento
empeora. Por lo tanto, la mejora no proviene del indicador de ausencia. La
asociacion estimada sigue siendo decreciente aun despues del ciclo anual: los
dias con mayor viento maximo D-1 reciben menos reclamos predichos. La onda anual
simple no explica el signo contraintuitivo.

No se ejecuta bootstrap ni se modifica el modelo final. La prueba tampoco
produce una evaluacion fuera de muestra para enero, porque enero 2026 pasa a
entrenamiento.

Implementacion y salidas:

- `scripts/explorar_q30_estacionalidad_clima_inferencia_com.R`;
- `outputs/modelo_inferencial_segmento_com/exploracion_q30_estacionalidad_clima_d1/`.

## Avance 2026-09-16 - prueba de q7 sola

No se agrega q7 al modelo actual porque `delta_q_7_30` se construye exactamente
como `media_q_7 - media_q_30`: incluir q7, q30 y la diferencia produciria una
dependencia lineal perfecta.

Se prueba en cambio una reparametrizacion sustantivamente distinta: reemplazar
q30, `q7-q30` y la interaccion atraso por cambio reciente por q7 como unico
resumen de propension. Se mantienen calendario, ciclo anual, densidad, NBI,
atraso, atraso por dia de semana y efectos penalizados de barrio y segmento.

En la validacion abril-junio de 2026:

| Modelo | RMSE | MAE | Sesgo | Correlacion | R2 |
|---|---:|---:|---:|---:|---:|
| q30 + cambio q7-q30 | 187,85 | 155,75 | -125,24 | 0,690 | 0,054 |
| q7 sola | 191,00 | 159,94 | -133,59 | 0,710 | 0,022 |

q7 sola sigue mejor los movimientos relativos, pero reproduce peor el nivel.
El RMSE empeora en abril, mayo y junio. Su coeficiente estandarizado tambien es
negativo (`-0,0368`), por lo que el signo no surge solamente de representar la
propension reciente mediante `q7-q30`.

La prueba es exploratoria, sin bootstrap y sin leer el test. q30 mas cambio
reciente se conserva como referencia provisoria.

Implementacion y salidas:

- `scripts/probar_q7_sola_inferencia_reevaluacion_2026.R`;
- `scripts/validar_exploracion_q7_sola_inferencia_2026.R`;
- `outputs/reevaluacion_2026/exploracion_inferencia_q7_sola/`.

## Avance 2026-09-17 - curvatura e interaccion de propension

Se comparan dos extensiones del candidato `q30 + cambio q7-q30`, manteniendo
sin cambios calendario, ciclo anual, territorio, atraso, atraso por cambio,
atraso por dia de semana y efectos penalizados:

- un termino cuadratico para `q7-q30`;
- la interaccion explicita `q30 * (q7-q30)`.

En validacion abril-junio de 2026:

| Modelo | RMSE | MAE | Sesgo | Correlacion | R2 |
|---|---:|---:|---:|---:|---:|
| Referencia lineal | 187,85 | 155,75 | -125,24 | 0,690 | 0,054 |
| Cambio cuadratico | 184,57 | 153,33 | -122,15 | 0,698 | 0,087 |
| Cambio cuadratico sin atraso por cambio | 185,49 | 154,14 | -123,20 | 0,697 | 0,077 |
| q30 por cambio | 183,82 | 152,27 | -120,46 | 0,696 | 0,094 |

Ambas extensiones reducen RMSE en abril, mayo y junio. La interaccion queda
apenas mejor en validacion, mientras el termino cuadratico obtiene mejor AIC
dentro del entrenamiento. Sus predicciones diarias tienen correlacion `0,9999`
y difieren en promedio solo `1,63` clusters. La validacion respalda que falta
alguna forma no lineal, pero no permite atribuir la mejora con claridad a
curvatura o interaccion.

Al retirar solo `atraso * (q7-q30)` del modelo cuadratico, el RMSE queda en
`185,49`: pierde `0,92` puntos frente al cuadratico completo, pero conserva una
mejora de `2,36` frente a la referencia lineal. Mejora abril y junio y empeora
mayo en `0,61` puntos. El coeficiente lineal del cambio queda en `-0,0063` y el
cuadratico en `0,0079`; el minimo estimado se ubica cerca de `q7-q30 = 0,009`.
La simplificacion es viable, aunque la interaccion si aporta una ganancia
predictiva pequena.

## Avance 2026-09-17 - bootstrap del cuadratico completo

Se ejecutan 50 replicas del candidato cuadratico completo. Cada replica
remuestrea con reposicion las 53 semanas de entrenamiento y los 951 segmentos
completos. Los segmentos repetidos reciben identificadores nuevos para volver a
estimar sus efectos penalizados. Las 50 replicas convergen y el test permanece
sellado.

| Termino | Estimacion | EE bootstrap | Percentil 2,5% | Percentil 97,5% | Mismo signo |
|---|---:|---:|---:|---:|---:|
| Log densidad | -0,00174 | 0,00022 | -0,00220 | -0,00140 | 50/50 negativo |
| Porcentaje NBI | 0,00000 | 0,00007 | -0,00006 | 0,00019 | 44/50 positivo |
| Atraso medio | 0,02332 | 0,00266 | 0,02058 | 0,02959 | 50/50 positivo |
| Propension q30 | 0,06179 | 0,00997 | 0,04494 | 0,07877 | 50/50 positivo |
| Cambio lineal q7-q30 | 0,02444 | 0,01469 | -0,00807 | 0,04328 | 45/50 positivo |
| Cambio cuadratico | 0,01589 | 0,00249 | 0,01100 | 0,02022 | 50/50 positivo |
| Atraso por cambio | -0,00583 | 0,00154 | -0,00895 | -0,00378 | 50/50 negativo |

Los errores bootstrap son entre 2,2 y 4,6 veces los convencionales para estos
terminos. La curvatura queda respaldada, mientras el cambio lineal aislado cruza
cero. En atraso medio, el minimo de la curva tiene mediana `-0,026` y percentiles
`[-0,049; 0,006]` en la escala original de `q7-q30`; su ubicacion es menos
estable que la convexidad.

La interaccion atraso por cambio conserva signo negativo en las 50 replicas. En
este candidato no puede describirse como inestable, aunque sigue siendo pequena
y su interpretacion sustantiva requiere cuidado. Densidad queda negativa y
estable, y NBI no se distingue de cero; esto difiere de la especificacion
anterior con q60 y debe considerarse antes de congelar el modelo inferencial.

Implementacion y salidas:

- `scripts/bootstrap_inferencial_delta_cuadratico_2026.R`;
- `scripts/validar_bootstrap_inferencial_delta_cuadratico_2026.R`;
- `outputs/reevaluacion_2026/exploracion_inferencia_curvatura_interaccion_q30_delta/bootstrap_cuadratico_completo/`.

No se promueve ninguna variante, no se ejecuta bootstrap y no se lee el test.

Implementacion y salidas:

- `scripts/explorar_curvatura_interaccion_q30_delta_inferencia_2026.R`;
- `scripts/validar_exploracion_curvatura_interaccion_q30_delta_2026.R`;
- `outputs/reevaluacion_2026/exploracion_inferencia_curvatura_interaccion_q30_delta/`.

## Fuentes Y Navegacion

- Tarea predictiva relacionada:
  `tareas/T028_pronosticar_y_explicar_volumen_diario_reclamos_com.md`.
- Informe principal:
  `documentacion/pronostico_diario_clusters_reclamo_com.qmd`.
- Sintesis de modelos: `knowledge/wiki/modelos_agregados_com.md`.
