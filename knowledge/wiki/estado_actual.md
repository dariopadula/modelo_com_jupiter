# Estado Actual

Ver tambien [[index]], [[tareas_por_tipo]], [[zona_limpia]], [[modelo_zona_limpia]], [[datos_y_leakage]] y [[decisiones]].

## Foco Reciente

El trabajo reciente incluye el frente Zona Limpia y el desarrollo del pronostico
agregado diario de reclamos COM (T028):

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
  de seleccionados/observados por hexagonos. Revision visual aun pendiente;
  ver el cierre 2026-09-02 en T030.
- Historico ampliado el 2026-09-08: puntos de seleccion/observacion y tabla de
  estrategias para COM; evaluacion diaria ZL con seleccion, visitas y problemas;
  y lunes destacados en la serie temporal. La revision visual sigue pendiente.

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

## Restricciones Actuales

- Municipio B tiene fuente Zona Limpia incompleta.
- `Voluminosos` queda fuera del problema comparable principal.
- `202508`, `202509`, `202601` y `202602` se excluyen de analisis ZL por cobertura anomala.
- COM no se usa como target principal ni como feature del modelo ZL puro.
- Las variables climaticas INUMET para `Melilla G3` estan procesadas desde CSV locales con cobertura diaria desde `2025-01-01`.
- La tabla `data/processed/clima/inumet_melilla_g3/clima_inumet_melilla_g3_features_diarias.csv` esta lista para join por `dia`; usa solo clima hasta `D-1`.
- En la evaluacion exploratoria, clima no mejora validacion COM y no mejora las evaluaciones ZL mas exigentes (`random_dia` y temporal), aunque si aparece con importancia y mejora el split random por fila ZL.
- El exceso sobre periodo teorico en modelos COM muestra importancia en XGBoost, pero no mejora de forma robusta validacion/test; no se promueve al baseline.
- Algunos experimentos iniciales de T028 que usan scores COM agregados no son
  OOF de extremo a extremo. El XGBoost candidato mas reciente ya usa A0 OOF en
  entrenamiento, pero sus interacciones siguen siendo evidencia predictiva y
  no deben interpretarse causalmente.
- En la cascada ZL, `operativo_segmento` queda como candidato parsimonioso: no usa territorio nominal y compite bien en temporal; `amplio_actual` queda mejor como diagnostico territorial.
- La app operativa v2 consume `app_operativa_v2/data/operacional/` y sigue sin
  calcular features ni aplicar modelos. COM y ZL se configuran por separado y
  pueden superponerse. El pronostico agregado y los cupos barriales actuales son
  un prototipo retrospectivo basado en salidas experimentales, no un contrato
  operativo diario.
- Sus tablas historicas y referencias territoriales viven en
  `app_operativa_v2/data/historico/` y `app_operativa_v2/data/referencia/`.
  Los generadores publican directamente en esas rutas para evitar copias
  desactualizadas.

## Documentos Clave Para Retomar

1. [[tareas_por_tipo]]
2. [[zona_limpia]]
3. [[modelo_zona_limpia]]
4. [[app_operativa]]
5. `zona_limpia/README.qmd`
6. `zona_limpia/reportes/10_sesgos_seleccion_zona_limpia.qmd`
7. `zona_limpia/reportes/13_modelo_problema_observado_zl.qmd`
8. `documentacion/HITOS.md`
9. `TAREAS.md`
10. `tareas/T028_pronosticar_y_explicar_volumen_diario_reclamos_com.md`
11. [[modelos_agregados_com]]
12. `documentacion/pronostico_diario_clusters_reclamo_com.qmd`
13. `documentacion/resumen_pronostico_diario_com.qmd`
14. `tareas/T030_refactorizar_app_operativa_shiny.md`

## Proximos Pasos Probables

- Completar la fuente faltante de Zona Limpia para Municipio B cuando este disponible; hasta entonces T013 sigue pendiente y la cobertura debe marcarse como incompleta.
- Definir el contrato conceptual conjunto COM/ZL y una visualizacion que muestre coincidencias y divergencias sin crear implicitamente un unico target (T024).
- Definir que accion operativa soportara la app: seleccion de clusters, dibujo de zonas, agrupacion sugerida o recorridos, junto con restricciones y metricas de campo (T025).
- Reevaluar y consolidar el modelo ZL, con una fase parcial usando la fuente actual y una fase definitiva dependiente de Municipio B (T026).
- Fortalecer pruebas de contratos, frescura, leakage y monitoreo multi-modelo antes de ampliar el uso operativo (T027).
- Comparar el modelo ZL puro contra ajustes por propension de visita.
- Profundizar calibracion, lift y estabilidad temporal del modelo ZL puro.
- Si se insiste con clima, evaluar con mas robustez: repeticiones random por dia, sensibilidad sin `mes_calendario` y posibles interacciones/umbrales antes de incorporarlo al baseline.
- Si se insiste con exceso sobre periodo teorico en COM, probar interacciones o reemplazos de variables base, no solo agregarlo encima.
- Para T028, definir el contrato operativo, intervalos predictivos y monitoreo
  antes de promover A0 + XGBoost compacto al scoring o a la app.
- Para T030, revisar la Evolucion temporal de Montevideo implementada el
  2026-09-02 (validacion/test y metricas por periodo). Aun falta definir barrios
  y las metricas territoriales adicionales. Desde el 2026-09-08 incluye puntos
  seleccionados/observados opcionales y una tabla de ocho estrategias con
  precision, cobertura y lift por cluster. El detalle diario COM ya compara distribuciones
  seleccionadas/observadas en hexagonos sincronizados; falta revision visual.
  La Evaluacion del dia ZL agrega un mapa de los seleccionados por el modelo con
  aro gris de seleccion, aro verde para visitas seleccionadas y punto naranja
  de problema, mas las visitas no seleccionadas identificadas con aro azul y una
  tabla comparativa de los cinco criterios ZL. Tambien falta su revision visual.
  Ver la ficha T030.
- Desarrollar mas adelante en T029 la linea inferencial sobre dias de alta
  afectacion territorial; esta tarea no bloquea la integracion predictiva.
- Decidir como tratar Municipio B mientras no este integrada su fuente faltante.
- Profundizar el candidato ZL `operativo_segmento` con repeticiones random por dia, sensibilidad sin variables redundantes y calibracion/lift.
- La referencia anterior conserva tabla de estrategias y mapa categorico.
  En v2 se acordo comparar dos distribuciones territoriales en hexagonos,
  sin exigir coincidencia por cluster; validar esta nueva lectura visual.
- Mantener separadas las lecturas: reclamos COM, problemas observados ZL y ajuste por propension.
- Usar esta nota como punto de arranque, no como reemplazo de la documentacion fuente.
