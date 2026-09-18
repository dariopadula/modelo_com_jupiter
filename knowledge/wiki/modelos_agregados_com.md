# Modelos Agregados COM

Ver tambien [[modelos_com]], [[datos_y_leakage]] y [[estado_actual]].

## Proposito

Esta nota permite recuperar rapidamente el hilo de T028: que problema se
modela, que familias ya se probaron, cuales fueron las decisiones y donde esta
la evidencia. No reemplaza las fuentes primarias:

- gestion y pendientes: `tareas/T028_pronosticar_y_explicar_volumen_diario_reclamos_com.md`;
- resultados, metricas y graficos: `documentacion/pronostico_diario_clusters_reclamo_com.qmd`.
- resumen para compartir: `documentacion/resumen_pronostico_diario_com.qmd`.
- modelo inferencial y bootstrap:
  `documentacion/informe_diagnostico_temporal_modelo_inferencial_com.qmd`.

## Problema

El target principal es la cantidad diaria de clusters con al menos un reclamo
COM. El total de reclamos es secundario: mide repeticion y carga administrativa,
no extension territorial.

T028 queda acotada al pronostico operativo. El analisis inferencial se gestiona
por separado en T029. El candidato XGBoost puede aprovechar interacciones
complejas para predecir, pero esas
interacciones no se trasladan automaticamente al modelo inferencial ni tienen
interpretacion causal.

## Referencias Vigentes

| Referencia | Unidad | Funcion |
|---|---|---|
| Suma de scores | Ciudad/dia | Baseline natural del modelo COM por cluster; subestima amplitud diaria. |
| A0 | Segmento/dia | Estructura: dia de semana e interceptos penalizados de barrio y segmento. |
| E1 | Segmento/dia | Referencia dinamica anterior: A0, cola alta de scores por barrio y cola alta de exceso por segmento. |
| X2 W7 + `q7 - q60` + feriado | Segmento/dia | Variante predictiva actual: XGBoost corrige el logit de A0 con levante, propension reciente, cambio respecto del nivel habitual y feriado. |

## Evolucion De La Busqueda

1. **Agregacion territorial.** Barrio/dia y CCZ/dia mejoraron la suma de scores,
   pero mostraron inestabilidad temporal.
2. **Jerarquia local.** La unidad segmento/dia con barrio/segmento capturo mejor
   la estructura. A0 quedo como baseline parsimonioso.
3. **Resumenes dinamicos.** Colas altas de score y exceso agregaron variacion;
   E1 quedo como referencia dinamica anterior.
4. **Interacciones lineales.** Exceso, propension y territorio mejoraron ajuste
   interno, pero no generalizaron de forma estable.
5. **Carga ponderada.** Se construyo `q * h(exceso)` y se compararon media, RMS y
   atraso sin ponderar. Hubo senal, pero alta redundancia e inestabilidad.
6. **Pendientes aleatorias.** Las pendientes barriales de atraso sobreajustaron
   y quedaron descartadas en la especificacion probada.
7. **Correccion flexible de A0.** XGBoost con `base_margin` capturo interacciones
   entre estructura, levante y propension sin abandonar la expectativa basal.
8. **Ventanas historicas.** W7 fue la mejor ventana individual entre 7, 15, 30,
   60 y 90 observaciones.
9. **Cambio reciente.** Agregar `q7 - q60` a W7 mejoro validacion y test y quedo
   incorporado en la especificacion compacta seleccionada.
10. **Feriados.** Agregar `es_feriado` a la correccion dinamica bajo el RMSE
    combinado de 157,1 a 155,0. Postferiado no mejoro la variante con feriado.
11. **Severidad extrema.** Agregar la media del top 20 % de `h` por segmento/dia
    llevo el RMSE combinado a 156,6 y empeoro picos altos y bajos. Se descarta
    en esta forma; la feature tuvo uso en XGBoost, pero no generalizo.
12. **Cambio global COM.** La diferencia y el ratio entre promedios diarios de
    clusters con reclamo de 7 y 60 dias, cerrados en D-2, obtuvieron RMSE
    combinado 162,9 y 160,4. Tuvieron gain alto, pero generalizaron peor y se
    descartan.
13. **Evaluacion por barrio.** X2 mejora el RMSE de A0 en 53 de 62 barrios. La
    variante con feriado mejora X2 en 35 barrios y conserva ventaja frente a A0
    en 53. El RMSE mediano por barrio es 5,1 y la correlacion mediana 0,485.
14. **Propension barrial.** Agregar q7 barrial mejora test a RMSE 169,5, pero
    deja RMSE combinado 156,2 frente a 155,0 del candidato. Sumar el cambio
    barrial 7-60 requiere 616 iteraciones y empeora test a 184,1. Ninguna
    variante se selecciona.
15. **Poda.** Se selecciona la version compacta de cinco variables: RMSE
    combinado 156,0, correlacion 0,691 y 83,0% de variabilidad reproducida.
    Reduce las entradas dinamicas de 13 a 5 y mejora test frente a la completa.
16. **Modelo inferencial final.** Se fija una especificacion lineal
    `segmento/dia` con densidad, NBI, atraso, `q60`, `q7 - q60`, atraso por
    cambio reciente y atraso por dia de semana. Se elimina atraso por feriado.
    El RMSE combinado es 153,8. Un bootstrap conjunto de 50 replicas remuestrea
    semanas y segmentos completos: densidad conserva signo positivo y NBI signo
    negativo en 50/50; atraso por cambio incluye cero.

## Lectura Conceptual Actual

El pronostico se entiende en tres capas:

1. **Estructura:** territorio y calendario determinan el patron relativamente
   estable.
2. **Shock:** las condiciones operativas de levante permiten apartarse de ese
   patron.
3. **Sensibilidad:** importa donde se concentra el shock y si la propension
   reciente se aparta del comportamiento habitual.

`q7 - q60` resume esa tercera idea: distingue un territorio habitualmente
reclamador de uno cuya propension aumento recientemente.

Para la reevaluacion con datos hasta septiembre de 2026, `q30 + ciclo anual`
queda como candidato inferencial principal provisorio. Esta decision permite
usar un año completo de entrenamiento; no reemplaza todavia la referencia
anterior ni implica haber abierto el nuevo test.

La capa compartida ya esta construida hasta `2026-09-14`. La tabla
`data/processed/features_compartidas/segmento_dia/` incluye q7, q30, w7, w30,
atraso, ciclo anual, densidad y NBI, con COM cerrado en D-2. No contiene splits
ni clima; estos se definen o unen despues de congelar el diseno temporal.

El diseno temporal ya esta congelado como `reevaluacion_2026_v1`: un año de
train entre abril de 2025 y marzo de 2026, validacion abril-junio de 2026 y test
sellado desde julio hasta el 14 de septiembre de 2026. La seleccion de modelos
se hara solo con validacion.

El paso 5 ya entreno `pronostico_a0`,
`pronostico_a0_xgb_compacto_q30` e `inferencial_q30_ciclo`. La correccion
compacta usa `q7-q30` para alinearse con la historia compartida de 30 dias. Los
hiperparametros quedaron fijos, no hubo bootstrap y no se leyo el test.

En validacion, la correccion compacta reduce el RMSE de A0 de `164,44` a
`149,70` y mejora en abril, mayo y junio. El candidato inferencial logra
correlacion `0,690`, pero su RMSE es `187,85` y su sesgo `-125,24`; se conserva
por su finalidad explicativa y debe juzgarse tambien por la claridad y
estabilidad de sus efectos. El test sigue sellado hasta congelar finalistas.

La prueba de reemplazar q30 y `q7-q30` por q7 sola eleva la correlacion a
`0,710`, pero empeora RMSE a `191,00`, MAE a `159,94` y sesgo a `-133,59`. El
coeficiente de q7 tambien queda negativo. No corresponde agregar q7 junto con
q30 y su diferencia porque existe dependencia lineal exacta. Se conserva q30
mas cambio reciente como referencia provisoria.

Dos extensiones de esa referencia mejoran validacion: agregar el cuadrado de
`q7-q30` reduce el RMSE a `184,57`, y agregar `q30 * (q7-q30)` lo reduce a
`183,82`. Ambas mejoran en abril, mayo y junio, pero sus predicciones tienen
correlacion `0,9999`. Esto sugiere una forma no lineal omitida, sin permitir
distinguir todavia curvatura de interaccion. Ninguna variante fue promovida y
el test permanece sellado.

Retirar `atraso * (q7-q30)` del modelo cuadratico deja RMSE `185,49`: conserva
una mejora de `2,36` frente a la referencia lineal, con una perdida de `0,92`
frente al cuadratico completo. La simplificacion es interpretable, pero la
interaccion retirada aporta una ganancia predictiva pequena.

El bootstrap conjunto de 50 replicas del cuadratico completo respalda la
convexidad: el cuadrado de `q7-q30` es positivo en 50/50 y tiene intervalo
`[0,0110; 0,0202]`. El cambio lineal cruza cero. `Atraso * cambio` es negativo en
50/50 (`[-0,0090; -0,0038]`), por lo que en esta especificacion no aparece como
inestable. Densidad queda negativa y estable, mientras NBI cruza cero. Esta
lectura territorial difiere del modelo anterior con q60 y debe resolverse antes
de congelar un finalista inferencial.

## Decisiones Y Limites

- Mantener A0 como referencia estructural.
- Mantener E1 solo como referencia historica dinamica.
- Cerrar esta etapa predictiva con A0 y una correccion XGBoost compacta que usa
  tiempo desde levante, `rms_q_7`, `rms_w_7`, `q7 - q60` y feriado. No fue
  promovido aun al scoring ni a la app.
- No interpretar SHAP o interacciones de XGBoost como efectos causales.
- En el modelo inferencial, interpretar densidad y NBI como asociaciones con
  reclamos registrados. El bootstrap respalda estabilidad dentro de la muestra,
  no identificacion causal.
- No reabrir variantes descartadas sin una hipotesis nueva o un cambio de datos.
- Evaluar siempre con cortes temporales y respetar COM hasta `D-2`.
- Algunos experimentos iniciales basados en scores COM no fueron OOF de extremo
  a extremo; el candidato X2 reciente usa A0 OOF durante entrenamiento.
- La expansion por cobertura se usa solo en graficos comparables con el universo
  completo; las metricas se calculan sobre la muestra comun sin expansion.
- Ningun candidato fue incorporado al scoring ni a la app.

## Proximo Paso

Validar la logica del prototipo retrospectivo de app y definir el contrato
operativo, los intervalos predictivos y el monitoreo antes de promover el modelo
compacto al scoring diario. En paralelo, definir el umbral de dia complicado.
En T029 queda pendiente acordar la presentacion sustantiva de los efectos. La
exploracion con clima `D-1` ya se realizo: no produjo una mejora estable y el
viento maximo conservo una asociacion negativa dificil de interpretar incluso
al controlar el ciclo anual. En T032 corresponde congelar ahora los finalistas
a partir de la validacion; cualquier nueva prueba climatica requiere
completar la cobertura de temperatura y precipitacion.

## Donde Buscar Detalle

- Inventario modelo por modelo, tablas y graficos:
  `documentacion/pronostico_diario_clusters_reclamo_com.qmd`.
- Resumen breve para compartir:
  `documentacion/resumen_pronostico_diario_com.qmd`.
- Scripts: `scripts/*agregado*_com.R`, `scripts/experimentar_*_com.R`,
  `scripts/explorar_*_com.R`, `scripts/probar_*_com.R` y
  `scripts/comparar_*_com.R`.
- Resultados reproducibles: subcarpetas correspondientes en `outputs/`.
