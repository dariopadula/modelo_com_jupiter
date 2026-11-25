# Gestión de modelos

Estado: R02 valida descriptores de modelo y compatibilidad mínima. La carga de bundles y adaptadores predictivos sigue pendiente. Véase [base R02](../base_r02.md).

Identificar bundles compatibles y su procedencia.

## Entrada y salida

Modelo, receta y metadatos; salida: versión explícita validada para inferencia.

## Contrato y límites

No elegir archivo más reciente implícitamente; A0/P3 es un compuesto y requiere ambos artefactos compatibles.

## Fuentes para migrar

- [scripts/construir_app_modelos_largo_historico.R](../../../scripts/construir_app_modelos_largo_historico.R)
- [scripts/probar_xgboost_correccion_estructural_com.R](../../../scripts/probar_xgboost_correccion_estructural_com.R)
- [scripts/comparar_poda_xgboost_com.R](../../../scripts/comparar_poda_xgboost_com.R)

Tareas: R01, R02, R03, R06, R07. Ver [índice](../../tareas/index.md). Evidencia de migración y equivalencia: pendiente; registrar en la ficha correspondiente.

[Volver al cerebro](../index.md)

