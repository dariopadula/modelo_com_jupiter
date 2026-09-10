# T004 - Base ampliada COM para analisis Zona Limpia

Estado: finalizada

Prioridad: alta

Area: datos / zona limpia / auditoria

Fecha de creacion: 2026-07-01 Fecha de cierre: 2026-07-01

### Contexto

Los datos COM incluyen incidentes que comienzan con
`Zona limpia`. Estos registros no forman parte del target
actual del modelo, pero son relevantes para auditar la seleccion de
contenedores problematicos realizada por un privado. La categoria agrupa
situaciones distintas: problemas encontrados y resueltos, visitas
registradas como limpio y casos donde no se encuentra el contenedor.

### Plan propuesto

- Mantener intacta la salida actual `data/parquet/com/`, filtrada a los incidentes usados por el modelo.

- Crear una salida ampliada `data/parquet/com_completo/` con incidentes del modelo y registros `Zona limpia`.

- Homogeneizar etiquetas de Zona Limpia con una funcion especifica `normalizar_incidente_zona_limpia()`.

- Agregar indicadores para distinguir incidentes usados por el modelo y registros Zona Limpia.

- Crear scripts y diagnosticos propios dentro de `zona_limpia/`, separados de los scripts globales.

### Criterio de finalizacion

Existe una base `com_completo` reproducible y un
diagnostico inicial de etiquetas `Zona limpia` que permita
definir el mapeo final sin alterar el pipeline del modelo ni la app
operativa.

### Notas

El mapeo fino de categorias Zona Limpia queda pendiente de revision
luego de observar las frecuencias reales, porque hay categorias que se
solapan.

Se creo `zona_limpia/` con scripts propios, se genero
`data/parquet/com_completo/` y se guardaron diagnosticos
iniciales en `zona_limpia/outputs/`.

