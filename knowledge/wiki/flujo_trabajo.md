# Flujo De Trabajo

Ver tambien [[index]], [[mapa_documental]], [[tareas_por_tipo]], [[datos_y_leakage]] y [[decisiones]].

## Regla General

El proyecto se trabaja con una separacion explicita entre:

- codigo fuente;
- datos procesados;
- modelos entrenados;
- reportes generados;
- app operativa.

La app debe consumir salidas ya calculadas. No debe recalcular features ni aplicar modelos.

## Lectura Inicial Recomendada

Antes de cambios relevantes:

1. `README.qmd`
2. `TAREAS.md` y, desde su indice, solo las fichas relevantes en `tareas/`
3. `documentacion/HITOS.md`
4. documentacion especifica del tema
5. si el tema es Zona Limpia, `zona_limpia/README.qmd`

Documentos especificos:

- scoring operativo: `documentacion/proceso_scoring_operativo.qmd`;
- modelos: `documentacion/modelos.qmd` y `documentacion/modelos_utils.qmd`;
- flujo de datos: `documentacion/flujo_datos.qmd`.

## Gestion De Cambios

Para cambios conceptuales o de alto impacto:

- presentar diagnostico breve y plan antes de modificar;
- priorizar cambios pequenos y revisables;
- no borrar ni sobrescribir documentacion existente sin confirmacion;
- no reentrenar modelos pesados ni sobrescribir artefactos importantes sin avisar alcance;
- registrar decisiones cuando haya dudas de diseno.

## Documentacion Obligatoria

Cada cambio relevante debe reflejarse en al menos una de estas fuentes:

- `documentacion/HITOS.md`: avance importante o decision estable;
- `documentacion/versiones/`: registro puntual si conviene preservar detalle;
- `TAREAS.md` y `tareas/`: indice y ficha para alta, avance, bloqueo, descarte o cierre de tarea.

La wiki en `knowledge/` no reemplaza esa obligacion. La wiki sintetiza despues.

## Backlog

`TAREAS.md` funciona como indice breve del backlog vivo. Cada tarea tiene una ficha separada en `tareas/` con:

- estado: `pendiente`, `en proceso` o `finalizada`;
- prioridad: `alta`, `media` o `baja`;
- contexto;
- plan propuesto;
- criterio de finalizacion;
- notas o decisiones pendientes.

## Reglas De Datos Y Leakage

Reglas documentadas:

- features historicas excluyen el dia objetivo;
- variables predictivas de levante usan corte `D 01:00` y sufijo `_pred`;
- scoring operativo usa reclamos historicos cerrados hasta `D-2`;
- reclamos de `D` nunca entran como features;
- predicciones historicas se congelan salvo reproceso explicito y versionado.

## Flujo Para Nuevas Tareas

1. Ubicar tema en [[mapa_documental]].
2. Revisar [[componentes]] para entender scripts y dependencias.
3. Revisar [[decisiones]] para no contradecir supuestos establecidos.
4. Crear o actualizar la ficha en `tareas/` y su linea en `TAREAS.md` si corresponde.
5. Ejecutar cambios en el componente minimo necesario.
6. Validar o documentar explicitamente si no se pudo validar.
7. Registrar hito/version si el cambio afecta resultados o rumbo.
8. Actualizar wiki solo si cambia el conocimiento estable.

## Estado Actual Inferido

- El proyecto tiene memoria interna (`AGENTS.md`, `TAREAS.md`, `tareas/`, `HITOS.md`) porque todavia no depende solamente de Git como registro de decisiones.
- Existen reportes renderizados `.html`, pero la fuente editable son `.qmd` y `.md`.
- Zona Limpia se mantiene como frente analitico separado del pipeline operativo COM.

## Pendiente De Confirmar

- Revisar periodicamente que el indice y las fichas no tengan estados o enlaces inconsistentes.
- Convencion final de versionado de modelos y artefactos productivos.
