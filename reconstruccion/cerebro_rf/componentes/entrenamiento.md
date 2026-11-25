# Entrenamiento y evaluación

Estado: R06 finalizada. Inferencia ZL con insumos iguales validada y entrenamientos completos COM/ZL ejecutados por el usuario y revisados. Se corrigió el AUC COM por desbordamiento entero, sin reentrenar. Los tres desvíos contra la publicación histórica quedan como procedencia pendiente. [Resultados, comandos y alcance](../entrenamiento_r06.md).

Reproducir solo familias efectivas, sus splits y preprocesamiento. La selección vigente de ZL es `operativo_segmento` con escenario `random_dia_estratificado_mes`; la selección COM es el logístico reducido D-2 congelado en R01.

## Entrada y salida

Historia identificada y receta efectiva; salida: bundle y evaluación reproducible.

## Contrato y límites

El entrenamiento se ejecuta aparte de la actualización operativa y no corre en cada scoring. Debe poder lanzarse ocasionalmente con datos nuevos para medir degradación, crear un candidato reproducible y compararlo con el bundle activo usando ventanas/targets compatibles y sin leakage. Promover un candidato requiere aprobación explícita; al promoverlo se regeneran los scores y productos afectados. Conservar versiones identificadas del modelo activo y de versiones anteriores que permitan rollback; la retención exacta está pendiente.

Mantener OOF temporal A0; no reemplazar modelos por candidatos T032; corridas largas por usuario. La frecuencia, métricas/umbrales de degradación, aprobación de promoción y política de retención se definirán antes de automatizar reentrenamientos. No hay reentrenamiento automático en la operación diaria.

## Fuentes para migrar

- [scripts/modelo_logistico_cluster_dia_reducido.R](../../../scripts/modelo_logistico_cluster_dia_reducido.R)
- [zona_limpia/08_modelo_problema_observado_zl_xgboost.R](../../../zona_limpia/08_modelo_problema_observado_zl_xgboost.R)
- [scripts/probar_xgboost_correccion_estructural_com.R](../../../scripts/probar_xgboost_correccion_estructural_com.R)
- [scripts/comparar_poda_xgboost_com.R](../../../scripts/comparar_poda_xgboost_com.R)

Tareas: [R06 finalizada](../../tareas/R06_zona_limpia_entrenamiento.md); [R07 finalizada](../../tareas/R07_agregado_compuesto.md). A0/P3 ya tiene receta y entrenador OOF/selección/refit con fixtures aprobadas; su preparación y entrenamiento completos fueron ejecutados por el usuario y revisados (corrida 20261022_111500). [Comandos R07](../agregado_r07.md). Ver [índice](../../tareas/index.md).

[Volver al cerebro](../index.md)

