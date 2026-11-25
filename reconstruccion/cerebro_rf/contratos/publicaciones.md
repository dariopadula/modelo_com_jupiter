# Productos y publicación para app

Propuesto: conservar semántica de operacional/, historico/ y referencia/. Score lleva día, cluster, modelo/versión, target y ranking; agregado lleva día, nivel territorial, territorio, estimación, exposición y escenario. Observados deben conservar estado de cierre.

Una publication_id vinculará capas, modelos, referencias, rangos y controles. Local utiliza staging/activación recuperable; S3 objetos por versión y puntero estable. El lector debe fijar una versión coherente. Detección automática continua se difiere.

La app consume serie liviana, detalle particionado por fecha/modelo y maestro compacto. No debe generar features ni aplicar modelos. Las publicaciones antiguas no se reemplazan en la migración paralela.

Fuente: [contrato app vigente](../../../documentacion/contrato_datos_app_operativa_v2.qmd). Esquemas ejecutables pendientes R02/R08; activación integral R09.

[Índice](index.md)

