# T008 - Integrar variables territoriales censales a clusters

Estado: finalizada

Prioridad: alta

Area: datos / territorio / features

Fecha de creacion: 2026-07-01 Fecha de cierre: 2026-07-01

### Contexto

Para comparar modelos basados en COM y Zona Limpia, y para estudiar
sesgos de reclamo o seleccion de visita, se necesita una capa
territorial fija por `cluster_id`. En
`shp/Marco2011_SEG_Montevideo_Total/` esta disponible el
shape de segmentos censales de Montevideo del Censo 2011, con poblacion,
hogares, viviendas y variables de NBI.

La informacion territorial debe agregarse una vez por version de
cluster, no recalcularse dentro de cada tabla diaria. Esto permite usar
las mismas variables en modelos COM, modelos Zona Limpia, propension de
visita y mapas.

### Plan propuesto

- Leer el shape de segmentos censales 2011.

- Calcular area geometrica y densidades por segmento: densidad de poblacion;

- densidad de hogares;

- densidad de viviendas.

- Construir un centroide operativo por cluster usando el promedio de posiciones del cluster.

- Asignar cada cluster al segmento censal del centroide.

- Calcular diagnosticos de mezcla territorial usando todas las posiciones del cluster: segmento principal por cantidad de posiciones;

- cantidad de segmentos tocados por el cluster;

- porcentaje de posiciones en el segmento principal;

- bandera `cluster_multisegmento`.

- Guardar una tabla versionada por `version_cluster`/`cluster_id`.

### Criterio de finalizacion

Existe una salida reproducible
`data/processed/cluster_territorial/cluster_segmento_censal/`
con variables demograficas y territoriales fijas por cluster, mas
diagnosticos de cobertura y clusters multisegmento.

### Notas

La primera version usa el segmento del centroide para asignar
variables demograficas. Los clusters que cruzan mas de un segmento
quedan identificados para evaluar luego si conviene usar ponderacion por
posiciones.

Se creo
`scripts/construir_cluster_territorial_segmento_censal.R`. La
salida principal es
`data/processed/cluster_territorial/cluster_segmento_censal/`,
con resumenes en
`data/processed/cluster_territorial/resumen/`.

La corrida con `version_cluster = v2026_05_25` genero
9.168 clusters, todos con segmento censal asignado por centroide. Se
identificaron 471 clusters multisegmento, equivalentes al 5,1% del
total.

