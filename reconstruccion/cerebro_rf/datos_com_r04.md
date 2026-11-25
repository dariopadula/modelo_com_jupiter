# Datos, asignaciones y features COM — R04

Estado: R04 finalizada con implementación y validación acotada local, 20 de octubre de 2026. R05 pendiente. No es todavía actualización incremental diaria ni publicación productiva.

## Qué cambió

Se migraron nueve funciones de preparación, actividad, vecinos, asignación espacial, base y features a R/ingesta/, R/referencias/ y R/features/. Se reutilizó el código original con namespaces explícitos, formato de dos espacios y descripciones de propósito/entradas/salida. [Procedencia y hashes](../config/procedencia_r04.json).

El [procesador propio](../R/ingesta/procesar_datos_com.R) ofrece dos recorridos:

- Eventos crudos: preparar COM y levantes, asignar posiciones contra referencia fija, asignar COM y construir base/features.
- Snapshot histórico preparado: reutilizar levantes ya descargados y mapa estable, reconstruir la asignación de eventos y las features sin descargar ni preparar otra vez toda la historia.

No se regeneran clusters ni se recalculan cruces censales/administrativos. Se reutilizan las referencias espaciales versionadas; el maestro territorial de la muestra se conserva. No hay consultas Impala/S3 ni importaciones ejecutables del código original desde el procesamiento.

## Corrección temporal aprobada

La función original construye la fecha de corte desde medianoche UTC más una hora. Se comprobó que eso equivale a las 22:00 del día anterior en Montevideo. El usuario aprobó expresamente corregir los nuevos levantes a **01:00 America/Montevideo**.

La función migrada ancla el día al reloj local antes de sumar la hora de corte. Prueba: un levante de las 00:30 entra y uno de las 02:00 no entra en el corte de las 01:00. El cambio es de tres horas frente al legado; **es una corrección intencional, no equivalencia exacta de esas columnas**. [Comparación contra funciones originales](../config/comparacion_funciones_r04.json).

No se reconstruyó la historia descargada con ese corte nuevo ni se reentrenaron modelos. El snapshot de marzo mantiene los campos predictivos históricos preparados; su equivalencia demuestra migración de base/historia/asignación para ese snapshot, no equivalencia del corte corregido frente al modelo original. Antes de operación con nuevas fuentes debe validarse el efecto sobre el modelo y sus resultados; no promover el cambio de datos como equivalencia histórica.

## Comprobación real acotada

El [importador de migración](../herramientas_migracion/importar_insumos_com_r04.R) creó insumos propios con 79.401 contenedor-días y 17.773 eventos para los 50 clusters de referencia, desde 2025-01-01 hasta 2026-03-31. No contiene etiquetas de cluster en las entradas pasadas al asignador: este recalcula la asignación desde coordenadas y candidatos.

Límite importante: los eventos del bloque se eligieron a partir de asignaciones canónicas previas a esos clusters. La prueba valida la reproducción de ese bloque conocido; **no valida cobertura espacial de todos los reclamos de la ciudad**, nuevos eventos que debieran entrar al bloque o un universo completo de competidores. Los casos sintéticos independientes comprueban umbrales, candidatos no elegibles y posiciones nuevas. No aplicar este recorte espacial a la futura ingesta general.

Resultado: **22.013 filas y 57 variables sin diferencias**, mismas claves, targets, elegibilidad y variables históricas; asignaciones coincidentes para las claves y etiquetas comparadas. Los 50 scores COM de marzo conservan diferencia máxima cero. [Informe del derivado validado](../config/validacion_r04.json) y [comparación por variable](../runtime/r04_com/comparacion_features.csv).

El rango se toma del insumo explícito y no de los extremos de reclamos, para conservar días sin eventos. Los controles diarios separan sin_eventos (solo con cierre declarado), cerrado_con_eventos y no_cerrado. El snapshot histórico no tiene cierre contractual verificable y lo registra como desconocido; no se infiere desde el último evento ni se habilita scoring diario por esa ausencia.

## Mayo: resultado de la investigación

[Diagnóstico de mayo](../config/diagnostico_mayo_r04.json): para los 50 clusters del 24/05, los siete campos resumidos en la publicación coinciden con los actuales, pero permanece el error de score máximo 0,008730778733081257.

La publicación no conserva el vector completo de las 15 variables, ni prueba identidad histórica de todos los insumos/preprocesamientos. No se estableció qué variable o cambio de origen explica la diferencia. No atribuirla automáticamente al contexto ni a una corrección de fuentes. Antes de ampliar la equivalencia de predicciones a mayo se necesita una instantánea completa de features/preprocesamiento que produjo esa publicación o una reconstrucción histórica acordada. R05 conserva este límite; no bloquea la equivalencia de datos canónicos de marzo aquí probada.

## Ejecución disponible

Desde la raíz de reconstruccion/:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' --vanilla scripts/preparar_datos_com.R
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' --vanilla tests/test_datos_com_r04.R
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' --vanilla scripts/predecir_com.R
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' --vanilla scripts/run_app.R
```

La segunda línea es la prueba de equivalencia del bloque de migración, no un paso de la futura operación diaria. Si los derivados cambian, su marca de validación debe renovarse antes de usar ese bloque piloto en inferencia.

preparar_datos_com.R acepta opcionalmente ruta de insumos y directorio de salida, relativos a la raíz nueva. Por ejemplo, los fixtures crudos se probaron en runtime/prueba_raw_r04/ sin tocar el snapshot real. Rechaza rutas absolutas y escapes fuera de reconstruccion/. La selección de insumos ya importados es independiente del puente al proyecto anterior.

### Esquema del insumo RDS

Campos comunes: from/through (Date), target_clusters y marks. marks declara source_id, timezone, complete_through (Date o NULL) y available_through_timestamp (POSIXct o NULL).

Snapshot: levante preparado, com con id/dia/incidente/x/y y position_map versionado. Crudos: raw_com, raw_levante y cluster_members_ref; el procesador selecciona ese recorrido al existir raw_levante. Deben incluirse todos los candidatos y el contexto suficiente para el alcance que se quiera evaluar; el procesador no inventa cobertura omitida.

Salidas en runtime/r04_com/: asignaciones, base, features, controles y marcas en derivados.rds. La inferencia comprueba el hash contra la validación y sustituye la historia importada R03 por las features reconstruidas. La app continúa leyendo producto_com_actual.rds, sin recalcular features ni modelos.

## Validaciones y pendientes

- R04_DATOS_OK: bloque histórico, 57 variables, asignaciones y scores.
- R04_REGLAS_OK: 16 casos de corte local, exclusión de datos futuros, contenedor no elegible, umbrales, días sin eventos, inicio sin historia, D-2 y corrección de un evento previo.
- R04_ORIGINAL_OK: equivalencia de reglas sobre fixtures salvo el corte local aprobado.
- Smoke del ejecutable con eventos crudos: seis filas, salida aislada; sin lecturas de fuentes originales.
- Regresión R02/R03 y comando de inferencia COM sobre las features R04.

Todas las corridas fueron locales y acotadas; ninguna requirió entrenamiento ni descarga. Pendientes de otras tareas: estado incremental y frescura (R05), persistencia/publicación integral y servicios reales (R09), universo completo y aceptación final (R10). No se iniciaron esas tareas ni se alteraron las publicaciones originales.
