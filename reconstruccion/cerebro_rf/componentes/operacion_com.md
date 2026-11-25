# Operacion COM

Estado: motor incremental local implementado en R05; validado con fechas y cierres sinteticos sobre features historicas R04. No habilita ejecucion productiva, no integra fuentes reales y no publica a la app. Ver [evidencia R05](../operacion_com_r05.md).

El motor procesa fechas nuevas en orden, conserva scores previos, exige frescura declarada y agrega observados solo cuando COM declara el cierre. El estado resume historia de clusters y se persiste junto con predicciones para la siguiente llamada.

Fuentes originales: `funciones/scoring_operativo_utils.R`, `scripts/emular_scoring_operativo_bloque_cluster_dia.R` y `scripts/proceso_scoring_operativo_cluster_dia.R`. Estado del corte nuevo y cierre real: pendiente de evidencia.

[Volver al cerebro](../index.md)
