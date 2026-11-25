# Reconstrucción del sistema operacional

Estado: R00-R07 finalizadas en sus alcances documentados. [Datos y features propios R04](cerebro_rf/datos_com_r04.md) y [motor incremental COM R05](cerebro_rf/operacion_com_r05.md) amplian el recorrido, aun sin cierre de fuentes reales ni certificacion del efecto del corte nuevo en el bundle. La inferencia ZL coincide con el codigo original al usar iguales insumos; los tres desvios con la publicacion historica quedan como procedencia pendiente. Los [entrenamientos completos COM/ZL](cerebro_rf/entrenamiento_r06.md) fueron ejecutados por el usuario y revisados; AUC COM corregido sin reentrenar. R07 finalizada: [preparacion y entrenamiento completos A0/P3](cerebro_rf/agregado_r07.md) revisados. Candidato no promovido. R08 esta en proceso: [productos piloto y app](cerebro_rf/productos_app_r08.md); falta validar el historico completo y la revision visual del usuario.

El objetivo es reproducir de forma autónoma la aplicación actual con COM, Zona Limpia y agregado A0 + P3, incluyendo sus entrenamientos pertinentes. No incluye inferencia explicativa ni experimentos no consumidos. La referencia local identificada se documenta en el [informe R01](cerebro_rf/referencia_local_r01.md); su equivalencia numérica y el despliegue remoto aún no están certificados.

- [Cerebro: puerta de entrada](cerebro_rf/index.md)
- [Estado actual](cerebro_rf/estado_actual.md)
- [Índice de tareas](tareas/index.md)
- [Tarea siguiente](tareas/actual.md)
- [Reglas de trabajo](cerebro_rf/reglas_trabajo.md)
- [Ejecución disponible: inferencia COM y app](scripts/README.md)
- [Convenciones de organización y código](cerebro_rf/convenciones_codigo.md)
- [Arquitectura fuente](../auditoria_v2/03_arquitectura_v2.md)
- [Plan fuente](../auditoria_v2/04_plan_reconstruccion.md)

## Forma de trabajo

Configuracion de ejemplo: [`.Renviron.example`](.Renviron.example). Sus comentarios distinguen entrada, salida y app, y explican la carga del entorno y las opciones S3/Impala. El archivo real `.Renviron` es privado. Rscript con `--vanilla` no lo carga automaticamente.

Una tarea autorizada por chat. Codex implementa y ejecuta verificaciones rápidas; las corridas largas las ejecuta el usuario con instrucciones reproducibles. Una validación obligatoria pendiente impide cerrar la tarea. No avanzar automáticamente. Durante la reconstrucción los componentes se desarrollan por separado; al completar R10, el flujo operativo para actualizar datos, generar los productos de la app y publicarlos debe coordinarse con una sola corrida. El entrenamiento queda en un recorrido separado y ocasional, con evaluación de degradación, comparación de candidatos y versiones recuperables para rollback; nunca se dispara en cada scoring.

R/ingesta/, R/referencias/ y R/features/ incluyen preparacion, asignacion y base/historia; R/modelos/ y R/entrenamiento/ cubren los recorridos migrados; R/operacion/ procesa bloques con cierre declarado. app/ lee los productos completos R08 y admite publicaciones versionadas R09. Acceso/publicacion local y S3 simulado probados; Impala/S3 reales pendientes de configuracion. R10 coordinara el pipeline completo. [Estado R09 y comandos](cerebro_rf/acceso_publicacion_r09.md).

## Responsabilidades y artefactos

Funciones en R/, ejecución del sistema en scripts/, interfaz en app/, configuración en config/ y pruebas en tests/. Las inspecciones e importaciones del legado viven en herramientas_migracion/, separadas del pipeline. La documentación vigente vive en cerebro_rf/ y el backlog en tareas/. runtime/ conserva muestras y el bundle reducido COM, excluidos de Git.

La política Git de la raíz excluye por defecto carpetas nuevas. R00 no modifica esa política: existencia en disco no significa que estos documentos estén versionados. Resolver su inclusión en una tarea autorizada antes de depender de Git como respaldo.



