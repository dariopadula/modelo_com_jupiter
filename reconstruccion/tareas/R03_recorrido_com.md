# R03 - Recorrido COM completo con artefacto fijo

- Estado: finalizada
- Prioridad: alta
- Dependencias: R02

## Contexto y objetivo

Primera seccion vertical visible, aun con features existentes importadas de forma acotada.

## Fuentes originales concretas

- [funciones/modelos_utils.R](../../funciones/modelos_utils.R)
- [scripts/construir_app_modelos_largo_historico.R](../../scripts/construir_app_modelos_largo_historico.R)
- [scripts/construir_maestro_clusters_app_v2.R](../../scripts/construir_maestro_clusters_app_v2.R)
- [scripts/construir_tablas_historicas_app_v2.R](../../scripts/construir_tablas_historicas_app_v2.R)
- [app_operativa_v2/app.R](../../app_operativa_v2/app.R)
- [app_operativa_v2/R/datos_app.R](../../app_operativa_v2/R/datos_app.R)
- [app_operativa_v2/R/datos_fuente.R](../../app_operativa_v2/R/datos_fuente.R)
- [app_operativa_v2/R/mod_seleccion.R](../../app_operativa_v2/R/mod_seleccion.R)
- [app_operativa_v2/R/mod_mapa.R](../../app_operativa_v2/R/mod_mapa.R)
- [app_operativa_v2/R/mod_lista.R](../../app_operativa_v2/R/mod_lista.R)
- [app_operativa_v2/tests/test_app.R](../../app_operativa_v2/tests/test_app.R)
- [skills/shiny_skill.md](../../skills/shiny_skill.md)

## Entradas

Bundle COM fijo, muestra de features y referencias verificadas.

## Salidas

Adaptador COM, productos minimos y app aislada para el mismo bloque.

## Plan propuesto

Reutilizar predecir_com y preparacion; adaptar lector/modulos; mantener ZL/agregado marcados como incompletos en este hito.

## Validacion

Comparar claves, scores, ranking, seleccion, mapa/lista y estados de observacion.

Estado de validacion: pruebas automaticas satisfactorias y revision visual general confirmada por el usuario el 2026-10-20: abrio la app reducida y parece funcionar bien. No se atribuyen al usuario verificaciones detalladas no reportadas. Cierre limitado al alcance de muestra R03.

Evidencia: [recorrido R03](../cerebro_rf/recorrido_com_r03.md) e [informe numerico](../config/equivalencia_com_r03.json). Bloque 2026-03-31, top 50 de universo 7996; 9011 filas de contexto. Error maximo 0 frente a tolerancia 1e-10; mismo ranking/flags, seleccion, coordenadas y estados. R03_COM_OK y regresion R02_TESTS_OK. App inicia, pero navegador integrado no pudo conectar por restricciones de socket. Falta aprobacion visual local, por lo que no se finaliza R03.

## Criterio de finalizacion

Recorrido COM probado con tolerancias previas y revision visual; no datos ficticios.

## Notas y decisiones pendientes

Leer guia Shiny antes de adaptar; no recalcular features ni modelos dentro de la app.

La guia fue aplicada: modulo UI/server y lector separado. Mayo 24 no fue equivalente (error maximo 0.008730778733081257); causa no determinada, investigar antes de ampliar periodo en R04/R05. La equivalencia confirmada solo corresponde al bloque de marzo. Estados observados son los preservados del legado, no un cierre recalculado. R04 no iniciada.

Ordenamiento aprobado y aplicado: inspectores/importacion en herramientas_migracion/, validaciones en tests/ y ejecucion en scripts/. Nuevo predecir_com.R recalcula el bloque propio antes de abrir la app. Codigo con sangria de dos espacios y comentarios de funciones; sin cambiar la receta. Revision visual sigue pendiente.

Ajuste de arranque tras reporte del usuario: run_app.R muestra estado y URL, comprueba dependencias/producto y abre navegador por defecto. Probado hasta Listening on 127.0.0.1:3843 con apertura de ventana desactivada para el test. El silencio reportado en PowerShell no se reprodujo; falta confirmar ejecucion y visualizacion local del usuario.

Aplicar [politica de pruebas y corridas largas](../cerebro_rf/reglas_trabajo.md). No finalizar con validaciones obligatorias pendientes. No ejecutar la tarea siguiente sin instruccion.

[Volver al indice](index.md)

## Cierre

R03 finalizada tras confirmacion visual del usuario. Las menciones anteriores a revision pendiente registran la secuencia de trabajo, ya resuelta. R04 queda como siguiente tarea pendiente, sin ejecucion automatica. Se mantienen la discrepancia de mayo, la equivalencia solo del bloque de marzo y las validaciones multi-modelo/remotas posteriores.

