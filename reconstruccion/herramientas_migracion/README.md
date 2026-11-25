# Herramientas de migración

Procesos puntuales que inspeccionan o importan datos del sistema anterior. No forman parte del pipeline operacional y requieren fuentes originales explícitas.

- inspeccionar_referencia_r01.R: metadatos y muestra local de referencia R01. No actualiza automáticamente el manifiesto congelado.
- preparar_muestra_com_r03.R: verifica hash de modelo, importa contexto acotado y compara scores antes de preparar la muestra COM. Rechaza sobrescribir la muestra existente.

No ejecutar como parte del arranque de app ni de la inferencia cotidiana. Consultar la ficha de tarea y [reglas](../cerebro_rf/reglas_trabajo.md) antes de usarlas.
