# Ejecución del sistema

Esta carpeta contiene únicamente puntos de entrada del sistema nuevo. El recorrido R04 y la app R08 son verificaciones separadas en esta etapa:

1. `preparar_datos_com.R` prepara fuentes crudas o reutiliza tablas históricas preparadas y construye asignaciones, base y features propias.
2. `predecir_com.R` consume las features R04 con validación vigente y el bundle fijo, calcula scores y genera `producto_com_actual.rds`.
3. `run_app.R` abre la interfaz completa R08 sobre su publicacion local; todavía no consume `producto_com_actual.rds`. La coordinación de ambos recorridos se resolverá en R10.

R08 tiene un piloto importado de dos fechas en `runtime/r08_app/publicacion_piloto`. Para iniciarlo desde `reconstruccion/`:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' --vanilla scripts/run_app.R
```

El lanzador verifica paquetes y manifiesto `ready`, y usa el piloto por defecto. Para otra publicacion directa, definir `RF_APP_PUBLICATION`. Para un almacen versionado local, definir `RF_APP_STORE`; para S3, `APP_DATA_SOURCE=cloudera_s3` y su configuracion. La app fija la version al arrancar. Escucha por defecto en `http://127.0.0.1:3843`; detener con Ctrl+C. R08 finalizada con historico completo y revision aprobados; ver [productos R08](../cerebro_rf/productos_app_r08.md).

El motor incremental R05 se ejecuta aparte con `scoring_com_incremental.R <entrada.rds> <salida_nueva.rds>`. Su paquete debe incluir historia completa de features, bundle, estado inicial y marcas contractuales. Solo se validó con cierres sinteticos; no alimentar con el snapshot R04 como si su cierre estuviera declarado ni conectar el producto incremental a la app. Ver [alcance y contrato R05](../cerebro_rf/operacion_com_r05.md).

Desde la raíz de reconstruccion/, en PowerShell:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' --vanilla scripts/preparar_datos_com.R
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' --vanilla scripts/predecir_com.R
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' --vanilla scripts/run_app.R
```

Si se modifican los derivados del bloque piloto, renovar su validación con tests/test_datos_com_r04.R antes de inferir. Esa comparación de equivalencia no forma parte de la futura operación diaria. [Alcance, insumos y comandos R04](../cerebro_rf/datos_com_r04.md).

Todavía no es el pipeline completo: el ejecutor integral se construye/verifica en R10. R06-R08 finalizadas; R09 implementada con validacion remota pendiente. R05 aporta el motor incremental COM con validacion local acotada.

R09 agrega `extraer_fuentes.R`, `publicar_entrega.R`, `materializar_entrega.R`, `publicar_productos.R` y `activar_publicacion.R`. Los tres selectores de backend son independientes. Publicar productos no activa automaticamente salvo argumento `activar`; rollback explicito con `activar_publicacion.R <almacen_local> restaurar`. Requisitos, limites y comandos reales aislados en [R09](../cerebro_rf/acceso_publicacion_r09.md). No ejecutar placeholders ni asumir que una prueba simulada demuestra acceso remoto.

Pruebas en [tests/](../tests/); importaciones y comparaciones de migración en [herramientas_migracion/](../herramientas_migracion/). Esas herramientas no se llaman desde la ejecución operacional.

Entrenamiento separado: `entrenar_modelo.R <entrada.rds> <directorio_salida_nuevo>` ajusta solo COM reducido D-2 o ZL operativo_segmento, según el paquete propio. Produce un candidato, métricas y splits; no reemplaza modelos activos ni ejecuta operación diaria. [Requisitos, preparador y comandos R06](../cerebro_rf/entrenamiento_r06.md). Pruebas pequeñas y entrenamientos completos aprobados para R06; consultar los CSV corregidos de la corrida 20261022_102731.

Agregado R07: `preparar_agregado.R <insumos.rds> <bases_nuevas.rds>` construye features/target desde canónicos; `predecir_agregado.R <bases_o_muestra.rds> <bundle.rds> <salida_nueva.rds>` produce las series fuera del período de entrenamiento. `entrenar_agregado.R <bases.rds> <directorio_nuevo>` genera el compuesto candidato con OOF A0 y selección/refit P3. [Requisitos y corrida completa R07](../cerebro_rf/agregado_r07.md). Inferencia fija, pruebas pequeñas y corrida completa R07 aprobadas; candidato no promovido.

