# Generación y publicación

Estado: R08 finalizada con historico completo y revision visual aprobados. Publicacion/activacion recuperable R09 implementada y validada localmente/S3 simulado; comprobacion remota pendiente. Ver [R09](../acceso_publicacion_r09.md).

Construir productos coherentes de operación, histórico y referencia.

## Entrada y salida

Scores, agregado, observados y referencias; salida: publicación validada identificada por versión.

## Contrato y límites

R08 construye destinos nuevos ready. R09 escribe versiones inmutables, verifica inventario y activa mediante puntero con respaldo. App fija una version; no recalcula modelos. S3 exige publicador unico, sin rename ni bloqueo distribuido. No se activo ningun consumidor vigente.

## Fuentes para migrar

- [scripts/construir_app_modelos_largo_historico.R](../../../scripts/construir_app_modelos_largo_historico.R)
- [scripts/construir_tablas_historicas_app_v2.R](../../../scripts/construir_tablas_historicas_app_v2.R)
- [scripts/construir_maestro_clusters_app_v2.R](../../../scripts/construir_maestro_clusters_app_v2.R)
- [documentacion/contrato_datos_app_operativa_v2.qmd](../../../documentacion/contrato_datos_app_operativa_v2.qmd)

Tareas: R03, R08, R09. Ver [índice](../../tareas/index.md). Ver [evidencia y validaciones R08](../productos_app_r08.md).

[Volver al cerebro](../index.md)

