# Datos de ejecución de la app

Esta carpeta no se versiona, salvo este archivo. Los procesos del proyecto
publican aquí las salidas que consume `app_operativa_v2`.

## Estructura

- `operacional/`: predicciones y controles del último proceso de scoring.
- `historico/`: serie agregada COM y detalle por cluster, día y modelo.
- `referencia/maestro_clusters/`: coordenadas y atributos territoriales mínimos.
- `referencia/barrios_mvd_23_pg.gpkg`: geometría de barrios, copiada desde la
  fuente geográfica porque no se genera dentro del proyecto.

Los constructores de historico y del maestro territorial validan en staging
antes de publicar. En Cloudera debe conservarse exactamente esta estructura
relativa.

La misma estructura puede alojarse fuera del proyecto bajo el prefijo S3
`dario/modelo_com_app/data/`. La selección entre la copia local y el Object
Store se realiza mediante `APP_DATA_SOURCE`; el contrato de carpetas y columnas
no cambia.
