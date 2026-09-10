# Estructura de datos

Los datos de esta carpeta se cargan localmente o en Cloudera y no se versionan
en Git. Se conservan solamente la estructura y los scripts fuente ubicados
dentro de ella.

La estructura de trabajo esperada es:

```text
data/
|-- parquet/
|   |-- com/
|   |-- com_completo/
|   `-- levante/
|-- processed/
|-- raw/
|   `-- inumet/
`-- reference/
    |-- clusters/
    `-- feriados/
```

Los scripts crean las subcarpetas de salida cuando las necesitan. Los datos
especificos de ejecucion de la app se publican directamente en
`app_operativa_v2/data/`.
