# R01 - Congelar referencia efectiva

- Estado: finalizada
- Prioridad: alta
- Dependencias: R00

## Contexto y objetivo

Identificar productos y artefactos efectivos antes de migrar; defaults no prueban configuracion activa.

## Fuentes originales concretas

- [scripts/construir_app_modelos_largo_historico.R](../../scripts/construir_app_modelos_largo_historico.R)
- [scripts/construir_tablas_historicas_app_v2.R](../../scripts/construir_tablas_historicas_app_v2.R)
- [app_operativa_v2/R/datos_fuente.R](../../app_operativa_v2/R/datos_fuente.R)
- [app_operativa_v2/R/datos_operacion.R](../../app_operativa_v2/R/datos_operacion.R)
- [app_operativa_v2/data/operacional/resumen_modelos_largo.csv](../../app_operativa_v2/data/operacional/resumen_modelos_largo.csv)
- [app_operativa_v2/data/historico/resumen_publicacion.csv](../../app_operativa_v2/data/historico/resumen_publicacion.csv)

## Entradas

Metadatos no secretos, publicaciones y artefactos locales; evidencia Cloudera si disponible.

## Salidas

Manifiesto de referencia con hashes, modelo/escenario, version espacial, periodos y procedencia; muestra acotada o instruccion para obtenerla.

## Plan propuesto

Contrastar publicaciones y configuracion no secreta; identificar artefactos; registrar limites y preparar muestra aislada. No entrenar ni promover candidatos.

## Validacion

Relacion comprobada entre productos COM/ZL/agregado y artefactos; distinguir identidad declarada y equivalencia numerica pendiente.

Estado de validacion: ejecutada, satisfactoria el 2026-10-20 para el alcance local aprobado por el usuario.

Evidencia: [informe local](../cerebro_rf/referencia_local_r01.md) y [manifiesto](../config/referencia_local_r01.json). Se inspeccionaron cuatro RDS, se identificaron 19 archivos con SHA-256 y se extrajeron 16 predicciones, 16 filas del maestro y ocho filas agregadas con filtrado previo. Resultado: R01_INSPECCION_OK y HASHES_OK. No hubo entrenamiento ni escritura a fuentes originales.

Congelacion local: version_cluster v2026_05_25, COM reducido D-2, ZL operativo_segmento/random_dia_estratificado_mes y compuesto A0/P3. Los hashes identifican binarios presentes, no prueban por si solos que generaron las publicaciones historicas. Equivalencia numerica posterior en R03/R06/R07. El campo retrospectivo fecha_reclamos_usada_hasta requiere revision semantica en R03/R05.

## Criterio de finalizacion

Referencia local documentada y limites explicitados; alcance local o local/Cloudera acordado. Si una validacion obligatoria queda pendiente, no cerrar.

## Notas y decisiones pendientes

No se abrio .Renviron ni se imprimieron secretos. El usuario aprobo referencia local primero y Cloudera posterior. No quedan verificaciones obligatorias pendientes dentro de ese alcance R01; comprobacion remota y equivalencia numerica se mantienen explicitamente en tareas posteriores. R02 sigue pendiente de nueva instruccion.

Aplicar [politica de pruebas y corridas largas](../cerebro_rf/reglas_trabajo.md). No finalizar con validaciones obligatorias pendientes. No ejecutar la tarea siguiente sin instruccion.

[Volver al indice](index.md)

