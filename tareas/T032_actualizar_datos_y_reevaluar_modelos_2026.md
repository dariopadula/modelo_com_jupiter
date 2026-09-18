# T032 - Actualizar datos y reevaluar modelos con test puro 2026

Estado: en proceso
Prioridad: alta
Area: datos / modelos COM / inferencia / Zona Limpia
Fecha de creacion: 2026-09-15

## Contexto

Los nuevos snapshots locales de COM y levantes amplian la cobertura hasta
septiembre de 2026. Esto permite reevaluar los modelos con mas historia y
reservar un test temporal puro que no haya intervenido en la seleccion de
variables, formulas ni candidatos.

El test acordado comprende julio, agosto y los dias 1 a 14 de septiembre de
2026. No se reserva septiembre por separado. La lista exacta de modelos
candidatos se definira despues de construir y revisar la base compartida. Para
la linea inferencial, `q30 + ciclo anual` queda como candidato principal
provisorio.

## Plan Propuesto

1. Auditar fuentes.
2. Actualizar particiones.
3. Construir features compartidas.
4. Congelar splits.
5. Entrenar candidatos.
6. Comparar validacion.
7. Congelar finalistas.
8. Evaluar el test una sola vez.
9. Generar informe.
10. Reentrenar la version operativa.

## Avance 2026-09-15 - Fuentes y particiones

Se completaron los pasos 1 y 2.

- COM nuevo: 2.116.835 filas, desde `2025-01-01 00:15` hasta
  `2026-09-14 17:55`.
- Levantes nuevo: 3.766.042 filas; incluye 2.184 registros del 15 de septiembre,
  que se excluyeron por corresponder a un dia incompleto.
- Enero-marzo de 2026 son identicos entre snapshots.
- COM presenta correcciones retrospectivas en abril; por eso se reemplazaron
  sus particiones de abril-septiembre.
- Levantes de abril es identico; se uso como contexto y se reemplazaron solo
  mayo-septiembre.
- `data/parquet/com_completo/` se actualizo junto con COM para dejar lista la
  fuente de Zona Limpia.
- Las particiones anteriores a los meses objetivo conservaron exactamente su
  cantidad de filas.
- El campo `id` de COM no es una clave global unica: 65 identificadores aparecen
  en mas de una fecha, sin filas completamente duplicadas. Por eso el proceso
  reemplaza particiones mensuales completas en lugar de hacer upsert solo por
  `id`.

Se detecto que el nuevo parquet COM guarda sus fechas como `timestamp` sin zona
y R las mostraba tres horas antes. La actualizacion recupera primero la hora
civil UTC del snapshot y luego la interpreta como hora de Montevideo. El
solapamiento con el snapshot anterior confirma que asi se reproducen las horas
originales.

La fuente climatica no tiene cobertura uniforme hasta el corte: viento llega al
15 de septiembre, mientras temperatura y precipitacion terminan el 13 de julio.
Esto debe resolverse o explicitarse antes de construir features climaticas para
todo el periodo.

Artefactos de control:

- `scripts/auditar_fuentes_actualizacion_202609.R`;
- `scripts/actualizar_particiones_fuentes_202609.R`;
- `outputs/auditoria_actualizacion_202609/`.

No se reconstruyeron features, no se entrenaron modelos y no se calcularon
metricas sobre el nuevo test.

## Avance 2026-09-16 - Features compartidas

Se completo el paso 3 sin definir splits, entrenar modelos ni calcular metricas
del test futuro.

- Se mantuvo fija la referencia de clusters `v2026_05_25`, con 9.168 clusters.
- De 964 posiciones nuevas, 755 quedaron asignadas hasta 50 m, 175 en revision
  entre 50 y 100 m y 34 pendientes por superar 100 m.
- Se reconstruyeron las capas territoriales para los 9.168 clusters. No quedaron
  clusters sin segmento, barrio, CCZ o municipio.
- La base cluster/dia contiene 4.815.357 filas, 622 dias y llega al
  `2026-09-14`.
- Las features historicas cluster/dia quedaron actualizadas en
  `data/processed/modelo_cluster_dia/features_cluster_dia/`.
- Se creo `data/processed/features_compartidas/segmento_dia/`, con 571.954
  filas, 952 segmentos, 62 barrios y cobertura modelable desde `2025-01-03`
  hasta `2026-09-14`.
- Se creo `data/processed/features_compartidas/calendario_dia.parquet`, con los
  622 dias, feriados y ciclo anual.
- Las propensiones q7 y q30 usan reclamos conocidos hasta D-2 y suavizado
  cluster/barrio/global. Tambien se construyeron w7, w30, sus medias y RMS.
- Se actualizo el target de Zona Limpia hasta `2026-09-14`: 988.986 filas
  cluster/dia con algun evento COM o registro ZL.
- Se agrego una validacion reproducible de claves, cobertura, rangos,
  territorio, ausencia de splits/clima y frescura del target ZL.

La capa compartida es normalizada: los modelos cluster/dia usan la historia
dinamica y unen calendario y territorio; los modelos inferenciales usan la
tabla segmento/dia; Zona Limpia agrega su target especifico. No se fuerza una
tabla ancha identica para modelos con unidades y targets distintos.

El clima no se incorporo a la capa comun porque temperatura y precipitacion no
llegan al final del periodo. Queda como union opcional por dia hasta resolver
la cobertura.

Para compactar futuras corridas, el calculo de ventanas historicas se cambio a
sumas acumuladas y desplazamientos, con equivalencia verificada contra la
implementacion anterior. La busqueda de vecinos usa `FNN` cuando esta disponible
y `nabor` como alternativa.

Artefactos principales:

- `scripts/construir_features_compartidas_modelos.R`;
- `scripts/validar_features_compartidas_modelos.R`;
- `data/processed/features_compartidas/`;
- `data/processed/modelo_cluster_dia/features_cluster_dia/`;
- `data/processed/zona_limpia/comparacion_com_zona_limpia_cluster_dia/`.

## Avance 2026-09-16 - Splits congelados

Se completo el paso 4 con el contrato `reevaluacion_2026_v1`:

- contexto historico: `2025-01-01` a `2025-03-31` (90 dias);
- entrenamiento: `2025-04-01` a `2026-03-31` (365 dias);
- validacion: `2026-04-01` a `2026-06-30` (91 dias);
- test puro: `2026-07-01` a `2026-09-14` (76 dias).

El contexto se usa solamente para construir historia y rezagos; no participa en
el ajuste. El entrenamiento contiene un ciclo anual completo e incluye enero y
febrero de 2026. La validacion queda inmediatamente antes del test y es el unico
periodo habilitado para comparar y seleccionar candidatos.

El test queda marcado como `sellado`: no puede usarse para ajustar, seleccionar
modelos ni reportar metricas en esta etapa. Se abrira una sola vez en el paso 8,
despues de congelar los finalistas.

El calendario es comun a COM predictivo, inferencia y Zona Limpia. Cada familia
mantiene sus filtros de universo. En particular, Zona Limpia conserva la
exclusion de los meses con cobertura anomala; esa exclusion no modifica las
fronteras temporales compartidas.

Artefactos:

- `config/splits_reevaluacion_2026.csv`;
- `funciones/splits_temporales.R`;
- `scripts/congelar_splits_reevaluacion_2026.R`;
- `scripts/validar_splits_reevaluacion_2026.R`;
- `data/processed/features_compartidas/calendario_splits_reevaluacion_2026.parquet`;
- `data/processed/features_compartidas/metadata_splits_reevaluacion_2026.csv`.

El contrato se identifica con el checksum MD5
`3bf8a8d9f63693eb194e5e0be045e340`. Cualquier cambio posterior de fechas o
permisos requiere una nueva version del contrato y debe quedar documentado
antes de entrenar.

## Avance 2026-09-16 - Candidatos entrenados

Se completo el paso 5 sin bootstrap, sin metricas de validacion y sin leer el
periodo de test. Los scripts filtran los datos al `2026-06-30` antes de
materializar las bases de entrenamiento.

Candidatos COM cluster/dia:

- `com_logistico_reducido_d2`: referencia operativa actual, 15 features y
  regresion logistica global;
- `com_xgboost_d2`: benchmark flexible con las mismas 15 features y 120 rondas
  fijas.

Ambos usan 2.933.423 filas de entrenamiento y generan predicciones para 715.055
filas de validacion.

Candidatos de pronostico agregado e inferencia:

- `pronostico_a0`: `mgcv::bam()` binomial con dia de semana y efectos
  penalizados de barrio y segmento;
- `pronostico_a0_xgb_compacto_q30`: A0 mas una correccion XGBoost de 57 rondas
  con tiempo desde levante, `rms_q_7`, `rms_w_7`, `q7-q30` y feriado;
- `inferencial_q30_ciclo`: `mgcv::bam()` con calendario, ciclo anual, densidad,
  NBI, atraso, q30, cambio q7-q30, interacciones acordadas y efectos penalizados
  de barrio y segmento.

Estos modelos usan 342.565 filas segmento/dia de entrenamiento y generan
predicciones sobre 84.295 filas de validacion. El candidato inferencial se
ajusto sin bootstrap.

Candidatos Zona Limpia:

- `zl_operativo_segmento`: 36 features numericas operativas, censales y de
  calendario;
- `zl_amplio_actual`: 52 features numericas y 3 territoriales categoricas.

Ambos usan XGBoost con 250 rondas fijas, 75.490 visitas efectivas de
entrenamiento y 108.854 de validacion. Se mantienen fuera los meses de cobertura
anomala y los registros `Voluminosos`.

Artefactos:

- `scripts/entrenar_candidatos_com_cluster_reevaluacion_2026.R`;
- `scripts/entrenar_candidatos_agregados_inferencia_reevaluacion_2026.R`;
- `zona_limpia/15_entrenar_candidatos_zl_reevaluacion_2026.R`;
- `scripts/validar_candidatos_reevaluacion_2026.R`;
- `data/processed/modelos/reevaluacion_2026/`;
- `outputs/reevaluacion_2026/inventario_candidatos.csv`.

La comparacion de desempeno queda reservada para el paso 6 y usara solamente
las predicciones de validacion ya congeladas.

## Avance 2026-09-16 - Comparacion en validacion

Se completo el paso 6 usando exclusivamente abril-junio de 2026. No se leyo el
test, no se reentrenaron candidatos y no se ejecuto bootstrap.

COM cluster/dia:

- `com_xgboost_d2` alcanza AUC `0,7752`, logloss `0,2944` y Brier `0,0862`;
- `com_logistico_reducido_d2` alcanza AUC `0,7667`, logloss `0,2980` y Brier
  `0,0870`;
- XGBoost mejora las tres metricas globales y el AUC en cada uno de los tres
  meses. En el top diario del 10 %, eleva la captura media de `32,30 %` a
  `32,80 %` y el lift medio de `3,23` a `3,28`.

Pronostico agregado e inferencia:

- `pronostico_a0_xgb_compacto_q30` obtiene RMSE `149,70`, MAE `121,77`, sesgo
  `-43,41` y correlacion `0,681`;
- `pronostico_a0` obtiene RMSE `164,44`, MAE `130,04`, sesgo `-65,87` y
  correlacion `0,626`;
- la correccion compacta reduce el RMSE `9,0 %` y el MAE `6,4 %` frente a A0,
  y mejora el RMSE en abril, mayo y junio;
- `inferencial_q30_ciclo` obtiene RMSE `187,85`, MAE `155,75`, sesgo `-125,24`
  y correlacion `0,690`. Conserva senal para explicar variacion, pero no compite
  con el candidato predictivo en nivel ni error.

Zona Limpia:

- `zl_amplio_actual` alcanza AUC `0,6263`, logloss `0,6745` y Brier `0,2408`;
- `zl_operativo_segmento` alcanza AUC `0,6065`, logloss `0,6826` y Brier
  `0,2446`;
- el modelo amplio mejora las tres metricas y el AUC en cada mes. En el top
  diario del 10 %, eleva la precision media de `70,18 %` a `74,05 %` y el lift
  medio de `1,30` a `1,37`;
- ambos candidatos subestiman la prevalencia observada (`52,67 %`): sus
  probabilidades medias son `46,33 %` y `46,52 %`. La calibracion debe formar
  parte de la decision operativa posterior.

La comparacion respalda llevar al paso 7 a XGBoost COM, A0 mas XGBoost compacto
y el modelo ZL amplio como mejores opciones predictivas. Las referencias
parsimoniosas se conservan para decidir el costo de complejidad y calibracion.
El modelo inferencial se juzga ademas por claridad y estabilidad de efectos, no
solo por error predictivo.

Artefactos:

- `scripts/comparar_validacion_candidatos_reevaluacion_2026.R`;
- `scripts/validar_comparacion_validacion_reevaluacion_2026.R`;
- `outputs/reevaluacion_2026/validacion/`.

## Avance 2026-09-16 - Informe preliminar sin abrir el test

Se genero un informe interno con los resultados disponibles de entrenamiento y
validacion, sin congelar finalistas ni ejecutar el paso 8. El eje temporal marca
el test entre julio y el 14 de septiembre, pero deja esa franja vacia: no se
muestran observaciones, predicciones ni metricas del periodo reservado.

El informe incluye:

- comparacion del logistico reducido y XGBoost COM con metricas probabilisticas,
  estabilidad mensual y lift diario;
- serie diaria completa hasta validacion y comparacion de suma de scores, A0 y
  A0 mas correccion XGBoost durante abril-junio;
- parametros y metricas del modelo inferencial, con intervalos convencionales y
  sin bootstrap;
- comparacion ZL, dejando el candidato operativo sin territorio nominal como
  linea principal y `amplio_actual` como benchmark territorial;
- advertencia explicita de que ningun modelo ZL esta validado para Municipio B
  y de que el target es problema condicionado a una visita efectiva.

Artefactos:

- `documentacion/informe_preliminar_validacion_modelos_2026.qmd`;
- `documentacion/informe_preliminar_validacion_modelos_2026.html`;
- `scripts/validar_informe_preliminar_validacion_2026.R`.

La seleccion de finalistas permanece abierta. Los pasos 7 y 8 quedan pospuestos
hasta que la especificacion resulte satisfactoria.

## Avance 2026-09-16 - Demografia en el candidato ZL operativo

Se agrego `zl_operativo_segmento_demografia`, que incorpora
`poblacion_segmento`, `hogares_segmento` y `viviendas_segmento` al candidato
operativo. Conserva XGBoost, 250 rondas, el mismo train y la misma validacion;
no usa municipio, CCZ, barrio, mes calendario ni agregados de barrio/CCZ.

Resultados de validacion:

- AUC `0,6107` frente a `0,6065` del operativo basico;
- logloss `0,6816` frente a `0,6826`;
- Brier `0,2441` frente a `0,2446`;
- mejora de AUC en abril, mayo y junio;
- en el top diario del 10 %, precision media `70,61 %` frente a `70,18 %` y
  lift `1,303` frente a `1,296`.

La ganancia es pequena pero consistente. Este candidato pasa a ser la opcion
operativa preliminar mas transportable; `amplio_actual` conserva mejor AUC, pero
queda como benchmark territorial por su dependencia de ubicacion explicita y
la falta de cobertura adecuada de Municipio B. El test no fue leido.

## Criterio De Finalizacion

La tarea finaliza cuando los datos y features compartidos quedan actualizados,
los splits y candidatos se documentan antes del entrenamiento, los finalistas
se eligen solo con validacion, el test se evalua una vez y se genera la version
operativa junto con su informe.

## Notas Y Decisiones Pendientes

- Congelar los finalistas y sus reglas de lectura en el paso 7 antes de abrir el
  test.
- Resolver la cobertura incompleta de temperatura y precipitacion para
  julio-septiembre antes de decidir si clima integra la base compartida.
