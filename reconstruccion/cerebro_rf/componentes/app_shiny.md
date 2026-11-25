# Aplicación Shiny

Estado: R08 finalizada con historico completo de 509 dias y revision visual del usuario aprobada. R09 agrega lectura versionada local/S3 y cache por particion; pruebas locales/simuladas y HTTP aprobados, comprobacion real Cloudera diferida. Ver [R08](../productos_app_r08.md) y [R09](../acceso_publicacion_r09.md).

Reproducir las vistas actuales consumiendo únicamente productos preparados.

## Entrada y salida

Publicación estable y selección del usuario; salida: vistas, mapas, lista y evaluación.

## Contrato y límites

UI/server modular y lector separado; COM/ZL independientes; ninguna aplicación de modelos dentro de Shiny.

## Fuentes para migrar

- [app_operativa_v2/app.R](../../../app_operativa_v2/app.R)
- [app_operativa_v2/R/datos_fuente.R](../../../app_operativa_v2/R/datos_fuente.R)
- [app_operativa_v2/R/datos_operacion.R](../../../app_operativa_v2/R/datos_operacion.R)
- [app_operativa_v2/tests/test_app.R](../../../app_operativa_v2/tests/test_app.R)
- [skills/shiny_skill.md](../../../skills/shiny_skill.md)

Tareas: R03, R08, R10. Ver [índice](../../tareas/index.md). La app consume productos ya calculados; coordinacion punta a punta corresponde a R10.

[Volver al cerebro](../index.md)

