# Mapa Documental

Ver tambien [[index]], [[tareas_por_tipo]], [[arquitectura]], [[componentes]] y [[decisiones]].

## Documentacion Principal

| Documento | Ubicacion | Proposito | Consultar cuando |
|---|---|---|---|
| README del proyecto | `README.qmd` | Mapa operativo general: objetivo, flujo de datos, orden de ejecucion y salidas principales. | Se necesita entender el proyecto completo o ubicar una salida del pipeline. |
| Reglas de trabajo | `AGENTS.md` | Define como trabajar con Codex: lectura inicial, documentacion obligatoria, reglas de no leakage y separacion entre app/modelos/datos. | Antes de cambios relevantes o de retomar el proyecto. |
| Indice del backlog | `TAREAS.md` | Resume tareas por estado y enlaza sus fichas. | Para ubicar rapidamente trabajo activo o historico. |
| Fichas de tareas | `tareas/Txxx_*.md` | Conservan contexto, plan, estado, criterio de cierre y notas de cada tarea. | Abrir solo la ficha relacionada con el trabajo actual. |
| Hitos | `documentacion/HITOS.md` | Registro cronologico de avances y decisiones estables. | Para entender por que se tomo una decision o reconstruir la historia reciente. |
| Documento inicial del proyecto | `documento_proyecto.qmd` | Describe el planteo original: objetivo, datos disponibles, levantes, COM, clusters e integracion. | Para entender el origen conceptual del pipeline. |

## Documentacion Tecnica

| Documento | Ubicacion | Proposito | Consultar cuando |
|---|---|---|---|
| Flujo de datos | `documentacion/flujo_datos.qmd` | Detalla ingesta, levantes, COM, clusters, asignacion, base cluster-dia y features historicas. | Se modifica el pipeline de datos o se investiga leakage temporal. |
| Modelos COM | `documentacion/modelos.qmd` | Documenta modelos COM, splits, features, resultados y referencias a modelos relacionados. | Se entrena, compara o interpreta un modelo COM. |
| Utilidades de modelos | `documentacion/modelos_utils.qmd` | Explica funciones compartidas de preparacion, metricas, lift y calibracion. | Se agrega un modelo o se cambian reglas de evaluacion. |
| Diagnostico de variables | `documentacion/diagnostico_variables_modelo.qmd` | Resume colinealidad, VIF y criterio del modelo logistico reducido. | Se cambian features o se revisa interpretabilidad. |
| Analisis territorial COM | `documentacion/analisis_territorial_pred.qmd` | Evalua discriminacion, calibracion, incertidumbre y ranking global/local del modelo COM global por CCZ. | Se revisa desempeno territorial, representacion en el top o posibles recalibraciones por CCZ. |
| Proceso de scoring operativo | `documentacion/proceso_scoring_operativo.qmd` | Define regla D/D-2, estado historico, scoring por bloque, publicacion y app. | Se cambia scoring operativo, app o reglas de frescura. |
| Registros de version | `documentacion/versiones/README.md` y `documentacion/versiones/*.md` | Convencion para registrar cambios puntuales relevantes. | Se necesita dejar una version humana de un cambio importante. |

## Zona Limpia

| Documento | Ubicacion | Proposito | Consultar cuando |
|---|---|---|---|
| README Zona Limpia | `zona_limpia/README.qmd` | Contrato de datos, scripts, categorias, comparaciones, modelos y sesgos de Zona Limpia. | Cualquier cambio o analisis sobre Zona Limpia. |
| Visual ZL vs modelo | `zona_limpia/reportes/07_visualizar_seleccion_zl_vs_modelo.qmd` | Reporte de comparacion diaria a igual N entre seleccion ZL y modelo COM. | Se necesita comunicar tension entre problemas observados y reclamos COM. |
| Sesgos ZL | `zona_limpia/reportes/10_sesgos_seleccion_zona_limpia.qmd` | Reporte de cobertura territorial, correspondencia COM-ZL, ajuste por propension y criterio de levante. | Se discute subreclamo, sesgo territorial o seleccion no aleatoria. |
| Modelo problema observado ZL | `zona_limpia/reportes/13_modelo_problema_observado_zl.qmd` | Reporte metodologico del baseline XGBoost para problema observado en visitas efectivas Zona Limpia. | Se cambia, evalua o interpreta el modelo Zona Limpia observado. |

## App

| Documento | Ubicacion | Proposito | Consultar cuando |
|---|---|---|---|
| README app operativa | `app_operativa/README.md` | Explica ejecucion local y variables de entorno de la app Shiny. | Se levanta o prueba la app. |

## Documentos Generados

Los `.html` generados por Quarto reflejan reportes renderizados. Sirven para lectura, pero la fuente editable es el `.qmd` correspondiente.

## Pendiente De Confirmar

No se encontro `README.md` en la raiz; la fuente principal vigente es `README.qmd`.
