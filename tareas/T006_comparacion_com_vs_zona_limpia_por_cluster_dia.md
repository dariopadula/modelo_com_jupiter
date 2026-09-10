# T006 - Comparacion COM vs Zona Limpia por cluster-dia

Estado: finalizada

Prioridad: alta

Area: zona limpia / auditoria / comparacion territorial

Fecha de creacion: 2026-07-01 Fecha de cierre: 2026-07-01

### Contexto

Se quiere comparar, dia a dia y a nivel `cluster_id`, los
reclamos COM asignados al target del modelo con los resultados
reportados por Zona Limpia. La interpretacion debe reconocer que Zona
Limpia tiene mayor valor observacional cuando efectivamente visita el
lugar, porque son personas que registran la situacion in situ. En
cambio, COM depende de que una persona realice el reclamo, por lo que
puede tener sesgos geograficos, demograficos y culturales sobre que se
reclama y donde se reclama.

Para esta comparacion inicial conviene tratar
`Voluminosos` con cuidado, porque no es una categoria
equivalente al problema COM usado por el modelo. La comparacion estricta
deberia considerar como problemas comparables de Zona Limpia categorias
como `Basura fuera` y `Contenedor desbordado`,
dejando `Voluminosos` como categoria separada o
sensibilidad.

### Plan propuesto

- Asignar registros Zona Limpia a `cluster_id` y `dia`, manteniendo el proceso separado dentro de `zona_limpia/`.

- Construir una tabla comparativa `cluster_id`/`dia` con indicadores de COM y Zona Limpia.

- Separar estados de Zona Limpia: problema comparable, voluminosos, limpio, no visitado, no encontrado y no realizado.

- Definir una variable de comparacion con casos como: ambas fuentes reportan problema;

- solo Zona Limpia reporta problema;

- solo COM reporta problema;

- Zona Limpia reporta limpio y COM no;

- COM reporta pero Zona Limpia no permite validar;

- Zona Limpia sin visita efectiva.

- Generar resumenes diarios, mensuales y por cluster.

- Dejar preparada una salida apta para mapas interactivos por `cluster_id`/`dia`.

### Criterio de finalizacion

Existe una tabla reproducible de comparacion COM vs Zona Limpia por
`cluster_id`/`dia`, con tratamiento explicito de
`Voluminosos` y estados comparables documentados. La salida
permite construir resumenes y mapas interactivos sin recalcular la
logica base.

### Notas

La lectura sustantiva esperada no debe tratar COM como verdad
absoluta. Cuando Zona Limpia detecta problema y COM no, el caso puede
interpretarse como posible problema no reclamado, no necesariamente como
error de Zona Limpia.

Se creo
`zona_limpia/04_comparar_com_zona_limpia_cluster_dia.R`. Las
salidas principales son:

- `data/processed/zona_limpia/asignaciones_zona_limpia/`

- `data/processed/zona_limpia/zona_limpia_cluster_dia/`

- `data/processed/zona_limpia/comparacion_com_zona_limpia_cluster_dia/`

- `zona_limpia/outputs/comparacion_com_zona_limpia_resumen_estado.csv`

- `zona_limpia/outputs/comparacion_com_zona_limpia_resumen_mensual.csv`

- `zona_limpia/outputs/comparacion_com_zona_limpia_resumen_cluster.csv`

La corrida con `version_cluster = v2026_05_25`, excluyendo
enero y febrero de 2026 del analisis Zona Limpia, genero 642.248 filas
`cluster_id`/`dia` con evento COM o Zona Limpia.
Se conserva `Voluminosos` como categoria separada y no como
problema comparable estricto con COM.

La tabla completa sirve tambien para medir cobertura, pero la
comparacion de coincidencia debe hacerse solo con
`universo_comparable_zl == TRUE`, es decir, donde Zona Limpia
tuvo visita efectiva. Los casos `no_visitado`,
`no_se_encuentra` y `no_se_pudo_realizar` quedan
como falta de validacion, no como acuerdo o desacuerdo con COM. Los
meses `202601` y `202602` se excluyen de los
analisis por problema claro de registro/cobertura.

