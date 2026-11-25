# Ingesta y actualización

Estado: preparacion COM/levantes implementada en R04, con corte local corregido aprobado. R09 incorpora entregas fuentes_v2 y extractor Impala probados sin red; conexiones reales diferidas y coordinacion integral pendiente de R10. Ver [R04](../datos_com_r04.md) y [R09](../acceso_publicacion_r09.md).

Preparar COM, COM completo y levantes, conservar trazabilidad de correcciones.

## Entrada y salida

Entrega fuentes_v2 o historia existente; salida: datos preparados y marcas de cierre/disponibilidad.

## Contrato y límites

Mismo bloque crudo para COM y COM completo; días sin eventos distintos de días desconocidos.

## Fuentes para migrar

- [funciones/ingesta_incremental_utils.R](../../../funciones/ingesta_incremental_utils.R)
- [funciones/preparar_datos_com.R](../../../funciones/preparar_datos_com.R)
- [funciones/preparar_datos_levante.R](../../../funciones/preparar_datos_levante.R)
- [scripts/actualizar_fuentes_incremental.R](../../../scripts/actualizar_fuentes_incremental.R)

Tareas: R04, R09. Ver [índice](../../tareas/index.md). La evidencia local y los pendientes remotos estan en las fichas correspondientes.

[Volver al cerebro](../index.md)

