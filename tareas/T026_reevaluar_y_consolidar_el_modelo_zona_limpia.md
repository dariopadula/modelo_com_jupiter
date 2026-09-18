# T026 - Reevaluar y consolidar el modelo Zona Limpia

Estado: pendiente
Prioridad: alta
Area: zona limpia / modelos / validacion
Fecha de creacion: 2026-08-20

### Contexto

`operativo_segmento` muestra senal, pero el desempeno temporal es menor que en
particiones aleatorias. La auditoria de T013 mostro que los registros del
Municipio B pueden recuperarse mediante la asignacion espacial del cluster; el
campo `municipio` original era el que estaba incompleto.

### Plan propuesto

1. Profundizar calibracion, lift y estabilidad temporal con la fuente actual.
2. Comparar prediccion pura y ajustes por propension sin confundir interpretaciones.
3. Revisar sensibilidad territorial y redundancias.
4. Definir criterios minimos de utilidad.
5. Medir el efecto de reincorporar Municipio B con la asignacion espacial
   corregida antes de repetir entrenamiento y evaluacion.

### Criterio de finalizacion

Queda decidido si el modelo es exploratorio, complementario u operativo, con resultados reproducibles y cobertura auditada.

### Notas

La fase definitiva depende de recalcular los insumos historicos afectados por
T013; mientras tanto solo pueden cerrarse evaluaciones parciales.
