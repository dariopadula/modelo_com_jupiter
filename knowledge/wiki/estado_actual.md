# Estado Actual

Ver tambien [[index]], [[tareas_por_tipo]], [[zona_limpia]], [[modelo_zona_limpia]], [[datos_y_leakage]] y [[decisiones]].

## Foco Reciente

El trabajo reciente incluye el frente Zona Limpia, el desarrollo del pronostico
agregado diario de reclamos COM (T028) y su linea inferencial (T029):

- comparacion diaria entre seleccion efectiva de ZL y modelo COM a igual N;
- diagnostico de sesgos territoriales y de criterio asociado a levantes;
- correspondencia entre problemas observados por ZL y reclamos COM;
- ajuste exploratorio por propension de visita;
- primer baseline de modelo para problema observado ZL;
- descarga inicial de variables climaticas INUMET para `Melilla G3`;
- evaluacion exploratoria de variables climaticas en XGBoost COM y XGBoost ZL;
- evaluacion exploratoria de exceso sobre periodo teorico en modelos COM;
- cascada parsimoniosa de features para modelo Zona Limpia;
- integracion inicial de scores COM y ZL en app operativa mediante tabla larga multi-modelo.
- comparación de la suma de scores con modelos barrio/día y CCZ/día para
  anticipar cuántos clusters tendrán reclamo;
- exploración de variables de atraso, efectos territoriales y pendientes
  aleatorias por barrio.
- cierre de la etapa predictiva con A0 y una correccion XGBoost compacta de
  cinco variables.
- modelo inferencial final a nivel segmento/dia con `mgcv::bam()` y bootstrap
  conjunto de 50 replicas por semanas y segmentos completos.
- prototipo retrospectivo en la app con pronostico agregado, afectacion por
  barrio, estrategias de seleccion COM y ZL independientes, capas superpuestas
  y comparacion historica de estrategias.
- decision de detener parches visuales y planificar un refactor modular de la
  app operativa en T030, conservando la version actual como referencia.
- primera version modular de `Operacion del dia` en `app_operativa_v2/`, con
  mapa principal, capas COM/ZL independientes, seleccion por umbral y analisis
  de scores.
- capa historica liviana publicada para T030: serie agregada COM y detalle por
  cluster particionado por fecha/modelo.
- Historico v2 implementado: Evolucion temporal COM y distribucion territorial
  de seleccionados/observados por hexagonos.
- Historico ampliado el 2026-09-08: puntos de seleccion/observacion y tabla de
  estrategias para COM; evaluacion diaria ZL con seleccion, visitas y problemas;
  y lunes destacados en la serie temporal.
- preparacion del flujo local -> Git -> Cloudera: configuracion sensible fuera
  del codigo, lista de inclusion para el repositorio publico y datos de la app
  concentrados bajo `app_operativa_v2/data/`.
- auditoria de los nuevos snapshots, actualizacion incremental de COM, COM
  ampliado y levantes, reconstruccion de las features compartidas hasta
  `2026-09-14`, y entrenamiento y comparacion de candidatos solo en validacion;
  los finalistas siguen abiertos y el test permanece sellado.
- auditoria territorial de Zona Limpia: el campo `municipio` original esta
  incompleto, pero la asignacion espacial del cluster recupera visitas del
  Municipio B desde `2025-09-11` y cobertura diaria intensa desde `2026-05-14`.

## Lectura Actual

El modelo COM prioriza reclamos COM, pero no recupera sistematicamente problemas observados solo por Zona Limpia.

El baseline de modelo ZL puro usa como target principal `hay_zl_problema_comparable`. Muestra senal, pero todavia es exploratorio:

- AUC random por fila cercano a `0,68`;
- AUC random por dia cercano a `0,68` en validacion y `0,66` en test;
- AUC test random por dia repetido entre aproximadamente `0,663` y `0,681`;
- AUC temporal cercano a `0,60`;
- no esta listo como reemplazo operativo.

La evidencia actual sugiere subreclamo COM frente a problemas observados por ZL, pero no debe generalizarse sin explicitar sesgo de seleccion.

Para T028, A0 queda como referencia estructural y E1 como referencia dinamica
anterior. La etapa predictiva se cierra con XGBoost como correccion de A0
mediante `base_margin`. La version compacta seleccionada usa cinco variables:
tiempo medio desde levante, `rms_q_7`, `rms_w_7`, `q7 - q60` y feriado. Obtiene
RMSE combinado 156,0, correlacion 0,691 y reproduce 83,0 % de la variabilidad.
La seleccion cierra la comparacion experimental, pero todavia no implica su
promocion al scoring ni a la app.

Para T029 queda fijada como referencia inferencial actual una especificacion
segmento/dia con calendario, estructura territorial, atraso, propension
historica y cambio reciente. Su RMSE combinado es 153,79. En el bootstrap
conjunto, densidad y NBI conservan el signo en las 50 replicas; la interaccion
entre atraso y cambio reciente incluye cero y no se interpreta como un efecto
estable. El alcance es asociativo y se limita a los barrios observados.

Para la nueva reevaluacion, `q30 + ciclo anual` queda como candidato inferencial
principal provisorio. El test puro previsto comprende julio, agosto y los dias
1 a 14 de septiembre de 2026. Las features compartidas ya llegan al
`2026-09-14`: la historia cluster/dia, el calendario, el territorio, la tabla
segmento/dia y el target ZL usan el mismo corte. El split
`reevaluacion_2026_v1` ya esta congelado: train `2025-04-01` a `2026-03-31`,
validacion `2026-04-01` a `2026-06-30` y test sellado `2026-07-01` a
`2026-09-14`. Los candidatos fueron entrenados sin bootstrap y comparados
solo en validacion. XGBoost COM mejora al logistico reducido (AUC `0,7752`
contra `0,7667`); A0 mas XGBoost compacto mejora a A0 (RMSE `149,70` contra
`164,44`); y el modelo ZL amplio mejora al operativo por segmento (AUC `0,6263`
contra `0,6065`). Las ventajas aparecen en los tres meses. El inferencial
conserva correlacion, pero subestima el nivel. El test sigue sellado hasta
congelar los finalistas en el paso 7.

En una prueba adicional, q7 sola reemplaza q30 y `q7-q30`: aumenta la
correlacion a `0,710`, pero empeora RMSE, MAE y sesgo en validacion y conserva
coeficiente negativo. No se agrega q7 al modelo vigente porque q7, q30 y su
diferencia son linealmente dependientes. La referencia provisoria no cambia.

Agregar por separado `(q7-q30)^2` o `q30 * (q7-q30)` mejora el RMSE de la
referencia inferencial de `187,85` a `184,57` y `183,82`, respectivamente, con
mejora en los tres meses. Las dos variantes producen predicciones casi
identicas (`r = 0,9999`), de modo que queda pendiente elegir una forma
interpretable; no se promovio ninguna ni se abrio el test.

La variante cuadratica sin `atraso * (q7-q30)` obtiene RMSE `185,49`: conserva
parte de la mejora y simplifica la lectura, aunque pierde `0,92` puntos frente
al cuadratico completo. Mejora abril y junio, pero no mayo. Esta alternativa
queda abierta para una decision sustantiva posterior.

El cuadratico completo ya tiene un bootstrap conjunto de 50 replicas por
semanas y segmentos. La curvatura queda positiva en 50/50; el cambio lineal
cruza cero y `atraso * cambio` queda negativo en 50/50. Densidad es negativa y
estable, mientras NBI cruza cero. Los errores bootstrap multiplican por entre
`2,2` y `4,6` los convencionales. El test sigue sellado y la especificacion
inferencial aun no esta congelada.

La comparacion quedo consolidada en un informe preliminar que muestra solo
entrenamiento y validacion. La seleccion de finalistas permanece abierta y el
test se representa como una franja vacia, sin observaciones, predicciones ni
metricas. Para ZL, `operativo_segmento_demografia` agrega poblacion, hogares y
viviendas sin territorio nominal y mejora el AUC a `0,6107`; queda como
candidato principal mas transportable. `amplio_actual` permanece como benchmark
territorial por el riesgo de aprender patrones de seleccion geografica. Los
analisis que excluyeron B deben recalcularse con municipio asignado por cluster
antes de reinterpretarlos.

## Restricciones Actuales

- El campo `municipio` original de Zona Limpia esta incompleto; los resumenes
  territoriales deben usar el municipio asignado espacialmente al cluster.
- `Voluminosos` queda fuera del problema comparable principal.
- `202508`, `202509`, `202601` y `202602` se excluyen de analisis ZL por cobertura anomala.
- COM no se usa como target principal ni como feature del modelo ZL puro.
- Las variables climaticas INUMET para `Melilla G3` estan procesadas desde CSV locales con cobertura diaria desde `2025-01-01`.
- La fuente horaria no llega de forma uniforme al nuevo corte: temperatura y
  precipitacion terminan el `2026-07-13`, mientras viento llega al
  `2026-09-15`. Esto debe resolverse antes de construir una base climatica comun
  para el nuevo test.
- La tabla `data/processed/clima/inumet_melilla_g3/clima_inumet_melilla_g3_features_diarias.csv` esta lista para join por `dia`; usa solo clima hasta `D-1`.
- En la evaluacion exploratoria, clima no mejora validacion COM y no mejora las evaluaciones ZL mas exigentes (`random_dia` y temporal), aunque si aparece con importancia y mejora el split random por fila ZL.
- El exceso sobre periodo teorico en modelos COM muestra importancia en XGBoost, pero no mejora de forma robusta validacion/test; no se promueve al baseline.
- Algunos experimentos iniciales de T028 que usan scores COM agregados no son
  OOF de extremo a extremo. El XGBoost candidato mas reciente ya usa A0 OOF en
  entrenamiento, pero sus interacciones siguen siendo evidencia predictiva y
  no deben interpretarse causalmente.
- En la cascada ZL, `operativo_segmento_demografia` queda como candidato
  operativo preliminar: mejora de forma pequena pero consistente sin territorio
  nominal; `amplio_actual` queda como diagnostico territorial.
- La app operativa v2 consume `app_operativa_v2/data/operacional/` y sigue sin
  calcular features ni aplicar modelos. COM y ZL se configuran por separado y
  pueden superponerse. El pronostico agregado y los cupos barriales actuales son
  un prototipo retrospectivo basado en salidas experimentales, no un contrato
  operativo diario.
- Sus tablas historicas y referencias territoriales viven en
  `app_operativa_v2/data/historico/` y `app_operativa_v2/data/referencia/`.
  Los generadores publican directamente en esas rutas para evitar copias
  desactualizadas.
- El repositorio publico esta operativo y la app v2 se encuentra desplegada en
  Cloudera con los datos cargados por fuera de Git. `HISTORICO_OK` y
  `SESSION_OK` pasaron en destino; la interfaz y los mapas se verificaron en
  navegador. T031 esta finalizada.

## Documentos Clave Para Retomar

1. [[tareas_por_tipo]]
2. [[zona_limpia]]
3. [[modelo_zona_limpia]]
4. [[app_operativa]]
5. `zona_limpia/README.qmd`
6. `zona_limpia/reportes/10_sesgos_seleccion_zona_limpia.qmd`
7. `zona_limpia/reportes/13_modelo_problema_observado_zl.qmd`
8. `zona_limpia/reportes/14_cobertura_municipal_zona_limpia.qmd`
9. `documentacion/HITOS.md`
10. `TAREAS.md`
11. `tareas/T028_pronosticar_y_explicar_volumen_diario_reclamos_com.md`
12. [[modelos_agregados_com]]
13. `documentacion/pronostico_diario_clusters_reclamo_com.qmd`
14. `documentacion/resumen_pronostico_diario_com.qmd`
15. `tareas/T029_explicar_dias_alta_afectacion_territorial_com.md`
16. `documentacion/informe_diagnostico_temporal_modelo_inferencial_com.qmd`
17. `tareas/T030_refactorizar_app_operativa_shiny.md`
18. `tareas/T031_publicar_proyecto_y_replicar_en_cloudera.md`
19. `tareas/T032_actualizar_datos_y_reevaluar_modelos_2026.md`

## Proximos Pasos Probables

- Recalcular los diagnosticos historicos de Zona Limpia que excluyeron Municipio
  B, usando el municipio asignado espacialmente al cluster (T013).
- Definir el contrato conceptual conjunto COM/ZL y una visualizacion que muestre coincidencias y divergencias sin crear implicitamente un unico target (T024).
- Definir que accion operativa soportara la app: seleccion de clusters, dibujo de zonas, agrupacion sugerida o recorridos, junto con restricciones y metricas de campo (T025).
- Reevaluar y consolidar el modelo ZL despues de auditar el efecto de reincorporar
  Municipio B mediante la asignacion espacial (T026).
- Fortalecer pruebas de contratos, frescura, leakage y monitoreo multi-modelo antes de ampliar el uso operativo (T027).
- Comparar el modelo ZL puro contra ajustes por propension de visita.
- Profundizar calibracion, lift y estabilidad temporal del modelo ZL puro.
- Para T029, conservar `q30 + ciclo anual` como candidato inferencial provisorio.
  La exploracion agregada con clima `D-1` no produjo una mejora estable y el
  viento maximo mantuvo una asociacion negativa dificil de sostener. No repetir
  bootstrap ni ampliar esa especificacion hasta completar la cobertura de
  temperatura y precipitacion y congelar el nuevo diseno temporal.
- Si se insiste con exceso sobre periodo teorico en COM, probar interacciones o reemplazos de variables base, no solo agregarlo encima.
- Para T028, definir el contrato operativo, intervalos predictivos y monitoreo
  antes de promover A0 + XGBoost compacto al scoring o a la app.
- Para T032, revisar el informe preliminar y continuar explorando las
  especificaciones necesarias antes de congelar finalistas. Mantener sellado el
  test hasta una decision posterior.
- Para T030, continuar la Evolucion temporal de Montevideo implementada el
  2026-09-02 (validacion/test y metricas por periodo). Aun falta definir barrios
  y las metricas territoriales adicionales. Desde el 2026-09-08 incluye puntos
  seleccionados/observados opcionales y una tabla de ocho estrategias con
  precision, cobertura y lift por cluster. El detalle diario COM ya compara distribuciones
  seleccionadas/observadas en hexagonos sincronizados.
  La Evaluacion del dia ZL agrega un mapa de los seleccionados por el modelo con
  aro gris de seleccion, aro verde para visitas seleccionadas y punto naranja
  de problema, mas las visitas no seleccionadas identificadas con aro azul y una
  tabla comparativa de los cinco criterios ZL. El arranque, la interfaz y los
  mapas se verificaron en Cloudera; ver la ficha T030.
- Para T029, acordar la presentacion sustantiva de los efectos y fijar cualquier
  nueva especificacion climatica antes de repetir el bootstrap.
- Determinar que resultados y modelos ZL historicos cambian al reincorporar
  Municipio B con el criterio espacial corregido.
- Profundizar `operativo_segmento_demografia` con repeticiones random por dia,
  sensibilidad sin variables redundantes y calibracion/lift.
- La referencia anterior conserva tabla de estrategias y mapa categorico.
  En v2 se acordo comparar dos distribuciones territoriales en hexagonos,
  sin exigir coincidencia por cluster; validar esta nueva lectura visual.
- Mantener separadas las lecturas: reclamos COM, problemas observados ZL y ajuste por propension.
- Usar esta nota como punto de arranque, no como reemplazo de la documentacion fuente.
