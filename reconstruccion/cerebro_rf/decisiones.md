# Decisiones y asuntos pendientes

## Acordado

- 22/10/2026, R06: aceptar la migración mediante comparación del código original y reconstruido con el mismo modelo e insumos actuales. Acotar la investigación de los tres scores ZL distintos respecto de la publicación histórica; conservarlos como pendiente de procedencia para revisar antes de sustituir el sistema vigente. No atribuirlos sin evidencia al corte horario, a nuevos datos o a reentrenamiento. Los entrenamientos obligatorios siguen requiriendo validación; este acuerdo no cierra R06 ni autoriza R07.

- R04: el usuario aprobó corregir el corte de nuevos levantes a las 01:00 de Montevideo. El legado usa 01:00 UTC (22:00 del día anterior local). No aplicar backfill ni reentrenar automáticamente. La compatibilidad del snapshot histórico y el corte corregido son políticas distintas. Ver [evidencia R04](datos_com_r04.md).

- Raíz nueva: reconstruccion/. Documentación: cerebro_rf/, separada de knowledge/ original.
- R00 crea estructura y documentación únicamente; una tarea por intervención.
- Alcance final: app con COM, ZL y agregados que efectivamente utiliza, con entrenamiento e inferencia. Excluir inferencia explicativa y experimentos no consumidos.
- Codex corre validaciones rápidas; usuario corre procesos largos. Conservar evidencia y pendientes.
- No alterar app, modelos ni publicaciones vigentes durante migración.
- El desarrollo se hará por componentes y se validará cada pieza de forma aislada. Al completar R10, el recorrido operativo que actualiza datos, prepara features, puntúa, genera productos y abastece la app deberá poder ejecutarse con una sola corrida coordinadora.
- El entrenamiento no se ejecutará en cada corrida operativa. Debe existir un recorrido separado y ejecutable de forma ocasional para reevaluar degradación con nuevos datos etiquetados, entrenar un candidato, compararlo con el modelo activo y, si se aprueba, regenerar los scores/productos afectados.
- Mantener versiones identificables de modelos para permitir volver a la versión anterior. La cantidad/plazo de retención y el criterio de promoción quedan pendientes; no conservar automáticamente todos los datos ni salidas intermedias.

## Diseño propuesto, aún sin implementar

Implementado en R02: configuración por defaults locales, DCF explícito y entorno reconocido, en ese orden; no descubrimiento implícito de .Renviron. Arranque y contratos mínimos solo con R base. Runtime local relativo y confinado a raíz nueva. Motivo: hacer comprobable el aislamiento antes de migrar algoritmos. Ver [evidencia y límites](base_r02.md).

Módulos R por responsabilidad, bundles con receta, publicaciones coherentes y lector de app desacoplado. Motivo: mantener equivalencia sin acoplar pipeline a algoritmo o almacenamiento.

La propuesta inicial de ejecución manual por componentes queda refinada por las decisiones anteriores: los componentes se desarrollan y prueban por separado, pero R10 debe integrar una entrada operativa única. El reentrenamiento será un flujo separado y ocasional, con evaluación, promoción explícita y rollback por versión; no habrá reentrenamiento implícito al actualizar datos.

## Decisiones pendientes

- Alcance R01 resuelto: el usuario aprobó referencia local primero; Cloudera se comprobará después. Ver [evidencia](referencia_local_r01.md).
- Muestra, períodos y tolerancias de equivalencia; presupuesto para entrenamientos completos.
- Responsable de extracción Impala y declaración de cierre; ubicaciones S3 reales.
- Inclusión en Git de reconstruccion/ sin incorporar runtime ni secretos.
- Condiciones de transición final y autorización de cambio de consumidor.
- Frecuencia o disparadores de reevaluación, métricas/umbrales de degradación, aprobación de promoción y cantidad/plazo de modelos anteriores a retener.

No usar estas decisiones pendientes para ejecutar R01 dentro de R00. Véase [plan fuente](../../auditoria_v2/04_plan_reconstruccion.md).

