# R10 - Autonomia y aceptacion

- Estado: pendiente
- Prioridad: alta
- Dependencias: R09

## Contexto y objetivo

Demostrar funcionamiento propio y preparar transicion sin activarla.

## Fuentes originales concretas

- [app_operativa_v2/README.md](../../app_operativa_v2/README.md)
- [app_operativa_v2/run_app.R](../../app_operativa_v2/run_app.R)
- [app_operativa_v2/tests/test_app.R](../../app_operativa_v2/tests/test_app.R)
- [app_operativa_v2/tests/test_fuente_datos.R](../../app_operativa_v2/tests/test_fuente_datos.R)
- [auditoria_v2/03_arquitectura_v2.md](../../auditoria_v2/03_arquitectura_v2.md)
- [auditoria_v2/04_plan_reconstruccion.md](../../auditoria_v2/04_plan_reconstruccion.md)

## Entradas

Sistema propio, referencia R01, manifiestos y evidencia previa.

## Salidas

Evidencia integral local/Cloudera y propuesta de transicion; un punto de entrada para el recorrido operativo y un recorrido separado para reentrenar/evaluar versiones.

## Plan propuesto

Desarrollar y probar cada componente por separado durante R01-R09. En R10, coordinar con una sola corrida el flujo operativo completo desde actualizacion de datos hasta productos publicados para la app. Mantener fuera de esa corrida el entrenamiento; exponerlo por un punto de entrada separado que produzca un candidato evaluable. Probar ejecucion desde raiz nueva sin acceso al codigo antiguo, comparar salidas y revisar destinos.

## Validacion

Autonomia, paridad, ausencia de escrituras originales y pruebas en ambos entornos. La corrida operativa debe coordinar actualizacion, features, scoring de familias incluidas, productos, validacion y publicacion sin ejecutar entrenamiento. El flujo de reentrenamiento debe evaluar degradacion con etiquetas nuevas, comparar candidato/modelo activo, conservar manifiestos/versiones, permitir regenerar productos tras promocion y demostrar rollback. Corridas largas por usuario.

Estado de validacion: no ejecutada; tarea pendiente.

## Criterio de finalizacion

Criterios acordados satisfechos y limites registrados; transicion queda pendiente de aprobacion separada.

## Notas y decisiones pendientes

No cambiar abastecimiento, publicacion o despliegue actual al cerrar esta tarea. La frecuencia/metricas de degradacion, umbrales de promocion y cantidad/plazo de versiones anteriores a retener deben definirse antes de automatizar el reentrenamiento.

Antes de aprobar una sustitucion, revisar expresamente los tres desvios ZL respecto de la publicacion historica registrados en R06. La equivalencia con insumos actuales iguales no certifica la procedencia de aquella publicacion; documentar la resolucion o la limitacion aceptada en la propuesta de transicion.

Aplicar [politica de pruebas y corridas largas](../cerebro_rf/reglas_trabajo.md). No finalizar con validaciones obligatorias pendientes. No ejecutar la tarea siguiente sin instruccion.

[Volver al indice](index.md)

