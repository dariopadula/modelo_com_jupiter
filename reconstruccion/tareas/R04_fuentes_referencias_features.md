# R04 - Fuentes, geografia y features COM

- Estado: finalizada
- Prioridad: alta
- Dependencias: R03

## Contexto y objetivo

Sustituir features importadas por transformaciones propias equivalentes.

## Fuentes originales concretas

- [funciones/preparar_datos_com.R](../../funciones/preparar_datos_com.R)
- [funciones/preparar_datos_levante.R](../../funciones/preparar_datos_levante.R)
- [funciones/definir_intervalos_actividad_contenedor.R](../../funciones/definir_intervalos_actividad_contenedor.R)
- [funciones/ingesta_incremental_utils.R](../../funciones/ingesta_incremental_utils.R)
- [funciones/asignar_com_a_contenedores_activos.R](../../funciones/asignar_com_a_contenedores_activos.R)
- [funciones/asignar_posiciones_levante_a_clusters.R](../../funciones/asignar_posiciones_levante_a_clusters.R)
- [funciones/construir_base_cluster_dia.R](../../funciones/construir_base_cluster_dia.R)
- [funciones/construir_features_historicas_cluster_dia.R](../../funciones/construir_features_historicas_cluster_dia.R)
- [scripts/asignar_clusters_posiciones_nuevas.R](../../scripts/asignar_clusters_posiciones_nuevas.R)
- [scripts/asignar_com_contenedores_clusters.R](../../scripts/asignar_com_contenedores_clusters.R)
- [scripts/construir_cluster_territorial_admin.R](../../scripts/construir_cluster_territorial_admin.R)
- [scripts/construir_cluster_territorial_segmento_censal.R](../../scripts/construir_cluster_territorial_segmento_censal.R)

## Entradas

Historia descargada, referencia espacial estable e incrementos pequenos.

## Salidas

Fuentes canonicas, asignaciones, base/features y marcas explicitas de cierre.

## Plan propuesto

Importar historia identificada; reutilizar reglas; construir derivados en destinos propios.

## Validacion

Igualdad de claves/targets/elegibilidad y features; casos D-2, D 01:00, cero eventos, sin historia y correcciones.

Estado de validacion: ejecutada y satisfactoria el 2026-10-20 para el bloque local acotado. R04_DATOS_OK (22013 filas, 57 variables y 17773 asignaciones), R04_REGLAS_OK (16 comprobaciones), R04_ORIGINAL_OK (salvo corte aprobado), COM_PREDICCIONES_OK usando features R04, R03_COM_OK y R02_TESTS_OK. Hashes de originales/referencias, enlaces y estilo verificados. No hay validaciones obligatorias de este alcance R04 pendientes.

Evidencia: [datos COM R04](../cerebro_rf/datos_com_r04.md). 79401 contenedor-dias, 17773 eventos; 22013 filas y 57 variables equivalentes a fuentes canonicas en el bloque de marzo. Inferencia consume features reconstruidas con hash validado, sin cambiar scores de la muestra. Nueve funciones migradas con procedencia y namespaces explicitos.

## Criterio de finalizacion

Pruebas acotadas pasan y features nuevas reemplazan la muestra importada, conservando reglas salvo la correccion del corte local aprobada expresamente por el usuario.

## Notas y decisiones pendientes

No regenerar clusters ni descargar de nuevo la historia.

Hallazgo R03 a investigar antes de ampliar periodo: top50 del 2026-03-31 reproduce scores exactamente, pero el 2026-05-24 difiere hasta 0.008730778733081257 con features actuales. No se determino si son cambios de insumos o contexto. Ver evidencia R03 y comparar campos antes de atribuir causa o modificar reglas.

Investigacion R04: los siete campos resumidos de mayo coinciden; no existe vector completo en la publicacion para atribuir causa. La discrepancia se conserva como limite para mayo, sin ampliar equivalencia. El usuario aprobo corregir nuevos levantes a 01:00 America/Montevideo; no se recalculo historia ni se reentreno. Esta excepcion aprobada modifica intencionalmente la regla de corte del legado (01:00 UTC); el resto de reglas se preserva. Marcas de cierre desconocidas quedan como tales y no autorizan scoring diario.

Cierre: R05 queda pendiente de nueva instruccion. Cobertura espacial integral, operacion con nuevas fuentes y evaluacion de resultados con corte corregido no se declaran aprobadas por esta prueba de snapshot historico. No se altero codigo ni publicaciones originales y no se iniciaron tareas T035-T040.

Aplicar [politica de pruebas y corridas largas](../cerebro_rf/reglas_trabajo.md). No finalizar con validaciones obligatorias pendientes. No ejecutar la tarea siguiente sin instruccion.

[Volver al indice](index.md)

