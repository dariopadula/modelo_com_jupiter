# T007 - Explorar sesgo geografico y demografico de no reclamo COM

Estado: pendiente

Prioridad: media

Area: zona limpia / sesgo / investigacion futura

Fecha de creacion: 2026-07-01

### Contexto

La comparacion entre Zona Limpia y COM abre una pregunta mas amplia:
COM puede subrepresentar problemas en zonas donde hay menor propension a
reclamar, diferencias culturales sobre que se considera reclamable,
menor acceso a canales de reclamo o menor confianza en que reclamar
produzca una respuesta. Esto puede generar sesgos geograficos y
socioeconomicos en el target del modelo.

Zona Limpia, cuando hay visita efectiva, puede funcionar como una
fuente observacional complementaria para estimar problemas no
reclamados. En particular, los casos donde Zona Limpia detecta un
problema comparable y COM no registra reclamo son candidatos a medir
sesgo de no reclamo.

### Plan propuesto

- Usar los resultados de T006 para identificar clusters/dias con problema observado por Zona Limpia sin reclamo COM.

- Agregar la informacion por cluster, mes y zona geografica.

- Explorar si la brecha Zona Limpia vs COM varia territorialmente.

- Evaluar cruces futuros con variables socioeconomicas, demograficas o proxies territoriales disponibles.

- Definir si esta brecha debe usarse solo como diagnostico o tambien como insumo para ajustar targets, calibracion o interpretacion del modelo.

### Criterio de finalizacion

Queda documentado un diagnostico inicial de brecha de no reclamo COM,
con comparaciones territoriales y una decision sobre si corresponde
incorporarla al proceso de modelado, a la app o solo a reportes
analiticos.

### Notas

Esta tarea depende de T006. No conviene avanzar sobre inferencias de
sesgo antes de tener una tabla validada de comparacion COM vs Zona
Limpia por `cluster_id`/`dia`.

