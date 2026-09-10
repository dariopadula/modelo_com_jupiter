# Modelo Zona Limpia

Ver tambien [[zona_limpia]], [[datos_y_leakage]], [[tareas_por_tipo]], [[decisiones]] y [[glosario]].

## Para Que Sirve Esta Nota

Esta nota orienta tareas sobre el modelo de problema observado de Zona Limpia.
No reemplaza el reporte metodologico completo:

- `zona_limpia/reportes/13_modelo_problema_observado_zl.qmd`

Usarla para saber rapidamente que leer, que archivos estan involucrados y que
riesgos revisar antes de modificar el modelo.

## Que Predice

El baseline intenta estimar la probabilidad de encontrar un problema observable
si Zona Limpia visita un cluster.

No es el mismo objetivo que el modelo COM operativo. El modelo COM predice
reclamos; este modelo busca aproximar problema observado en campo.

## Target

El target es:

```text
hay_zl_problema_comparable
```

Lectura:

- `hay_zl_problema_comparable`: Zona Limpia observo `basura_fuera` o `contenedor_desbordado`.

COM no se usa como feature ni como target principal. Se conserva como evaluacion
secundaria para leer la relacion entre problemas observados ZL y reclamos.

## Universo Actual

- Visitas efectivas de Zona Limpia.
- Meses `202510`, `202511`, `202512`, `202603`, `202604`, `202605`.
- `202508`, `202509`, `202601` y `202602` excluidos por cobertura anomala.
- `Voluminosos` excluido del target principal.
- Municipio B con cobertura incompleta en la fuente actual.

## Archivos Principales

Fuente metodologica:

- `zona_limpia/reportes/13_modelo_problema_observado_zl.qmd`

Script:

- `zona_limpia/08_modelo_problema_observado_zl_xgboost.R`
- Soporta experimento opcional con clima (`USAR_CLIMA=1`) usando features INUMET hasta `D-1`.

Artefactos:

- `data/processed/modelos/zona_limpia_problema_observado_xgboost/`

Salidas de lectura:

- `zona_limpia/outputs/modelo_zl_observado_resumen_base.csv`
- `zona_limpia/outputs/modelo_zl_observado_metricas.csv`
- `zona_limpia/outputs/modelo_zl_observado_metricas_random_dia_reps.csv`
- `zona_limpia/outputs/modelo_zl_observado_metricas_targets.csv`
- `zona_limpia/outputs/modelo_zl_observado_lift.csv`
- `zona_limpia/outputs/modelo_zl_observado_importancia.csv`

Salidas exploratorias con clima:

- `zona_limpia/outputs/experimentos_clima/`
- `outputs/experimentos_clima/features_importancia_com_y_zl.csv`
- `outputs/experimentos_clima/features_clima_importancia_com_y_zl.csv`

## Lectura Actual

El baseline muestra senal aprendible, pero debil estabilidad temporal:

- split random por fila estratificado por mes/target: AUC cercano a `0,68`;
- split random por dia estratificado por mes: AUC cercano a `0,68` en validacion y `0,66` en test;
- cinco repeticiones random por dia: AUC test aproximadamente entre `0,663` y `0,681`;
- split temporal: AUC cercano a `0,60`.

El random por dia es una evaluacion intermedia: evita mezclar clusters del mismo
dia entre entrenamiento y evaluacion, pero sigue mezclando meses. La diferencia
con el split temporal sugiere que el modelo todavia no esta listo como reemplazo
de una regla operativa. Puede haber cambios de criterio, cobertura, registro o
regimen entre fines de 2025 y 2026.

El experimento con clima INUMET muestra alguna mejora en split random por fila,
pero no mejora random por dia ni temporal. Por ahora no se incorpora al baseline.

Se agrego una cascada de escenarios de features mediante `FEATURE_SET_ZL`:

- `operativo_minimo`;
- `operativo_segmento`;
- `operativo_clima`;
- `segmento_clima`;
- `amplio_actual`.

Lectura inicial: `amplio_actual` mejora los splits random, pero mezcla muchas
capas territoriales y categorias nominales. `operativo_segmento` usa menos
columnas, evita municipio/CCZ/barrio nominal y queda muy competitivo en temporal;
por ahora es el candidato parsimonioso mas razonable para seguir explorando.

## Riesgos Antes De Cambiarlo

- Usar COM como feature y contaminar un modelo que busca estar limpio de COM.
- Generalizar desde visitas de Zona Limpia a toda la ciudad sin explicitar sesgo de seleccion.
- Olvidar que Municipio B tiene fuente incompleta.
- Mezclar `Voluminosos` con problemas comparables.
- Evaluar solo con split random por fila y no mirar random por dia ni estabilidad temporal.
- Usar territorio nominal amplio como si fuera senal operativa generalizable.
- Interpretar importancia de XGBoost como causalidad.

## Relacion Con Otros Analisis

- [[zona_limpia]] resume el frente completo.
- `zona_limpia/reportes/10_sesgos_seleccion_zona_limpia.qmd` documenta sesgos de seleccion, correspondencia COM-ZL y propension.
- [[datos_y_leakage]] resume reglas de cortes temporales y features disponibles.
- [[tareas_por_tipo]] indica que documentacion actualizar si cambia el modelo.

## Pendiente De Confirmar

- Como cambia el modelo cuando se integre la fuente faltante de Municipio B.
- Como comparar el modelo ZL puro contra ajustes por propension de visita.
- Como integrar el score ZL puro junto al score COM en la app operativa.
- Si se insiste con clima, evaluar con repeticiones random por dia, sensibilidad sin `mes_calendario` e interacciones/umbrales.
