# Hitos Del Proyecto

Este archivo registra avances importantes y decisiones estables del proyecto. Sirve como memoria cronologica para retomar el trabajo en futuras sesiones.

## 2026-08-28 - Prototipo funcional del pronostico agregado en la app

Area: app / modelos / COM / Zona Limpia

Se implementa una primera version retrospectiva para probar indicadores,
selecciones y mapas antes del refactor tecnico de la app.

### Decisiones

- La suma de scores deja de mostrarse como indicador operativo de volumen.
- COM y ZL tienen configuraciones de seleccion independientes.
- COM puede usar el total agregado, cupos estimados por barrio o repartir una
  capacidad fija segun la afectacion barrial esperada.
- ZL conserva opciones basadas en porcentaje, cantidad, umbral y reglas por
  barrio, sin usar el modelo agregado COM.
- Las capas COM y ZL pueden verse simultaneamente.
- Se retira de la interfaz la comparacion historica de hexagonos y se reemplazan
  los contornos negros de observados por categorias de captura mas legibles.
- La comparacion de desempeno historico pasa a una tabla de todas las estrategias
  con parametros, seleccionados, evaluables, capturados, precision, cobertura y
  lift.
- Para ZL, precision y lift se calculan solo entre seleccionados con visita
  efectiva.
- La afectacion barrial se une por codigo INE y se excluye el poligono sin nombre
  para evitar faltantes causados por diferencias en tildes o enie.
- Las salidas agregadas actuales son retrospectivas y no se presentan como
  contrato operativo definitivo.

### Archivos relacionados

- `app_operativa/app.R`
- `app_operativa/R/datos_app.R`
- `app_operativa/www/app.css`
- `app_operativa/tests/test_app.R`
- `app_operativa/README.md`
- `tareas/T028_pronosticar_y_explicar_volumen_diario_reclamos_com.md`

## 2026-08-28 - Separacion del pronostico y la linea inferencial COM

Area: modelos / COM / tareas / app

Se acota T028 al pronostico diario de clusters con reclamo, su validacion, el
contrato operativo y su futura integracion en la app. La explicacion de los dias
con alta afectacion territorial pasa a T029 como tarea pendiente independiente.

### Decisiones

- La linea inferencial no bloquea la integracion del pronostico agregado en la
  app.
- Las interacciones del modelo predictivo no se interpretan como evidencia
  causal.
- T029 conserva el trabajo inferencial pendiente con prioridad media.

### Archivos relacionados

- `TAREAS.md`
- `tareas/T028_pronosticar_y_explicar_volumen_diario_reclamos_com.md`
- `tareas/T029_explicar_dias_alta_afectacion_territorial_com.md`
- `knowledge/wiki/estado_actual.md`
- `knowledge/wiki/modelos_agregados_com.md`

## 2026-08-27 - Feriados en la correccion dinamica del pronostico COM

Area: modelos / COM / pronostico diario

Se compara el candidato XGBoost W7 + `q7 - q60` contra variantes que incorporan
feriado y postferiado en la correccion dinamica, manteniendo A0 sin cambios. El
calendario vigente marca los dos dias de Carnaval y los cinco dias laborables
de Turismo.

Agregar solo feriado reduce el RMSE combinado de `157,1` a `155,0` y deja el
sesgo practicamente en cero. Agregar tambien postferiado obtiene RMSE `156,0` y
no mejora la variante con solo feriado. El resultado queda como evidencia
experimental; todavia no se promueve ningun modelo al scoring ni a la app.

Tambien se prueba la media del top 20 % de severidad `h` por segmento/dia sobre
el candidato con feriado. Obtiene RMSE combinado `156,6` y empeora los errores
en picos altos y bajos frente a la variante con solo feriado, por lo que se
descarta en esta forma.

Como contraste adicional se agregan por separado la diferencia y el ratio entre
el promedio global de clusters con reclamo de 7 y 60 dias, cerrados en `D-2`.
Obtienen RMSE combinado `162,9` y `160,4`, respectivamente. Aunque XGBoost les
asigna gain alto, ambas generalizan peor y quedan descartadas.

La evaluacion barrio/dia muestra que X2 mejora el RMSE de A0 en 53 de 62
barrios. Agregar feriado mejora X2 en 35 barrios y mantiene una ventaja frente
a A0 en 53. Para el candidato con feriado, el RMSE mediano por barrio es `5,1`,
el RMSE relativo mediano `0,440` y la correlacion temporal mediana `0,485`.

Se prueban tambien la propension W7 del barrio y su cambio respecto de W60. El
nivel barrial solo mejora test a RMSE `169,5`, pero queda peor en el combinado
con `156,2` frente a `155,0`. El bloque con cambio barrial requiere 616
iteraciones y empeora test a `184,1`, por lo que ambas variantes quedan fuera
del candidato vigente.

Finalmente se comparan cinco niveles de poda del XGBoost. Se selecciona la
version compacta de cinco variables: tiempo desde levante, `rms_q_7`,
`rms_w_7`, `q7 - q60` y feriado. Obtiene RMSE combinado `156,0`, correlacion
`0,691`, reproduce `83,0%` de la variabilidad y mejora test frente a la version
completa, reduciendo las entradas dinamicas de 13 a 5.

Archivos principales:

- `scripts/comparar_feriados_xgboost_com.R`;
- `outputs/comparacion_feriados_xgboost_com/`;
- `documentacion/pronostico_diario_clusters_reclamo_com.qmd`;
- `tareas/T028_pronosticar_y_explicar_volumen_diario_reclamos_com.md`.

## 2026-08-21 - Primeros modelos COM agregados por barrio y CCZ

Area: modelos / COM / territorio / pronostico diario

Se construyen y comparan modelos `barrio/dia` y `CCZ/dia` para predecir la
cantidad de clusters con al menos un reclamo. Ambos usan una exposicion binomial
por clusters activos, resumenes dinamicos de la tabla cluster-dia, variables
sociodemograficas, interacciones con NBI e interceptos territoriales penalizados.

En test, ambos modelos recuperan alrededor de `76%` del desvio observado y
alcanzan correlacion cercana a `0,53`, frente a `37%` y correlacion `0,36` de la
suma de scores. El RMSE mejora, pero el MAE queda levemente peor. En validacion
se observa sobreestimacion importante, por lo que los resultados son
promisorios pero no suficientes para elegir modelo ni promoverlo a operacion.

Archivos principales:

- `scripts/modelo_agregado_territorial_diario_com.R`;
- `outputs/modelos_agregados_territoriales_com/`;
- `documentacion/pronostico_diario_clusters_reclamo_com.qmd`;
- `tareas/T028_pronosticar_y_explicar_volumen_diario_reclamos_com.md`.

## 2026-08-20 - Backlog indexado con fichas separadas

Area: documentacion / forma de trabajo

Se reemplaza el backlog monolitico por un indice breve en `TAREAS.md` y una
ficha independiente por tarea en `tareas/`. El indice agrupa las tareas por
estado, conserva una descripcion corta y enlaza el detalle correspondiente.

Se definen los estados `pendiente`, `en proceso`, `bloqueada`, `finalizada` y
`descartada`. Las categorias sin tareas no se muestran en el indice. Al cambiar
una tarea deben actualizarse tanto su ficha como la linea del indice.

La migracion conserva los identificadores `T001` a `T027`. Se actualizan las
reglas de trabajo y la wiki para leer primero el indice y abrir solamente las
fichas relevantes.

Archivos principales:

- `TAREAS.md`;
- `tareas/Txxx_*.md`;
- `AGENTS.md`;
- `knowledge/wiki/flujo_trabajo.md`;
- `knowledge/wiki/mapa_documental.md`.

## 2026-07-16 - Diagnostico territorial del modelo COM por CCZ

Area: modelos / COM / territorio / evaluacion

Se implementa una evaluacion territorial del modelo logistico reducido COM D-2
sin reentrenar modelos por CCZ ni incorporar territorio como predictor. El mismo
modelo global se audita en los 18 CCZ para discriminacion, calibracion, ranking
global de ciudad y ranking local dentro de cada territorio.

La reconstruccion reproduce las metricas originales: AUC `0,753` en validacion
y test. La cobertura territorial es completa. El AUC por CCZ varia entre `0,691`
y `0,771` en validacion, y entre `0,691` y `0,760` en test. Tambien se observan
diferencias territoriales de calibracion, que deben interpretarse respecto del
target de reclamos COM y no como medicion directa de problemas fisicos.

Se generan intervalos mediante 1.000 remuestreos de metricas diarias por CCZ y
se documentan por separado las politicas de ranking global y local.

Archivos principales:

- `scripts/diagnostico_territorial_modelo_com_ccz.R`;
- `documentacion/analisis_territorial_pred.qmd`;
- `outputs/diagnostico_territorial_modelo_com_ccz/`.

## 2026-07-13 - App operativa multi-modelo COM y Zona Limpia

Area: app / scoring operativo / zona limpia

### Resumen

Se integra una salida historica larga para que la app pueda alternar entre el score de reclamos COM y el score exploratorio de problema observado Zona Limpia.

### Decisiones

- La unidad de consumo de la app queda como `cluster_id` / `dia_objetivo` / `modelo_id` / `version_modelo`.
- `com_reclamo` predice reclamos COM.
- `zl_problema` predice problema observado Zona Limpia usando el candidato parsimonioso `operativo_segmento`.
- La app sigue siendo de solo lectura: no calcula features ni aplica modelos.
- Las metricas historicas usan el observado del target seleccionado para evitar mezclar reclamos COM con problemas ZL.

### Archivos relacionados

- `scripts/construir_app_modelos_largo_historico.R`
- `app_operativa/app.R`
- `app_operativa/R/datos_app.R`
- `app_operativa/README.md`
- `app_operativa/tests/test_app.R`
- `data/processed/app_modelos_largo/`

### Resultado

La salida `data/processed/app_modelos_largo/` contiene 509 dias por modelo, desde `2025-01-01` hasta `2026-05-24`, con 3.951.029 filas para `com_reclamo` y 3.951.029 filas para `zl_problema`.

La prueba de sesion de la app finalizo con `SESSION_OK`.

Actualizacion: la app prioriza `data/processed/app_modelos_largo/` como default
cuando `APP_DATA_PATH` no esta seteado. Se agrega en Mapa la representacion
`Cruce COM/ZL` para ver en una misma capa los clusters priorizados por ambos
scores, solo por COM o solo por ZL.

## 2026-07-13 - Cascada parsimoniosa de features para modelo Zona Limpia

Area: zona limpia / modelos / features

### Resumen

Se evalua una cascada de modelos XGBoost para problema observado Zona Limpia, separando features operativas, demografia de segmento, clima y territorio nominal/ampliado.

### Decisiones

- El target se mantiene como `hay_zl_problema_comparable`.
- COM no entra como feature.
- `amplio_actual` queda como default del script para compatibilidad, pero se interpreta como diagnostico territorial amplio.
- `operativo_segmento` queda como candidato parsimonioso para seguir explorando.
- Los escenarios con clima se mantienen exploratorios.

### Archivos relacionados

- `zona_limpia/08_modelo_problema_observado_zl_xgboost.R`
- `scripts/consolidar_experimento_cascada_zl.R`
- `data/processed/modelos/experimentos_cascada_zl/`
- `zona_limpia/outputs/experimentos_cascada_zl/`

### Resultado

En splits random, `amplio_actual` tiene mejor AUC, pero usa categorias territoriales y muchas mas columnas. En split temporal, `operativo_segmento` queda muy competitivo y supera levemente a `amplio_actual` en AUC test (`0,601` vs `0,599`) con 36 columnas y sin municipio, CCZ ni barrio nominal.

La lectura inicial es que conviene avanzar con un modelo ZL parsimonioso basado en levante, contenedores, calendario y variables de segmento, dejando el modelo amplio para diagnostico territorial y no como baseline operativo directo.

## 2026-07-13 - Experimento de exceso sobre periodo teorico en modelos COM

Area: modelos / COM / features

### Resumen

Se evalua agregar al modelo COM una variable de exceso del tiempo desde ultimo levante respecto al periodo teorico.

### Decisiones

- El exceso se calcula solo con variables ya disponibles ex ante: `mean_tiempo_desde_ultimo_levante_pred` y `mean_levante_periodo`.
- Se agregan dos variantes: exceso positivo y exceso positivo truncado a 7 dias.
- La feature queda detras de un flag experimental (`USAR_EXCESO_LEVANTE=1`) y no modifica los modelos por defecto.
- No se promueve al baseline operativo con la evidencia actual.

### Archivos relacionados

- `funciones/modelos_utils.R`
- `scripts/modelo_logistico_cluster_dia_reducido.R`
- `scripts/modelo_xgboost_cluster_dia.R`
- `scripts/modelo_random_forest_cluster_dia.R`
- `scripts/consolidar_experimento_exceso_levante_com.R`
- `outputs/experimentos_exceso_levante/`

### Resultado

En XGBoost COM, las variables de exceso aparecen con importancia, pero la mejora global es marginal: validacion sube aproximadamente `AUC +0,00003` y test baja aproximadamente `AUC -0,00028`. En el logistico reducido ocurre algo similar: validacion sube aproximadamente `AUC +0,00005` y test baja aproximadamente `AUC -0,00015`.

La lectura inicial es que el exceso resume una senal existente, pero no aporta evidencia suficiente para cambiar el baseline. Puede quedar como candidata para futuras pruebas con otra especificacion o interacciones.

## 2026-07-13 - Fuente climatica INUMET para modelo Zona Limpia

Area: datos / clima / zona limpia

### Resumen

Se agrega una descarga reproducible de datos abiertos de INUMET para usar variables climaticas como potenciales features ex ante del modelo Zona Limpia.

### Decisiones

- La fuente inicial es INUMET Datos Abiertos.
- La estacion usada es `Melilla G3`, `estacion_id = 608`.
- Las variables descargadas son `Temperatura del Aire` y `Precipitacion Acumulada Horaria`.
- Se usan como fuente primaria local dos CSV horarios descargados desde INUMET y se generan tablas procesadas horaria y diaria.
- La fuente se documenta como datos crudos sin validacion, segun advertencia de INUMET.

### Archivos relacionados

- `scripts/descargar_clima_inumet_melilla_g3.R`
- `data/raw/inumet/datos_abiertos/`
- `data/processed/clima/inumet_melilla_g3/clima_inumet_melilla_g3_horario.csv`
- `data/processed/clima/inumet_melilla_g3/clima_inumet_melilla_g3_diario.csv`
- `data/processed/clima/inumet_melilla_g3/clima_inumet_melilla_g3_features_diarias.csv`
- `data/processed/clima/inumet_melilla_g3/cobertura_anual.csv`
- `data/processed/clima/inumet_melilla_g3/metadata.csv`

### Resultado

La descarga solicitada desde `2025-01-01` queda ejecutada a partir de dos CSV locales horarios (`inumet_temperatura_del_aire.csv` e `inumet_precipitacion_acumulada_horaria.csv`) ubicados en `data/raw/inumet/datos_abiertos/`. Estos CSV contienen `Aeropuerto Melilla G3` desde 2020. La tabla diaria procesada para modelado cubre `2025-01-01` a `2026-07-13`.

Se genera ademas una tabla de features predictivas diarias. Para cada dia `D`, las variables usan solo informacion climatica hasta `D-1`: resumen del dia anterior y ventana acumulada `D-3` a `D-1`. Esto evita leakage operativo al unir clima con tablas de modelado.

Estas variables fueron evaluadas de forma exploratoria en modelos COM y Zona Limpia, pero no fueron promovidas al baseline.

### Evaluacion Exploratoria En Modelos

Se agrega una evaluacion exploratoria de las variables climaticas en:

- XGBoost COM;
- XGBoost de problema observado Zona Limpia.

La prueba se ejecuta con `NROUNDS_XGB = 120` para COM y `NROUNDS_XGB_ZL = 120` para ZL, en salidas separadas de los modelos vigentes. No reemplaza el baseline actual.

Salidas:

- `outputs/experimentos_clima/comparacion_metricas_com_xgboost_clima_delta.csv`
- `zona_limpia/outputs/experimentos_clima/comparacion_metricas_zl_xgboost_clima_delta.csv`
- `outputs/experimentos_clima/features_importancia_com_y_zl.csv`
- `outputs/experimentos_clima/features_clima_importancia_com_y_zl.csv`

Lectura inicial:

- en COM, el clima no mejora validacion (`AUC -0,0014`) y apenas cambia test (`AUC +0,0002`);
- en ZL, el clima mejora el split random por fila, pero no mejora random por dia ni temporal;
- por ahora conviene mantenerlo como experimento y no promoverlo automaticamente al baseline.

## 2026-07-03 - Primer modelo de problema observado Zona Limpia

Area: zona limpia / modelos / territorio

### Resumen

Se crea un primer baseline XGBoost para estimar riesgo de problema observado en campo, usando visitas efectivas de Zona Limpia. El target principal queda definido por problemas comparables observados por Zona Limpia; COM se conserva solo como evaluacion secundaria.

### Decisiones

- El target principal del modelo ZL es `hay_zl_problema_comparable`.
- COM no se usa como feature ni como target principal; queda como evaluacion secundaria.
- Los problemas comparables de Zona Limpia son `basura_fuera` y `contenedor_desbordado`.
- `Voluminosos` queda excluido del entrenamiento inicial.
- Se usan meses `202510`, `202511`, `202512`, `202603`, `202604`, `202605`.
- Se mantienen excluidos `202508`, `202509`, `202601` y `202602`.
- Se agregan municipio, CCZ y barrio como atributos territoriales por cluster.
- Se evalua split temporal, split random por fila estratificado por mes/target y split random por dia estratificado por mes.

### Archivos relacionados

- `scripts/construir_cluster_territorial_admin.R`
- `zona_limpia/08_modelo_problema_observado_zl_xgboost.R`
- `zona_limpia/reportes/13_modelo_problema_observado_zl.qmd`
- `data/processed/cluster_territorial/cluster_admin_territorial/`
- `data/processed/modelos/zona_limpia_problema_observado_xgboost/`
- `zona_limpia/outputs/modelo_zl_observado_resumen_splits.csv`
- `zona_limpia/outputs/modelo_zl_observado_metricas.csv`
- `zona_limpia/outputs/modelo_zl_observado_metricas_random_dia_reps.csv`
- `zona_limpia/outputs/modelo_zl_observado_metricas_targets.csv`
- `zona_limpia/outputs/modelo_zl_observado_lift.csv`
- `zona_limpia/outputs/modelo_zl_observado_importancia.csv`

### Resultado

Luego se redefine el target principal como ZL puro (`hay_zl_problema_comparable`) y se agregan features de exceso sobre periodo teorico de levante, feriados, vispera de feriado y dia habil. El split random por fila muestra AUC cercano a `0,68` en validacion/test. El split random por dia, que separa dias completos entre train, validacion y test, queda cerca de `0,68` en validacion y `0,66` en test; cinco repeticiones ubican el AUC test aproximadamente entre `0,663` y `0,681`. El split temporal se mantiene cerca de `0,60` en validacion/test. La diferencia refuerza la hipotesis de cambios temporales de criterio, cobertura o regimen entre fines de 2025 y 2026.

La documentacion metodologica especifica del baseline queda en `zona_limpia/reportes/13_modelo_problema_observado_zl.qmd`; `documentacion/modelos.qmd` conserva solo una referencia breve para evitar duplicacion.

### Advertencia De Cobertura Territorial

Se identifica que Municipio B aparece subrepresentado en la fuente actual de Zona Limpia porque sus registros estan en otra tabla pendiente de integracion. Por lo tanto, la baja cobertura observada para Municipio B no debe interpretarse como baja prioridad real ni como ausencia de visitas.

Esta limitacion afecta diagnosticos territoriales, entrenamiento del modelo Zona Limpia observado y evaluaciones contrafactuales basadas en visitas efectivas.

### Criterio De Levante

Se agrega un diagnostico exploratorio para evaluar si la seleccion de Zona Limpia se asocia con tiempo desde ultimo levante y exceso respecto al periodo teorico.

Variable principal:

```text
min(max(mean_tiempo_desde_ultimo_levante_pred - mean_levante_periodo, 0), 7)
```

Resultado inicial: los cluster-dias visitados por Zona Limpia muestran mayor tiempo desde ultimo levante, mayor ratio tiempo/periodo y mayor exceso positivo que los no visitados. La tasa de visita aumenta con excesos positivos moderados, pero no de forma lineal simple en valores altos.

Archivos relacionados:

- `zona_limpia/09_diagnostico_criterio_levante_zl.R`
- `zona_limpia/outputs/diagnostico_levante_zl_bin_exceso_mean_trunc_7.csv`
- `zona_limpia/outputs/diagnostico_levante_zl_decil_exceso_mean_trunc_7.csv`

### Reporte De Sesgos De Seleccion

Se consolida la lectura de sesgos de seleccion de Zona Limpia en:

- `zona_limpia/reportes/10_sesgos_seleccion_zona_limpia.qmd`

El reporte documenta cobertura territorial, advertencia de Municipio B por fuente faltante y patrones asociados al exceso sobre periodo teorico de levante.

### Correspondencia COM-Zona Limpia Por Territorio

Se agrega un diagnostico para medir, excluyendo Municipio B, que proporcion de problemas observados por Zona Limpia tiene reclamo COM asociado.

Resultado inicial: aproximadamente `10,8%` de los problemas comparables observados por Zona Limpia tienen COM asociado en el mismo cluster-dia. La correspondencia varia por municipio y CCZ, lo que sugiere diferencias territoriales en propension a reclamar o en captura COM de problemas observados.

Esta lectura queda incorporada tambien al reporte de sesgos de seleccion de Zona Limpia, con tabla global, tabla por municipio y graficos por municipio y CCZ.

### Ajuste Por Propension De Visita Zona Limpia

Se agrega un baseline exploratorio para corregir parcialmente la seleccion no aleatoria de Zona Limpia. El modelo estima la propension de visita efectiva usando features previas de levante, territorio y calendario, excluyendo Municipio B por fuente incompleta. Luego se recalcula la correspondencia COM-Zona Limpia con pesos IPW estabilizados.

Resultado inicial: el ajuste no reduce la hipotesis de subreclamo. El ratio global `problemas ZL / COM` pasa de `5,44` crudo a `5,65` ajustado; el ratio `solo ZL problema / COM` pasa de `4,86` a `5,07`. La lectura sigue condicionada al supuesto de que las features observadas capturan suficientemente la regla de seleccion.

Archivos relacionados:

- `zona_limpia/11_diagnostico_correspondencia_com_zl_territorio.R`
- `zona_limpia/12_modelo_propension_visita_zl_y_ajuste_correspondencia.R`
- `zona_limpia/reportes/10_sesgos_seleccion_zona_limpia.qmd`
- `zona_limpia/outputs/correspondencia_com_zl_territorio_municipio.csv`
- `zona_limpia/outputs/correspondencia_com_zl_territorio_ccz.csv`
- `zona_limpia/outputs/correspondencia_com_zl_ipw_global.csv`
- `zona_limpia/outputs/correspondencia_com_zl_ipw_municipio.csv`

## 2026-07-02 - Comparacion diaria Zona Limpia vs modelo a igual N

Area: zona limpia / modelos / evaluacion operativa

### Resumen

Se construye una comparacion diaria entre los clusters efectivamente visitados por Zona Limpia y los clusters que habria sugerido el modelo `logistico_reducido_d2` usando la misma cantidad diaria de visitas.

### Decisiones

- El periodo principal es marzo, abril y mayo de 2026, segun disponibilidad de datos.
- El problema real observado se define como reclamo COM valido o problema comparable observado por Zona Limpia.
- Los problemas comparables de Zona Limpia son `basura_fuera` y `contenedor_desbordado`.
- `Voluminosos` no cuenta como problema en la metrica principal.
- La seleccion del modelo usa top N diario, donde N es la cantidad de clusters con visita efectiva de Zona Limpia ese dia.
- Se agregan tambien metricas COM-only para evaluar el objetivo original del modelo: captura de reclamos COM.
- La lectura debe tratarse como conservadora para el modelo porque en lugares no visitados por Zona Limpia solo se observa problema si hubo reclamo COM.

### Archivos relacionados

- `zona_limpia/06_comparar_seleccion_zl_vs_modelo_diario.R`
- `zona_limpia/reportes/07_visualizar_seleccion_zl_vs_modelo.qmd`
- `zona_limpia/outputs/seleccion_zl_vs_modelo_diario_logistico_reducido_d2.csv`
- `zona_limpia/outputs/seleccion_zl_vs_modelo_mensual_logistico_reducido_d2.csv`

### Visualizacion

Se agrega un reporte Quarto para comunicar la comparacion con cuatro lecturas: tasas diarias, tasas mensuales, diferencias diarias y tension entre objetivo de problema real observado y objetivo COM. En esta maquina `quarto` no esta disponible en el PATH, por lo que el HTML no se renderizo desde consola.

## 2026-07-01 - Exclusion de meses con cobertura anomala en analisis Zona Limpia

Area: zona limpia / calidad de datos

### Resumen

Se excluyen los meses `202508`, `202509`, `202601` y `202602` de los analisis de Zona Limpia porque la cantidad de registros es anormalmente baja y se interpreta como un problema de registro/cobertura.

### Decisiones

- La base ampliada `data/parquet/com_completo/` no se modifica.
- La exclusion se aplica en scripts analiticos de Zona Limpia.
- Los meses excluidos no deben interpretarse como baja real de problemas, visitas o actividad.

### Archivos relacionados

- `zona_limpia/funciones_zona_limpia.R`
- `zona_limpia/03_analisis_descriptivo_zona_limpia.R`
- `zona_limpia/04_comparar_com_zona_limpia_cluster_dia.R`
- `zona_limpia/05_evaluar_scores_com_vs_zona_limpia.R`
- `zona_limpia/README.qmd`

## 2026-07-01 - Scores COM frente a problemas observados por Zona Limpia

Area: zona limpia / modelos / evaluacion

### Resumen

Se evalua si los scores COM ya existentes priorizan problemas observados por Zona Limpia, especialmente casos donde Zona Limpia detecta problema comparable y COM no registra reclamo.

### Decisiones

- La comparacion se limita al periodo con predicciones disponibles.
- El ranking se calcula por modelo y dia, usando top 1%, 5%, 10% y 20%.
- La lectura principal se hace dentro del universo comparable de Zona Limpia.
- El resultado se interpreta como diagnostico del score COM, no como evaluacion definitiva de problema real.

### Archivos relacionados

- `zona_limpia/05_evaluar_scores_com_vs_zona_limpia.R`
- `data/processed/zona_limpia/scores_com_vs_zona_limpia_cluster_dia/`
- `zona_limpia/outputs/scores_com_vs_zona_limpia_resumen_solo_zl_problema.csv`
- `zona_limpia/outputs/scores_com_vs_zona_limpia_resumen_estado.csv`
- `zona_limpia/outputs/scores_com_vs_zona_limpia_captura_top_por_estado.csv`

### Resultado

Los scores COM priorizan claramente los casos donde hay reclamo COM, pero no concentran especialmente los problemas detectados solo por Zona Limpia. Excluyendo enero y febrero de 2026, en test `solo_zona_limpia_problema` queda en top 10% diario entre 9,0% y 9,3% segun modelo; en validacion, entre 6,2% y 6,8%. Esto refuerza la necesidad de explorar un modelo especifico de problema observado por Zona Limpia y un modelo de propension de visita.

## 2026-07-01 - Variables territoriales censales por cluster

Area: datos / territorio / features

### Resumen

Se integra el shape de segmentos censales 2011 de Montevideo a la referencia de clusters. La salida genera una tabla fija por `version_cluster`/`cluster_id` con asignacion a segmento censal, variables demograficas y diagnosticos de mezcla territorial.

### Decisiones

- El segmento censal base del cluster se asigna usando el centroide operativo del cluster, calculado como promedio de sus posiciones.
- Se guardan poblacion, hogares, viviendas, viviendas ocupadas, NBI y densidades por km2.
- Se conserva tambien el segmento principal por cantidad de posiciones del cluster.
- Los clusters con posiciones en mas de un segmento se marcan con `cluster_multisegmento`.
- La tabla queda como insumo fijo territorial para modelos COM, modelos Zona Limpia, propension de visita y analisis de sesgo de reclamo.

### Archivos relacionados

- `scripts/construir_cluster_territorial_segmento_censal.R`
- `data/processed/cluster_territorial/cluster_segmento_censal/`
- `data/processed/cluster_territorial/resumen/cluster_segmento_censal_resumen.csv`
- `data/processed/cluster_territorial/resumen/cluster_segmento_censal_resumen_segmentos.csv`
- `shp/Marco2011_SEG_Montevideo_Total/`

### Resultado

La corrida con `version_cluster = v2026_05_25` genero 9.168 clusters con segmento censal asignado por centroide y cero clusters sin segmento. Se identificaron 471 clusters multisegmento, equivalentes al 5,1% del total.

## 2026-07-01 - Comparacion COM vs Zona Limpia por cluster-dia

Area: zona limpia / auditoria / comparacion territorial

### Resumen

Se construye una tabla reproducible para comparar reclamos COM y registros Zona Limpia a nivel `cluster_id`/`dia`. La comparacion permite distinguir coincidencias, problemas observados por Zona Limpia sin reclamo COM, reclamos COM sin validacion de Zona Limpia, visitas limpias y casos no visitados.

### Decisiones

- Zona Limpia, cuando hay visita efectiva, se interpreta como evidencia observacional fuerte porque surge de una visita al lugar.
- COM no se trata como verdad absoluta, porque depende de la propension territorial y demografica a reclamar.
- Para la comparacion estricta con COM, `Voluminosos` queda separado y no cuenta como problema comparable.
- Los problemas comparables de Zona Limpia son `basura_fuera` y `contenedor_desbordado`.
- La coincidencia COM vs Zona Limpia debe evaluarse solo donde `universo_comparable_zl == TRUE`, es decir, donde Zona Limpia tuvo visita efectiva. Los casos sin visita efectiva quedan para medir cobertura/no validacion.
- Las salidas quedan separadas en `data/processed/zona_limpia/` y no modifican el pipeline operativo del modelo.

### Archivos relacionados

- `zona_limpia/04_comparar_com_zona_limpia_cluster_dia.R`
- `zona_limpia/funciones_zona_limpia.R`
- `data/processed/zona_limpia/asignaciones_zona_limpia/`
- `data/processed/zona_limpia/zona_limpia_cluster_dia/`
- `data/processed/zona_limpia/comparacion_com_zona_limpia_cluster_dia/`
- `zona_limpia/outputs/comparacion_com_zona_limpia_resumen_estado.csv`
- `zona_limpia/outputs/comparacion_com_zona_limpia_resumen_mensual.csv`
- `zona_limpia/outputs/comparacion_com_zona_limpia_resumen_cluster.csv`

### Resultado

La corrida con `version_cluster = v2026_05_25`, excluyendo enero y febrero de 2026 del analisis Zona Limpia, genero 642.248 filas `cluster_id`/`dia` con evento COM o Zona Limpia. Entre los estados principales aparecen 6.921 cluster-dias donde ambas fuentes reportan problema comparable, 56.848 donde solo Zona Limpia reporta problema comparable y 4.852 donde COM reporta mientras Zona Limpia registra limpio.

## 2026-07-01 - Base ampliada COM para analisis Zona Limpia

Area: datos / zona limpia / auditoria

### Resumen

Se crea un frente exploratorio separado para analizar registros COM `Zona limpia` sin alterar el pipeline operativo del modelo ni la app.

### Decisiones

- Los scripts del proceso quedan en `zona_limpia/`, separados de `scripts/`.
- La salida `data/parquet/com/` se mantiene como base filtrada para el modelo y solo debe ser escrita por `scripts/get_datos_COM.R`.
- La nueva salida `data/parquet/com_completo/` incluye incidentes del modelo y registros `Zona limpia`.
- La funcion `normalizar_incidente_zona_limpia()` normaliza diferencias tipograficas basicas en etiquetas Zona Limpia.
- El mapeo fino de categorias queda definido en `zona_limpia/mapeo_incidentes_zona_limpia.csv`.

### Archivos relacionados

- `zona_limpia/README.qmd`
- `zona_limpia/funciones_zona_limpia.R`
- `zona_limpia/mapeo_incidentes_zona_limpia.csv`
- `zona_limpia/01_generar_com_completo.R`
- `zona_limpia/02_diagnostico_etiquetas_zona_limpia.R`
- `data/parquet/com_completo/`
- `zona_limpia/outputs/`

### Resultado

La base ampliada local contiene 975.749 registros: 592.570 incidentes usados por el modelo y 383.179 registros `Zona limpia`. Los registros `Zona limpia` quedan clasificados en 7 categorias canonicas.

## 2026-06-30 - Primera version de app operativa

Area: app / visualizacion operativa

### Resumen

Se implementa una primera app Shiny de solo lectura para consumir las predicciones operativas ya generadas por el proceso de scoring.

### Decisiones

- La app no calcula features ni aplica modelos.
- La app consume salidas publicadas por el proceso operativo.
- Las vistas principales son predicciones del dia operativo, mapa, historico y estado de datos.
- La agregacion territorial inicial usa hexagonos; DBSCAN queda fuera de la primera version.
- En historico se conserva la visualizacion cruda y queda pendiente agregar comparacion territorial agregada contra reclamos reales.

### Archivos relacionados

- `app_operativa/app.R`
- `app_operativa/R/datos_app.R`
- `app_operativa/run_app.R`
- `documentacion/proceso_scoring_operativo.qmd`
- `TAREAS.md`

### Pendientes

- Implementar comparacion territorial historica por hexagonos.
- Revisar nombres de pestanas y textos para evitar confusion entre "Hoy" y dia operativo disponible.

## 2026-06-30 - Proceso operativo persistente de scoring

Area: scoring operativo / datos / app

### Resumen

Se define e implementa el proceso operativo que genera y publica predicciones acumuladas para la app. El proceso corre por fuera de la app y trabaja con fuentes ya materializadas en Parquet.

### Decisiones

- La app consume una tabla acumulada de predicciones; no recalcula nada.
- La fecha base se detecta desde el estado persistente guardado.
- Si hay varios dias pendientes, se procesan como un bloque unico.
- Las predicciones historicas no se recalculan por defecto.
- Se usan staging, respaldos y lock para evitar publicaciones incompletas o corridas simultaneas.
- Si una fuente critica esta atrasada, no se publican predicciones incompletas.

### Archivos relacionados

- `scripts/proceso_scoring_operativo_cluster_dia.R`
- `config/scoring_operativo.env.example`
- `documentacion/proceso_scoring_operativo.qmd`

### Pendientes

- Separar claramente corrida emulada y ruta productiva final.
- Definir columnas explicativas finales que debe consumir la app.

## 2026-06-30 - Emulacion por ventana, estado historico e incremento por bloque

Area: scoring operativo / features

### Resumen

Se valida una estrategia operativa para reconstruir features de dias nuevos sin recalcular toda la historia cada dia. La solucion combina una ventana reciente con una tabla liviana de estado historico por cluster.

### Decisiones

- La ventana reciente calcula variables moviles y features operativas.
- El estado historico conserva memoria acumulada por cluster.
- Para varios dias pendientes, se construye una sola ventana desde `B+1-VENTANA_DIAS` hasta `F`.
- Solo se guardan las predicciones de los dias objetivo; la ventana auxiliar no se publica en la tabla de la app.
- El cierre de reclamos del estado no avanza mas alla de la fecha COM cerrada.

### Archivos relacionados

- `scripts/construir_estado_historico_cluster.R`
- `scripts/validar_estado_historico_incremental.R`
- `scripts/emular_scoring_operativo_ventana_cluster_dia.R`
- `scripts/emular_scoring_operativo_bloque_cluster_dia.R`
- `documentacion/proceso_scoring_operativo.qmd`

### Resultado

La actualizacion incremental del estado historico se valido contra reconstruccion completa. En la prueba documentada, la actualizacion de diez dias produjo cero diferencias en el estado y el costo adicional de pasar de un dia a diez dias fue bajo frente al costo fijo de construir la ventana.

## 2026-06-30 - Regla operativa de cortes temporales

Area: scoring operativo / no leakage

### Resumen

Se define la regla temporal para predecir un dia objetivo `D` en contexto operativo, considerando las frecuencias reales de actualizacion de levantes y reclamos COM.

### Decisiones

- Levantes: usar informacion disponible hasta `D 01:00`.
- Reclamos historicos: usar reclamos cerrados hasta `D-2`.
- Reclamos de `D`: nunca entran como features.
- Reclamos observados de `D`: se completan despues, cuando COM este cerrado.
- Si `timestamp_max_levante < D 01:00`, no se genera la prediccion.
- La hora de corte de levantes debe ser parametrizable.

### Archivos relacionados

- `documentacion/proceso_scoring_operativo.qmd`
- `scripts/emular_scoring_operativo_cluster_dia.R`
- `scripts/modelo_logistico_cluster_dia_reducido.R`

### Pendientes

- Revisar si en el futuro COM puede actualizar con dias cerrados a medianoche para volver de `D-2` a `D-1`.

## 2026-06-30 - Estructura minima de memoria del proyecto

Area: documentacion / forma de trabajo

### Resumen

Se acuerda crear una estructura minima para que el proyecto no dependa de la memoria de una sesion de Codex.

### Decisiones

- Usar `AGENTS.md` como reglas de trabajo para Codex.
- Usar `TAREAS.md` como backlog vivo, con tareas en formato ficha.
- Usar `documentacion/HITOS.md` como registro cronologico de avances importantes.
- Usar `documentacion/versiones/` para registros puntuales de cambios relevantes.
- Mantener el README como mapa general del proyecto, con ajustes minimos.

### Archivos relacionados

- `AGENTS.md`
- `TAREAS.md`
- `documentacion/HITOS.md`
- `documentacion/versiones/`
- `README.qmd`

### Pendientes

- Mantener actualizadas las tareas a medida que se avance.
- Registrar nuevos cambios relevantes en hitos o versiones.

## 2026-06-12 - Comparacion de modelos principales

Area: modelos

### Resumen

Quedan documentados y comparados los modelos principales del proyecto: logistico completo, logistico reducido, Random Forest y XGBoost.

### Decisiones

- El logistico reducido se usa como referencia interpretable.
- Random Forest y XGBoost usan las mismas variables del logistico reducido para hacer comparable el cambio de algoritmo.
- La comparacion se realiza con metricas generales, lift, capture rate, calibracion e importancia/coefs segun el modelo.
- El split temporal vigente usa 12 meses de entrenamiento, 3 meses de validacion y meses restantes para test.

### Archivos relacionados

- `documentacion/modelos.qmd`
- `scripts/modelo_logistico_cluster_dia.R`
- `scripts/modelo_logistico_cluster_dia_reducido.R`
- `scripts/modelo_random_forest_cluster_dia.R`
- `scripts/modelo_xgboost_cluster_dia.R`

### Pendientes

- Decidir si vale la pena hacer tuning acotado de Random Forest o XGBoost.
- Evaluar estabilidad diaria en validacion y test.

## 2026-06-09 - Modelo logistico reducido y validacion temporal

Area: modelos / seleccion de variables

### Resumen

Se define un modelo logistico reducido con variables seleccionadas para mejorar interpretabilidad y reducir colinealidad.

### Decisiones

- Excluir ratios tiempo/periodo y duplicados `min`/`median`/`max` para mejorar interpretabilidad.
- Usar historia observada del cluster por tramos.
- Truncar `dias_desde_ultimo_reclamo_o_inicio` en 90 dias.
- Usar variables predictivas de levante con sufijo `_pred`.
- No crear indicadores `_na` automaticos para variables predictivas de levante/ratio.
- Incorporar validacion temporal con folds mensuales.

### Archivos relacionados

- `documentacion/modelos.qmd`
- `documentacion/diagnostico_variables_modelo.qmd`
- `scripts/modelo_logistico_cluster_dia_reducido.R`

### Pendientes

- Revisar en el futuro si las variables de actividad reciente de levantes deben entrar como indicadores o filtros.

## 2026-05-28 - Flujo base de datos y unidad cluster-dia

Area: datos / features

### Resumen

Se consolida el flujo de datos para construir la tabla principal de modelado a nivel `cluster_id`/`dia`.

### Decisiones

- La unidad principal de modelado es `cluster_id`/`dia`, no `contenedor_id`/`dia`.
- Los reclamos COM se asignan al contenedor elegible mas cercano y luego al cluster.
- Los reclamos `asignado` y `revision` entran al target; `pendiente` queda fuera.
- Los clusters se manejan con una referencia espacial estable.
- Las features historicas excluyen el dia objetivo.
- Las variables predictivas de levante usan corte `dia + 1 hora`.

### Archivos relacionados

- `README.qmd`
- `documentacion/flujo_datos.qmd`
- `scripts/get_datos_levante.R`
- `scripts/get_datos_COM.R`
- `scripts/gen_cluster_referencia_unicos.R`
- `scripts/asignar_com_contenedores_clusters.R`
- `scripts/construir_base_cluster_dia.R`
- `scripts/construir_features_historicas_cluster_dia.R`

### Pendientes

- Evaluar regla alternativa de actividad reciente, por ejemplo levante en los ultimos 7 dias.

## 2026-08-21 - Comparacion incremental de modelos agregados COM

Area: modelos / COM / pronostico diario

### Resumen

Se ejecuta la comparacion M0--M4 para pronosticar la cantidad diaria de clusters
con reclamo, con variantes separadas por barrio y CCZ. Los ocho modelos
territoriales convergen y la cobertura del ratio tiempo/periodo supera 99,9% fuera
de muestra.

### Resultados

- El bloque operativo e historico de M2 concentra la mejora frente a M1.
- La distribucion del ratio medio por cluster de M3 agrega una senal marginal,
  pero no mejora de forma estable los errores frente a M2.
- M4 mejora levemente la correlacion y logra RMSE `190,8` en CCZ/test, aunque
  conserva una sobreestimacion fuerte en validacion.
- M2 queda como referencia parsimoniosa; no se selecciona aun un modelo
  operativo por la inestabilidad temporal observada.

### Archivos relacionados

- `documentacion/pronostico_diario_clusters_reclamo_com.qmd`
- `scripts/comparar_modelos_agregados_territoriales_m0_m4_com.R`
- `outputs/experimento_modelos_agregados_m0_m4_com/`
- `tareas/T028_pronosticar_y_explicar_volumen_diario_reclamos_com.md`

## 2026-08-27 - Informe resumen del pronostico diario COM

Area: modelos / COM / documentacion

### Resumen

Se genera un informe breve para compartir con el equipo. Compara la suma de
scores, el modelo estructural A0 y la correccion dinamica seleccionada con
XGBoost compacto de cinco variables.

### Contenido

- Metricas de validacion y test, incluida correlacion y variabilidad explicada.
- Series observadas y estimadas, con feriados identificados.
- Comparacion visual separada para validacion y test.
- Diagnostico de los barrios con mayor RMSE.

### Archivos relacionados

- `documentacion/resumen_pronostico_diario_com.qmd`
- `documentacion/resumen_pronostico_diario_com.html`
- `documentacion/pronostico_diario_clusters_reclamo_com.qmd`
- `outputs/comparacion_poda_xgboost_com/`

### Pendientes

- Evaluar ratios a nivel contenedor y clusters con al menos un contenedor extremo.
- Investigar y corregir la inestabilidad de nivel entre validacion y test.

## 2026-08-24 - Jerarquia barrio/segmento para pronostico diario COM

Area: modelos / COM / pronostico diario

### Resumen

Se construye una base segmento/dia y se prueban modelos binomiales con
interceptos penalizados de barrio y segmento, dia de semana, exceso sobre periodo
teorico y resumenes top-20/top-30 del score COM.

### Resultados

- La base tiene 469.566 segmento-dias, 951 segmentos y 62 barrios.
- Los ajustes convergen en tiempos de aproximadamente 12 a 32 segundos.
- A0, solo con dia de semana y jerarquia, obtiene en test RMSE `174,6` y
  correlacion `0,615`.
- Las variantes top-20 dominan validacion; A3 obtiene RMSE `156,8` y correlacion
  `0,691`.
- En validacion + test, top-20 obtiene RMSE `164,8` y correlacion `0,645`.
- A0 y A4 se conservan como candidatos; la seleccion queda pendiente de
  backtesting mensual.

### Archivos relacionados

- `documentacion/pronostico_diario_clusters_reclamo_com.qmd`
- `scripts/benchmark_modelo_segmento_barrio_com.R`
- `scripts/comparar_modelos_segmento_barrio_scores_com.R`
- `outputs/comparacion_modelos_segmento_barrio_scores_com/`
- `tareas/T028_pronosticar_y_explicar_volumen_diario_reclamos_com.md`

## 2026-08-31 - Inicio planificado del refactor de la app operativa

Area: app / diseno operativo

### Resumen

Se decide detener los ajustes incrementales de interfaz y abordar un refactor
planificado de la app Shiny. La app vigente se conservara como referencia antes
de implementar una nueva version.

### Decisiones

- Separar operacion del ultimo dia, evaluacion historica y diagnostico tecnico.
- No mostrar observados en la pantalla del dia mientras el periodo no este
  cerrado.
- Definir preguntas, indicadores, controles, visualizaciones, contrato de datos
  y wireframes antes de programar.
- Mantener la app como capa de solo lectura y reutilizar solo funciones
  validadas.
- Seguir `skills/shiny_skill.md` para el diseno y la implementacion modular.

### Archivos relacionados

- `tareas/T030_refactorizar_app_operativa_shiny.md`
- `TAREAS.md`
- `knowledge/wiki/app_operativa.md`
- `knowledge/wiki/estado_actual.md`
- `skills/shiny_skill.md`

## 2026-09-01 - Primera version modular de Operacion del dia

Area: app / diseno operativo

### Resumen

Se implementa `app_operativa_v2/` como primera version aislada del refactor. La
app vigente se conserva como referencia y no se reemplaza.

### Decisiones

- El mapa es la vista principal y la lista de clusters queda en otra subpestana.
- COM y Zona Limpia conservan controles de seleccion separados.
- COM y ZL son capas independientes y superpuestas; las coincidencias surgen de
  la superposicion y no forman una tercera capa.
- La estimacion COM por barrio es una tercera capa opcional.
- El resumen del dia queda cerrado por defecto y no muestra observados.
- La carga Arrow materializa solo el ultimo dia disponible.
- La implementacion usa modulos Shiny separados para seleccion, resumen, mapa y
  lista.
- COM y Zona Limpia admiten seleccion por umbral de score, cada uno con su
  propio valor.
- Se agrega `Scores y umbrales` con histograma, umbral activo y curva de cantidad
  seleccionada. COM y ZL se analizan por separado porque representan objetivos
  diferentes.

### Validacion

- `app_operativa_v2/tests/test_app.R`: `SESSION_OK`.
- Validacion visual en navegador de mapa, resumen, lista, capas independientes y
  graficos de scores.

### Archivos relacionados

- `app_operativa_v2/`
- `tareas/T030_refactorizar_app_operativa_shiny.md`

## 2026-09-01 - Capa historica liviana para la app v2

Area: app / datos / rendimiento

### Resumen

Se publica una capa de datos especifica para que la futura vista Historico no
cargue los 7,9 millones de registros en memoria.

### Decisiones

- Separar la serie agregada COM del detalle cartografico por cluster.
- Mantener completa en memoria solo la serie por Montevideo y barrio.
- Particionar el detalle por `dia_objetivo/modelo_id` y filtrar antes de
  materializar.
- No duplicar barrio ni coordenadas en el detalle; usar el maestro territorial.
- Mantener la app como consumidora de salidas ya calculadas.

### Validacion

- `serie_historica_com`: 26.280 filas y 418 dias.
- `detalle_cluster_dia`: 7.902.058 filas, 509 dias y 1.018 particiones.
- `app_operativa_v2/tests/test_datos_historicos.R`: `HISTORICO_OK`.

### Archivos relacionados

- `scripts/construir_tablas_historicas_app_v2.R`
- `documentacion/contrato_datos_app_operativa_v2.qmd`
- `data/processed/app_operativa_v2_historico/`
- `tareas/T030_refactorizar_app_operativa_shiny.md`
## 2026-09-02 - Historico v2: evolucion temporal y distribucion territorial

Se implementan dos modulos sin modificar la app de referencia ni los modelos:

- Evolucion temporal COM de Montevideo: validacion y test, selector de periodo
  y correlacion, R2 predictivo, RMSE y MAE comparados con toda la evaluacion.
- Evaluacion del dia COM: lectura de una particion diaria, criterios operativos
  y dos mapas de distribucion porcentual por hexagonos con grilla/escala comunes.
  Cada distribucion usa su propio total; no exige acierto en el mismo cluster.

Pruebas durante la implementacion: EVOLUCION_OK, SESSION_OK y DIA_COM_OK.
Quedan pendientes revision visual, sincronizacion en navegador y definicion de
metricas comparativas. La tarea T030 permanece en proceso.

Fuentes: `app_operativa_v2/R/mod_evolucion.R`,
`app_operativa_v2/R/mod_dia_com.R` y
`tareas/T030_refactorizar_app_operativa_shiny.md`.

## 2026-09-10 - Configuracion segura de la conexion Impala

Area: configuracion / seguridad / portabilidad

### Resumen

La configuracion de conexion a Impala deja de estar escrita en los cargadores
de datos y pasa a variables de entorno locales.

### Decisiones

- `.Renviron` queda excluido de Git.
- `Renviron.example` documenta las variables requeridas sin valores reales.
- Los cargadores COM y levantes fallan con un mensaje explicito si falta alguna
  variable requerida.
- Las credenciales expuestas anteriormente deben rotarse antes de publicar el
  repositorio.

### Archivos relacionados

- `.gitignore`
- `Renviron.example`
- `funciones/configuracion_impala.R`
- `funciones/cargar_datos_com.R`
- `funciones/cargar_datos_levante.R`

## 2026-09-10 - App operativa v2 independiente de la app anterior

Area: app / portabilidad

### Resumen

La app v2 deja de importar utilidades desde `app_operativa/R/datos_app.R` y
queda autocontenida en codigo.

### Decisiones

- Migrar a `app_operativa_v2/R/datos_app.R` solo las seis funciones que tienen
  consumidores activos en la v2.
- No copiar funciones y calculos exclusivos de la interfaz anterior.
- Mantener separada la carga de datos respecto de la UI y los servidores Shiny.

### Archivos relacionados

- `app_operativa_v2/app.R`
- `app_operativa_v2/R/datos_app.R`
- `app_operativa_v2/R/datos_operacion.R`
- `tareas/T030_refactorizar_app_operativa_shiny.md`

## 2026-09-10 - Datos de ejecucion autocontenidos en la app v2

Area: app / datos / portabilidad

### Resumen

La app v2 concentra sus datos de ejecucion en `app_operativa_v2/data/`. Las
publicaciones especificas para la interfaz dejan de mantenerse duplicadas bajo
`data/processed/`.

### Decisiones

- Usar `data/operacional/` para predicciones y controles.
- Usar `data/historico/` para la serie agregada y el detalle por cluster.
- Generar un maestro territorial compacto en `data/referencia/maestro_clusters/`.
- Copiar el shape de barrios a `data/referencia/` porque no se genera en el
  proyecto.
- Mantener los datos excluidos de Git y versionar solamente
  `app_operativa_v2/data/README.md`.
- Hacer que los generadores de datos de la app publiquen directamente en estas
  rutas.

### Validacion

Las pruebas finalizaron con `SESSION_OK`, `HISTORICO_OK`, `DIA_COM_OK`,
`DIA_ZL_OK` y `EVOLUCION_OK`. No se recalcularon modelos ni predicciones.

### Archivos relacionados

- `app_operativa_v2/data/README.md`
- `app_operativa_v2/R/datos_operacion.R`
- `scripts/construir_app_modelos_largo_historico.R`
- `scripts/construir_tablas_historicas_app_v2.R`
- `scripts/construir_maestro_clusters_app_v2.R`
- `tareas/T030_refactorizar_app_operativa_shiny.md`
