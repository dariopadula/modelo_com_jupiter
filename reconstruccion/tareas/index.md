# Indice de tareas de reconstruccion

Una tarea autorizada por chat. [Puntero actual](actual.md). Secuencia: R00 -> R01 -> R02 -> R03 -> R04 -> R05 -> R06 -> R07 -> R08 -> R09 -> R10.

Estados permitidos: pendiente, en proceso, bloqueada, finalizada, descartada. Las dependencias indican orden; no autorizan ejecucion automatica. Prioridades: alta, media, baja.

| Tarea | Estado | Prioridad | Dependencia |
|---|---|---|---|
| [R00 - Crear estructura y cerebro](R00_estructura_y_cerebro.md) | finalizada | alta | ninguna |
| [R01 - Congelar referencia efectiva](R01_referencia_efectiva.md) | finalizada | alta | R00 |
| [R02 - Base autonoma y contratos](R02_base_autonoma_contratos.md) | finalizada | alta | R01 |
| [R03 - Recorrido COM completo con artefacto fijo](R03_recorrido_com.md) | finalizada | alta | R02 |
| [R04 - Fuentes, geografia y features COM](R04_fuentes_referencias_features.md) | finalizada | alta | R03 |
| [R05 - Operacion incremental COM](R05_operacion_incremental_com.md) | finalizada | alta | R04 |
| [R06 - ZL y entrenamiento COM/ZL](R06_zona_limpia_entrenamiento.md) | finalizada | alta | R05 |
| [R07 - Agregado A0 y P3 con entrenamiento](R07_agregado_compuesto.md) | finalizada | alta | R06 |
| [R08 - Productos e interfaz completos](R08_productos_app_completa.md) | finalizada | alta | R07 |
| [R09 - Acceso dual, extraccion y publicacion](R09_acceso_publicacion.md) | en proceso | alta | R08 |
| [R10 - Autonomia y aceptacion](R10_autonomia_aceptacion.md) | pendiente | alta | R09 |

R00-R08 finalizadas en sus alcances documentados. R09 autorizado: acceso y publicacion implementados y validados localmente/S3 simulado. Pendientes comprobaciones reales Impala/S3 cuando haya ubicaciones confirmadas. R10 pendiente; no iniciar automaticamente.

[Reglas](../cerebro_rf/reglas_trabajo.md) | [Estado sintetico](../cerebro_rf/estado_actual.md)




