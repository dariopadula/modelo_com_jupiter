# Wiki Del Proyecto

Esta wiki es una capa de navegacion sobre la documentacion existente de `modelo_com_jupiter`. No copia las fuentes: sintetiza arquitectura, decisiones, componentes y conceptos para retomar el proyecto con menor costo cognitivo.

## Por Donde Empezar

- Para retomar una sesion rapidamente: [[estado_actual]].
- Para entender el proyecto de punta a punta: [[arquitectura]], [[componentes]] y [[glosario]].
- Para ubicar documentacion fuente: [[mapa_documental]].
- Para decidir que leer o modificar segun la tarea: [[tareas_por_tipo]].
- Para modificar arquitectura o flujo de datos: [[arquitectura]], [[componentes]], [[datos_y_leakage]], fuente `documentacion/flujo_datos.qmd` y `README.qmd`.
- Para modificar modelos COM: [[modelos_com]], [[datos_y_leakage]], fuente `documentacion/modelos.qmd`, `documentacion/modelos_utils.qmd` y `documentacion/diagnostico_variables_modelo.qmd`.
- Para consultar rapidamente los modelos agregados COM ya probados: [[modelos_agregados_com]].
- Para trabajar en scoring operativo o app: [[scoring_operativo]], [[app_operativa]], [[flujo_trabajo]], fuente `documentacion/proceso_scoring_operativo.qmd` y `app_operativa/README.md`.
- Para trabajar con Zona Limpia: [[zona_limpia]], [[datos_y_leakage]], fuente `zona_limpia/README.qmd` y reportes `zona_limpia/reportes/*.qmd`.
- Para trabajar con el modelo de problema observado ZL: [[modelo_zona_limpia]], [[zona_limpia]] y reporte `zona_limpia/reportes/13_modelo_problema_observado_zl.qmd`.
- Para agregar una nueva funcionalidad: [[tareas_por_tipo]], [[flujo_trabajo]], [[componentes]], indice `TAREAS.md` y ficha especifica en `tareas/`.
- Para corregir un bug: [[tareas_por_tipo]], [[flujo_trabajo]], [[mapa_documental]] y el script/documento especifico del componente afectado.
- Para revisar decisiones historicas: [[decisiones]] y `documentacion/HITOS.md`.

## Mapa De La Wiki

- [[mapa_documental]]: lista de documentos fuente, proposito y momento de consulta.
- [[estado_actual]]: foco actual, restricciones y proximos pasos probables.
- [[arquitectura]]: vision sintetica del sistema y sus flujos.
- [[componentes]]: modulos, scripts principales, responsabilidades y dependencias.
- [[flujo_trabajo]]: forma de trabajo, documentacion obligatoria y reglas operativas.
- [[decisiones]]: decisiones inferidas de la documentacion actual.
- [[glosario]]: conceptos y nombres frecuentes.
- [[tareas_por_tipo]]: guia operativa para saber que leer, tocar y documentar por tipo de trabajo.
- [[datos_y_leakage]]: reglas de datos, cortes temporales y riesgos de leakage.
- [[modelos_com]]: guia de trabajo para modelos de reclamos COM.
- [[modelos_agregados_com]]: inventario sintetico de modelos para pronosticar el volumen diario COM.
- [[modelo_zona_limpia]]: ficha de orientacion del modelo de problema observado Zona Limpia.
- [[scoring_operativo]]: guia de trabajo para scoring diario y app.
- [[app_operativa]]: contrato actual de la app Shiny y convivencia de scores COM/ZL.
- [[zona_limpia]]: guia de trabajo para analisis y modelos Zona Limpia.

## Principio De Uso

Si una nota de la wiki contradice una fuente primaria, la fuente primaria manda. La wiki debe actualizarse como sintesis, no como nueva fuente independiente de verdad.
