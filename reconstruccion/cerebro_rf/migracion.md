# Procedencia y evidencia de migración

R02 implementó la base; R03 migró receta/inferencia COM y app reducida; R04 agregó preparación, asignación y construcción propia de features para un bloque histórico. Ver [evidencia R04](datos_com_r04.md). Los enlaces originales son referencias informativas, no dependencias ejecutables del procesamiento o la app.

| Pieza futura | Origen orientativo | Verificación pendiente |
|---|---|---|
| Configuración y acceso | [Nota y fuentes](componentes/configuracion_acceso.md) | Base R02; servicios reales R09 pendientes |
| Ingesta y actualización | [Nota y fuentes](componentes/ingesta.md) | Preparación R04 validada; actualización/publicación integral pendiente |
| Referencias y asignaciones | [Nota y fuentes](componentes/referencias_asignaciones.md) | Funciones y bloque histórico R04 validados; cobertura completa pendiente |
| Features históricas y operacionales | [Nota y fuentes](componentes/features.md) | COM R04 validado; familias R06/R07 pendientes |
| Entrenamiento y evaluación | [Nota y fuentes](componentes/entrenamiento.md) | R06, R07; sin migrar |
| Gestión de modelos | [Nota y fuentes](componentes/registro_modelos.md) | R01, R02, R03, R06, R07; sin migrar |
| Inferencia operacional | [Nota y fuentes](componentes/inferencia_operacional.md) | R03, R05, R06, R07; sin migrar |
| Generación y publicación | [Nota y fuentes](componentes/publicacion.md) | R03, R08, R09; sin migrar |
| Aplicación Shiny | [Nota y fuentes](componentes/app_shiny.md) | R03, R08, R10; sin migrar |

Para cada pieza migrada registrar en su tarea: origen exacto, versión/hash cuando corresponda, cambios intencionales, contrato, muestra, tolerancias, resultados y límites. Sintetizar aquí solo el estado y enlazar la evidencia; no duplicar salidas extensas.

Las identidades publicadas localmente descritas en [arquitectura fuente](../../auditoria_v2/03_arquitectura_v2.md) fueron contrastadas con metadatos y hashes en [R01](referencia_local_r01.md). R03 confirma equivalencia numérica COM solo para 50 clusters del 31/03; no para mayo ni para otras familias. No se verificó funcionamiento remoto. La tabla anterior conserva el alcance futuro de cada componente; el detalle de avances está en sus fichas y notas.

