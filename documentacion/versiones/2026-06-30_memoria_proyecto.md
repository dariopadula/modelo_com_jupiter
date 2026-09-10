# Cambio: memoria estable del proyecto

Fecha: 2026-06-30  
Area: documentacion / forma de trabajo

## Contexto

El proyecto venia acumulando mucho contexto en sesiones de Codex. Se decide crear una memoria estable dentro del propio repositorio para poder retomar el trabajo sin depender de conversaciones previas.

## Cambios realizados

- Se crea `AGENTS.md` con reglas de trabajo para Codex.
- Se crea `TAREAS.md` como backlog vivo en formato ficha.
- Se crea `documentacion/HITOS.md` como registro cronologico de avances importantes.
- Se crea `documentacion/versiones/` para registros puntuales de cambios relevantes.
- Se ajusta minimamente `README.qmd` para enlazar la memoria del proyecto.

## Decisiones tomadas

- Las tareas no se registran como tabla sino como fichas con contexto, plan y criterio de finalizacion.
- Los estados de tarea son `pendiente`, `en proceso` y `finalizada`.
- Las prioridades son `alta`, `media` y `baja`.
- Si `TAREAS.md` crece demasiado, las tareas finalizadas antiguas se pueden migrar a `TAREAS_FINALIZADAS.md`.

## Validaciones

- Se verifico que los archivos de memoria fueron creados.
- Se verifico que `README.qmd` enlaza la nueva estructura.

## Riesgos o pendientes

- Mantener esta estructura liviana para que no se vuelva burocratica.
- Actualizar tareas, hitos y versiones cuando haya cambios relevantes.
