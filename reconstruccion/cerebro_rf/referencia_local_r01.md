# Referencia local R01

Identificador: `local_r01_2026-10-20`. Alcance local aprobado por el usuario el 20 de octubre de 2026. Cloudera queda como comprobación posterior; no se consultó ni se atribuye su configuración a la referencia local.

## Evidencia congelada

[Manifiesto con SHA-256](../config/referencia_local_r01.json): 19 archivos identificados por ruta, tamaño y hash, incluyendo cuatro modelos presentes, fuentes del recorrido, resúmenes, CSV agregados y muestras. Congela los archivos actuales y los productos de comparación; no certifica que los binarios presentes sean los productores históricos exactos de todas las tablas.

| Producto | Confirmación local |
|---|---|
| COM | Bundle logístico reducido: rezago 2, 15 features, versión espacial `v2026_05_25`; train enero-diciembre 2025, validación enero-marzo 2026 y test histórico abril-mayo 2026. No se abrió el test nuevo T032. |
| ZL | Bundle `feature_set_zl=operativo_segmento`, 36 variables numéricas y ninguna categórica; contiene `random_dia_estratificado_mes` con fit y prep. No declara versión espacial propia en los campos inspeccionados. La publicación de muestra usa `v2026_05_25`. |
| Agregado | A0 es `mgcv::bam` con día de semana e interceptos penalizados de barrio/segmento. Corrector P3 XGBoost con media_tiempo_levante, rms_q_7, rms_w_7, delta_q_7_60 y es_feriado. Los CSV y la publicación declaran `P3_compacto`; no se probó numéricamente el compuesto. |

Los resúmenes publicados declaran COM/ZL del 2025-01-01 al 2026-05-24 y serie agregada del 2025-04-02 al 2026-05-24. Son metadatos declarados; no se recorrió la historia completa para validarlos.

## Muestra y comprobaciones ejecutadas

Muestra del 2026-05-24: ocho filas por modelo (16 en total), 16 filas del maestro para los IDs seleccionados y ocho filas de la serie `P3_compacto`. Se filtró antes de materializar. No es una muestra aleatoria ni una evaluación de calidad predictiva.

- [Predicciones](../runtime/referencia_r01/muestra_predicciones.csv)
- [Maestro](../runtime/referencia_r01/muestra_maestro.csv)
- [Serie](../runtime/referencia_r01/muestra_serie.csv)
- [Metadatos extraídos](../runtime/referencia_r01/metadatos_modelos.json)
- [Inspector reproducible](../herramientas_migracion/inspeccionar_referencia_r01.R)

Salida observada: `R01_INSPECCION_OK`. Validó tamaño de muestra, ambas familias, escenario ZL existente, maestro/serie no vacíos y concordancia de versión espacial entre COM y predicciones. R 4.5.1; Arrow 20.0.0.2, dplyr 1.1.4, jsonlite 2.0.0, XGBoost 1.7.11.1 y mgcv 1.9.3. No instaló paquetes ni entrenó. La primera ejecución falló por captura de variable en el filtro Arrow; se corrigió con evaluación explícita y la segunda pasó. Hubo advertencias de locale y traducción UTF-8 al leer A0, sin fallo de inspección; no se ejecutó inferencia A0.

Comando desde la raíz del repositorio:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' --vanilla reconstruccion/herramientas_migracion/inspeccionar_referencia_r01.R 'C:\DARIO\Git\modelo_com_jupiter'
```

El inspector usa la biblioteca R local ya instalada; no es un punto de entrada autónomo del nuevo sistema. Reejecutarlo reemplaza solo las muestras/metadatos de R01 dentro de runtime; no actualiza el manifiesto congelado. Comparar hashes antes de aceptar una nueva instantánea.

## Límites y verificaciones posteriores

- No había selectores de app/modelos definidos en el proceso inspeccionado. No se leyó `.Renviron`; tampoco se identificó un proceso Shiny activo. La referencia es la publicación local en disco, no una certificación del entorno en ejecución.
- La muestra COM contiene `fecha_reclamos_usada_hasta` igual al día objetivo y timestamps de corte que corresponden a generación retrospectiva. No demuestra que las features usen eventos del día, pero tampoco certifica disponibilidad D-2. Revisar semántica y reconstrucción acotada en R03/R05; no corregir ni replicar una inconsistencia silenciosamente.
- Equivalencia numérica de binarios frente a scores: pendiente en R03/R06/R07. Las recetas y campos inspeccionados son compatibles con el recorrido identificado, pero la correspondencia histórica no queda probada solo con nombres y hashes actuales.
- Compatibilidad predictiva A0/P3, categorías territoriales y procedencia exacta del margen: pendientes R07. No sustituir por el candidato q30 de reevaluación.
- Cloudera y S3 reales: pendientes posteriores conforme al alcance local aprobado; ver R09/R10. La exclusión Git de reconstruccion/ sigue sin resolver.

Estos límites no se consideran equivalencia aprobada ni habilitan migración automática. R01 congela una referencia local con evidencia y límites para comenzar R02 por nueva instrucción.
