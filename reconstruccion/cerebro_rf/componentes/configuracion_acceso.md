# Configuración y acceso

Estado: configuracion R02 y adaptadores R09 implementados y probados localmente/S3 simulado. Comprobacion real pendiente de ubicaciones y acceso. Veanse [base R02](../base_r02.md) y [acceso R09](../acceso_publicacion_r09.md).

Resolver entorno, entrada y almacenamiento sin cambiar transformaciones.

## Entrada y salida

Configuración validada, rutas y selectores; salida: lectura acotada de tablas/objetos y extracción Impala.

## Contrato y límites

Origen, destino y lectura app independientes; no inferir cierre desde último evento.

## Fuentes para migrar

- [funciones/backend_local_s3_utils.R](../../../funciones/backend_local_s3_utils.R)
- [funciones/configuracion_impala.R](../../../funciones/configuracion_impala.R)
- [funciones/cargar_datos_com.R](../../../funciones/cargar_datos_com.R)
- [funciones/cargar_datos_levante.R](../../../funciones/cargar_datos_levante.R)

Tareas: R02, R09. Ver [índice](../../tareas/index.md). Evidencia, limites y comandos reales en la nota R09; el simulador no valida CML ni Impala reales.

[Volver al cerebro](../index.md)

