# Modelos y preprocesamiento

Propuesto: adaptador con operaciones preparar, entrenar, predecir y evaluar. Bundle con identificador/versión, algoritmo, target, unidad/universo, features y orden, imputación/categorías, versión espacial, datos/split, parámetros/semilla y dependencias.

COM/ZL devuelven score por cluster/día; el compuesto agregado devuelve estimaciones por territorio/día con exposición. A0/P3 debe conservar margen base, cinco variables y OOF temporal de entrenamiento. Compatibilidad inválida debe fallar; no seleccionar binarios por fecha de archivo.

R01 identificó los artefactos locales presentes, metadatos y hashes; ver [referencia](../referencia_local_r01.md). No se certificó equivalencia numérica ni configuración remota. No sustituir modelos actuales por finalistas recientes ni activar ventanas móviles, reentrenamiento periódico, drift o reproceso masivo en la primera versión.

Fuente: [arquitectura aprobada para preparar R00](../../../auditoria_v2/03_arquitectura_v2.md). Ver [registro](../componentes/registro_modelos.md).

[Índice](index.md)

