# Referencias y asignaciones

Estado: funciones de asignación migradas y validadas en R04; referencia espacial y mapa histórico estables reutilizados. No se regeneraron clusters ni cruces territoriales. Cobertura espacial integral aún no certificada. Ver [evidencia](../datos_com_r04.md).

Mantener identidad espacial, territorio y elegibilidad.

## Entrada y salida

Referencia espacial estable, shapes y fuentes preparadas; salida: mapa posiciones/clusters y asignaciones COM/ZL.

## Contrato y límites

No regenerar clusters por corrida; preservar versión espacial y reglas de distancia/elegibilidad.

## Fuentes para migrar

- [scripts/asignar_clusters_posiciones_nuevas.R](../../../scripts/asignar_clusters_posiciones_nuevas.R)
- [scripts/asignar_com_contenedores_clusters.R](../../../scripts/asignar_com_contenedores_clusters.R)
- [scripts/construir_cluster_territorial_admin.R](../../../scripts/construir_cluster_territorial_admin.R)
- [scripts/construir_cluster_territorial_segmento_censal.R](../../../scripts/construir_cluster_territorial_segmento_censal.R)

Tareas: R04. Ver [índice](../../tareas/index.md). Evidencia de migración y equivalencia: pendiente; registrar en la ficha correspondiente.

[Volver al cerebro](../index.md)

