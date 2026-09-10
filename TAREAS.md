# Indice De Tareas

Este archivo es el punto de entrada al backlog. Cada tarea tiene su ficha completa
en `tareas/`; abrir solo las fichas necesarias para el trabajo actual.

## Estados Permitidos

- `pendiente`: acordada y todavia no iniciada.
- `en proceso`: trabajo activo.
- `bloqueada`: no puede avanzar hasta resolver una dependencia explicita.
- `finalizada`: criterio de finalizacion cumplido.
- `descartada`: se decidio no continuar; la ficha conserva el motivo.

## En proceso

- [T028 - Pronosticar el volumen diario de clusters con reclamo COM](tareas/T028_pronosticar_y_explicar_volumen_diario_reclamos_com.md) — prioridad alta. Validar el candidato predictivo agregado, definir su contrato operativo e integrarlo en la app sin mezclarlo con el ranking espacial.
- [T030 - Refactorizar la app operativa Shiny](tareas/T030_refactorizar_app_operativa_shiny.md) - prioridad alta. Evaluaciones diarias COM y ZL implementadas; revisar visualmente Historico y sincronizacion, luego definir metricas territoriales adicionales.

## Pendientes

- [T029 - Explicar los dias con alta afectacion territorial COM](tareas/T029_explicar_dias_alta_afectacion_territorial_com.md) — prioridad media. Desarrollar una linea inferencial reproducible e interpretable, separada del modelo predictivo y sin lenguaje causal no sustentado.
- [T002 - Comparacion territorial historica en la app](tareas/T002_comparacion_territorial_historica_en_la_app.md) — prioridad alta. Validar el prototipo de mapa categorico y tabla de estrategias contra resultados observados; se descarto la comparacion de tres mapas hexagonales.
- [T003 - Evaluar criterio de contenedores activos recientes](tareas/T003_evaluar_criterio_de_contenedores_activos_recientes.md) — prioridad media. Se observo que en predicciones aparecen clusters con tiempos desde ultimo levante mayores a 6 o 7 dias.
- [T007 - Explorar sesgo geografico y demografico de no reclamo COM](tareas/T007_explorar_sesgo_geografico_y_demografico_de_no_reclamo_com.md) — prioridad media. La comparacion entre Zona Limpia y COM abre una pregunta mas amplia: COM puede subrepresentar problemas en zonas donde hay menor propension a reclamar, diferencias culturales so...
- [T013 - Diagnosticar cobertura territorial y fuente faltante de Zona Limpia](tareas/T013_diagnosticar_cobertura_territorial_y_fuente_faltante_de_zona_limpia.md) — prioridad alta. El analisis preliminar por municipio, CCZ y barrio muestra diferencias fuertes de cobertura territorial de Zona Limpia.
- [T024 - Definir contrato conceptual y visual conjunto COM-Zona Limpia](tareas/T024_definir_contrato_conceptual_y_visual_conjunto_com_zona_limpia.md) — prioridad alta. Validar el prototipo de capas COM/ZL superpuestas y documentar como decidir sin mezclar targets ni forzar reglas simetricas.
- [T025 - Definir apoyo operativo para zonas y recorridos en el mapa](tareas/T025_definir_apoyo_operativo_para_zonas_y_recorridos_en_el_mapa.md) — prioridad alta. Una posibilidad es que la persona usuaria observe ambos scores y disene zonas para recorrer.
- [T026 - Reevaluar y consolidar el modelo Zona Limpia](tareas/T026_reevaluar_y_consolidar_el_modelo_zona_limpia.md) — prioridad alta. `operativo_segmento` muestra senal, pero el desempeno temporal es menor que en particiones aleatorias y Municipio B sigue incompleto.
- [T027 - Fortalecer pruebas, contratos y monitoreo operativo](tareas/T027_fortalecer_pruebas_contratos_y_monitoreo_operativo.md) — prioridad media. Existen validaciones puntuales, pero no una suite central para todo el pipeline multi-modelo.

## Finalizadas

- [T001 - Organizar memoria estable del proyecto](tareas/T001_organizar_memoria_estable_del_proyecto.md) — prioridad alta. El proyecto todavia no esta formalmente versionado y se viene trabajando con bastante contexto acumulado en sesiones de Codex.
- [T004 - Base ampliada COM para analisis Zona Limpia](tareas/T004_base_ampliada_com_para_analisis_zona_limpia.md) — prioridad alta. Los datos COM incluyen incidentes que comienzan con `Zona limpia`.
- [T005 - Primer descriptivo de Zona Limpia](tareas/T005_primer_descriptivo_de_zona_limpia.md) — prioridad alta. Luego de generar `data/parquet/com_completo/` y definir el mapeo canonico de etiquetas Zona Limpia, se necesita una primera lectura agregada para entender composicion, visitas e...
- [T006 - Comparacion COM vs Zona Limpia por cluster-dia](tareas/T006_comparacion_com_vs_zona_limpia_por_cluster_dia.md) — prioridad alta. Se quiere comparar, dia a dia y a nivel `cluster_id`, los reclamos COM asignados al target del modelo con los resultados reportados por Zona Limpia.
- [T008 - Integrar variables territoriales censales a clusters](tareas/T008_integrar_variables_territoriales_censales_a_clusters.md) — prioridad alta. Para comparar modelos basados en COM y Zona Limpia, y para estudiar sesgos de reclamo o seleccion de visita, se necesita una capa territorial fija por `cluster_id`.
- [T009 - Evaluar scores COM frente a problemas observados por Zona Limpia](tareas/T009_evaluar_scores_com_frente_a_problemas_observados_por_zona_limpia.md) — prioridad alta. Antes de entrenar un modelo especifico con target Zona Limpia, interesa evaluar si los scores COM ya disponibles capturan parte de los problemas reales observados por Zona Limpi...
- [T010 - Comparar seleccion diaria Zona Limpia vs modelo a igual cantidad de visitas](tareas/T010_comparar_seleccion_diaria_zona_limpia_vs_modelo_a_igual_cantidad_de_visitas.md) — prioridad alta. Se necesita una comparacion comunicable entre la seleccion efectiva de puntos visitados por Zona Limpia y una seleccion alternativa sugerida por el modelo.
- [T011 - Reporte visual Zona Limpia vs modelo](tareas/T011_reporte_visual_zona_limpia_vs_modelo.md) — prioridad alta. Luego de construir la comparacion diaria a igual N, se necesita una pieza visual para comunicar que Zona Limpia y el modelo optimizan objetivos distintos: problemas observados e...
- [T012 - Primer modelo de problema observado Zona Limpia](tareas/T012_primer_modelo_de_problema_observado_zona_limpia.md) — prioridad alta. La comparacion entre seleccion Zona Limpia y modelo COM mostro que el modelo COM sirve para priorizar reclamos, pero no necesariamente problemas observados en campo.
- [T014 - Evaluar criterio de levante en seleccion Zona Limpia](tareas/T014_evaluar_criterio_de_levante_en_seleccion_zona_limpia.md) — prioridad alta. Existe la hipotesis de que la seleccion de Zona Limpia usa, directa o indirectamente, un criterio asociado al atraso respecto al periodo teorico de levante.
- [T015 - Reporte de sesgos de seleccion Zona Limpia](tareas/T015_reporte_de_sesgos_de_seleccion_zona_limpia.md) — prioridad alta. Las visitas de Zona Limpia no son una muestra uniforme.
- [T016 - Diagnosticar correspondencia territorial entre COM y problemas Zona Limpia](tareas/T016_diagnosticar_correspondencia_territorial_entre_com_y_problemas_zona_limpia.md) — prioridad alta. Se necesita medir en que territorios los problemas observados por Zona Limpia se convierten o no en reclamos COM.
- [T017 - Ajustar correspondencia COM-Zona Limpia por propension de visita](tareas/T017_ajustar_correspondencia_com_zona_limpia_por_propension_de_visita.md) — prioridad alta. La correspondencia cruda no puede generalizarse directamente porque los lugares visitados por Zona Limpia no son una muestra aleatoria.
- [T018 - Descargar variables climaticas INUMET para Zona Limpia](tareas/T018_descargar_variables_climaticas_inumet_para_zona_limpia.md) — prioridad media. Se requieren variables ex ante de precipitacion y temperatura para explorar mejoras del modelo de problema observado Zona Limpia.
- [T019 - Evaluar variables climaticas en modelos COM y Zona Limpia](tareas/T019_evaluar_variables_climaticas_en_modelos_com_y_zona_limpia.md) — prioridad media. Luego de construir features climaticas se quiere medir su aporte en los objetivos COM y Zona Limpia sin reemplazar los baselines.
- [T020 - Evaluar exceso sobre periodo teorico en modelos COM](tareas/T020_evaluar_exceso_sobre_periodo_teorico_en_modelos_com.md) — prioridad media. Se evalua si resumir cuanto excede el tiempo desde ultimo levante al periodo teorico mejora el ranking COM.
- [T021 - Evaluar cascada parsimoniosa de features para modelo Zona Limpia](tareas/T021_evaluar_cascada_parsimoniosa_de_features_para_modelo_zona_limpia.md) — prioridad alta. El modelo ZL amplio combina muchas capas territoriales y puede capturar seleccion o cobertura.
- [T022 - Integrar scores COM y Zona Limpia en app operativa](tareas/T022_integrar_scores_com_y_zona_limpia_en_app_operativa.md) — prioridad alta. La app necesita mostrar dos lecturas distintas sin recalcular modelos: riesgo de reclamo COM y riesgo exploratorio de problema observado ZL.
- [T023 - Evaluar territorialmente el modelo COM por CCZ](tareas/T023_evaluar_territorialmente_el_modelo_com_por_ccz.md) — prioridad alta. Se necesita auditar discriminacion, calibracion y utilidad operativa del modelo COM global entre CCZ sin entrenar modelos territoriales ni usar CCZ como predictor.

## Regla De Mantenimiento

Al crear o cambiar una tarea, actualizar su ficha y esta linea de indice. No
copiar el contexto, plan ni notas completas en este archivo.
