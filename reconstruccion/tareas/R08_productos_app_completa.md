# R08 - Productos e interfaz completos

- Estado: finalizada
- Prioridad: alta
- Dependencias: R07

## Contexto y objetivo

Completar los productos locales de lectura de la app y migrar todas sus vistas operativas e historicas. R08 consume scores ya calculados; no entrena ni predice.

## Fuentes originales concretas

- [scripts/construir_app_modelos_largo_historico.R](../../scripts/construir_app_modelos_largo_historico.R)
- [scripts/construir_tablas_historicas_app_v2.R](../../scripts/construir_tablas_historicas_app_v2.R)
- [scripts/construir_maestro_clusters_app_v2.R](../../scripts/construir_maestro_clusters_app_v2.R)
- [app_operativa_v2/app.R](../../app_operativa_v2/app.R)
- [app_operativa_v2/R/mod_scores.R](../../app_operativa_v2/R/mod_scores.R)
- [app_operativa_v2/R/mod_evolucion.R](../../app_operativa_v2/R/mod_evolucion.R)
- [app_operativa_v2/R/mod_dia_com.R](../../app_operativa_v2/R/mod_dia_com.R)
- [app_operativa_v2/R/mod_dia_zl.R](../../app_operativa_v2/R/mod_dia_zl.R)
- [app_operativa_v2/tests/test_datos_historicos.R](../../app_operativa_v2/tests/test_datos_historicos.R)
- [app_operativa_v2/tests/test_dia_com.R](../../app_operativa_v2/tests/test_dia_com.R)
- [app_operativa_v2/tests/test_dia_zl.R](../../app_operativa_v2/tests/test_dia_zl.R)
- [documentacion/contrato_datos_app_operativa_v2.qmd](../../documentacion/contrato_datos_app_operativa_v2.qmd)
- [skills/shiny_skill.md](../../skills/shiny_skill.md)

## Entradas

Scores, agregado, observados, controles y referencias.

## Salidas

Operacional/historico/referencia y todas las vistas de app nueva.

## Plan propuesto

Completar contratos y modulos; conservar seleccion COM/ZL separada y lectura particionada.

## Validacion

Prueba automatizada acotada de constructor/lectura, operacion, umbrales, mapa/lista, evolucion y evaluacion COM/ZL; filtros, empates, cupos y metricas; publicacion historica completa; revision visual del usuario.

Estado de validacion: suite R08 y 60 lecturas aprobadas; historico completo construido y manifiesto ready verificado; revision visual de la publicacion completa aprobada por el usuario. Sin validaciones obligatorias pendientes.

## Criterio de finalizacion

Productos historicos completos y operacionales pasan las pruebas pertinentes; el usuario confirma la revision visual. No se afecta la interfaz vigente.

## Notas y decisiones pendientes

No redisenar experiencia ni cambiar targets durante migracion.

Implementado en esta sesion: bootstrap propio, productos locales con manifiesto `ready` al final, modulos operativos e historicos, lanzador R08 y prueba automatizada. La publicacion piloto usa el snapshot vigente importado para 31/03 y 24/05/2026 (31.694 filas), con scores sin recalcular y candidatos sin promover. La prueba rapida completa, incluido el cargador de app.R de Shiny, paso en 21 segundos. El servidor piloto esta disponible en `http://127.0.0.1:3843` para revision visual.

Pendiente: se resolvieron el indice interno invalido tras `collect()` de Arrow, la falta de `bs_theme` y el alcance de valores de fecha al servir la UI. La UI ahora se construye con argumentos explicitos; la prueba renderiza esa UI despues de eliminar el entorno de carga y pasa con la fecha esperada. Se calificaron funciones `bslib`, se evito la carga automatica duplicada de `R/` y se hizo explicito el entorno compartido de la app. La comprobacion HTTP desde la herramienta local fue bloqueada por permisos de socket, aunque Shiny informa que esta escuchando en el puerto 3843. El usuario debe cerrar cualquier instancia anterior y reiniciar la app para revisar esta version. Importar el historial completo se deja al usuario porque la duracion es incierta; el comando aislado esta en [productos e interfaz R08](../cerebro_rf/productos_app_r08.md).

Aplicar [politica de pruebas y corridas largas](../cerebro_rf/reglas_trabajo.md). No finalizar con validaciones obligatorias pendientes. No ejecutar la tarea siguiente sin instruccion.

[Volver al indice](index.md)

## Correccion del cargador Shiny

La causa de los errores sucesivos de fecha y publication_label era la coexistencia de app.R y server.R: shinyAppDir prioriza server.R y omitia la inicializacion de app.R. Se renombraron los componentes a interfaz.R y servidor.R, conservando separacion de responsabilidades. La prueba ahora usa shiny::shinyAppDir y su manejador HTTP: estado 200 y fecha esperada confirmados, junto con pruebas de modulos (salida 0).

Validacion fallida registrada: una primera corrida fallo en la validacion de ranking/percentiles COM del constructor; la repeticion completa paso. Este fue el estado previo al diagnostico; la resolucion y las validaciones posteriores se registran abajo.
## Resolucion de validacion intermitente y revision visual

Revision visual del piloto confirmada por el usuario. La intermitencia queda resuelta por evidencia reproducida: indice __modelo_id vacio heredado de Arrow hacia data.table hacia que COM quedara vacio, fallando version unica. No era un desvio de ranking/percentiles. Se normaliza la materializacion de Arrow y se eliminan indices heredados sobre una copia en el validador. Suite R08 con regresion de indice invalido aprobada y 60 lecturas/validaciones aprobadas. Esto reemplaza el pendiente de intermitencia anterior. El historico completo y su revision visual fueron aprobados posteriormente; ver cierre abajo.

## Historico completo construido

Corrida del usuario runtime/r08_app_completa_20261022_150057: 26.280 filas de serie importadas y 7.902.058 filas de detalle en 509 dias, del 01/01/2025 al 24/05/2026. Constructor completo aprobado; manifiesto comprobado localmente con estado ready, historia_publicada, scores sin recalcular y candidatos sin promover. Revision visual del piloto ya aprobada. El usuario confirmo que la app con esta publicacion completa funciono correctamente. R08 finalizada; R09 pendiente y no iniciado.

## Cierre

Usuario confirma revision visual satisfactoria de la publicacion completa. Criterios de R08 cumplidos. Siguiente tarea: R09, pendiente de autorizacion; no se ejecuto.

