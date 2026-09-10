# Tareas Por Tipo

Ver tambien [[index]], [[flujo_trabajo]], [[componentes]], [[datos_y_leakage]], [[modelos_com]], [[modelo_zona_limpia]], [[scoring_operativo]] y [[zona_limpia]].

Esta nota es el router operativo de la wiki. Para cada tipo de tarea indica que leer, que archivos probablemente tocar, que documentacion actualizar y que riesgos revisar.

## Tabla Rapida

| Tipo de tarea | Leer antes | Archivos probables | Documentar en | Riesgos |
|---|---|---|---|---|
| Entender el proyecto | [[arquitectura]], [[componentes]], `README.qmd` | Ninguno | No aplica | Confundir wiki con fuente primaria |
| Cambiar flujo de datos | [[datos_y_leakage]], `documentacion/flujo_datos.qmd` | `scripts/get_*`, `scripts/construir_*`, `funciones/preparar_*` | `flujo_datos.qmd`, `TAREAS.md`, `HITOS.md` | Leakage, romper target, cambiar salidas |
| Cambiar modelo COM | [[modelos_com]], [[datos_y_leakage]] | `scripts/modelo_*.R`, `funciones/modelos_utils.R` | `modelos.qmd`, `diagnostico_variables_modelo.qmd`, `TAREAS.md`, `HITOS.md` | Comparabilidad, leakage, splits |
| Modelar volumen diario COM | [[modelos_agregados_com]], [[datos_y_leakage]], T028 | `scripts/*agregado*_com.R`, `scripts/experimentar_*_com.R`, `scripts/probar_*_com.R`, `scripts/comparar_*_com.R` | `pronostico_diario_clusters_reclamo_com.qmd`, T028 y wiki sintetica | Leakage temporal, mezclar prediccion e inferencia, duplicar metricas |
| Cambiar scoring operativo | [[scoring_operativo]], [[datos_y_leakage]] | `scripts/proceso_scoring_operativo_cluster_dia.R`, `funciones/scoring_operativo_utils.R` | `proceso_scoring_operativo.qmd`, `TAREAS.md`, `HITOS.md` | Frescura, D-2, reproceso |
| Cambiar app | [[app_operativa]], [[scoring_operativo]], `app_operativa/README.md` | `app_operativa/app.R`, `app_operativa/R/datos_app.R` | app README, `proceso_scoring_operativo.qmd` si cambia contrato | App recalculando features, contrato roto, targets mezclados |
| Analizar Zona Limpia | [[zona_limpia]], [[datos_y_leakage]] | `zona_limpia/*.R`, `zona_limpia/reportes/*.qmd` | `zona_limpia/README.qmd`, `TAREAS.md`, `HITOS.md` | Municipio B, Voluminosos, generalizacion |
| Cambiar modelo Zona Limpia | [[modelo_zona_limpia]], [[zona_limpia]], [[datos_y_leakage]] | `zona_limpia/08_*.R`, `zona_limpia/12_*.R`, `zona_limpia/reportes/13_modelo_problema_observado_zl.qmd` | `zona_limpia/README.qmd`, reporte ZL, referencia en `modelos.qmd`, `HITOS.md` | Usar COM como feature, sesgo seleccion |
| Agregar documentacion | [[mapa_documental]], [[flujo_trabajo]] | `documentacion/*.qmd`, `TAREAS.md`, `HITOS.md`, `knowledge/wiki/*.md` | Segun alcance | Duplicar en vez de sintetizar |
| Corregir bug puntual | [[componentes]], doc del componente | Script afectado | `TAREAS.md` si es relevante; `HITOS.md` si cambia resultados | Arreglar sintoma sin validar flujo |

## Checklists Por Tarea

### Cambiar Flujo De Datos

Leer:

- `documentacion/flujo_datos.qmd`
- [[datos_y_leakage]]
- `README.qmd`

Antes de tocar:

- identificar salida afectada;
- revisar consumidores aguas abajo;
- verificar si cambia unidad `cluster_id`/`dia`;
- revisar reglas de elegibilidad y cortes temporales.

Actualizar:

- `documentacion/flujo_datos.qmd`;
- `README.qmd` si cambia orden/salida principal;
- `TAREAS.md` y `documentacion/HITOS.md` si cambia comportamiento.

### Cambiar Modelo COM

Leer:

- [[modelos_com]]
- [[datos_y_leakage]]
- `documentacion/modelos.qmd`
- `documentacion/modelos_utils.qmd`
- `documentacion/diagnostico_variables_modelo.qmd`

Antes de tocar:

- confirmar target;
- confirmar split;
- confirmar features disponibles operativamente;
- si usa clima, confirmar que las variables estan cerradas en `D-1`;
- definir si el cambio afecta scoring.

Actualizar:

- `documentacion/modelos.qmd`;
- `documentacion/diagnostico_variables_modelo.qmd` si cambia seleccion de variables;
- `documentacion/proceso_scoring_operativo.qmd` si entra a scoring;
- `TAREAS.md` y `HITOS.md`.

### Cambiar Scoring Operativo

Leer:

- [[scoring_operativo]]
- [[datos_y_leakage]]
- `documentacion/proceso_scoring_operativo.qmd`

Antes de tocar:

- revisar D-2;
- revisar `D 01:00`;
- revisar estado historico;
- revisar staging, backups y lock;
- separar emulacion de produccion.

Actualizar:

- `documentacion/proceso_scoring_operativo.qmd`;
- `app_operativa/README.md` si cambia contrato de entrada;
- `TAREAS.md` y `HITOS.md`.

### Cambiar App

Leer:

- `app_operativa/README.md`
- [[scoring_operativo]]
- contrato de salida en `documentacion/proceso_scoring_operativo.qmd`

Antes de tocar:

- confirmar que la app solo lee;
- confirmar ruta `APP_DATA_PATH`;
- confirmar columnas disponibles;
- revisar si el cambio exige nuevas salidas del scoring.

Actualizar:

- `app_operativa/README.md`;
- `documentacion/proceso_scoring_operativo.qmd` si cambia contrato;
- `TAREAS.md` si corresponde.

### Cambiar Zona Limpia

Leer:

- [[zona_limpia]]
- [[modelo_zona_limpia]]
- `zona_limpia/README.qmd`
- `zona_limpia/reportes/10_sesgos_seleccion_zona_limpia.qmd`
- si hay modelado observado: `zona_limpia/reportes/13_modelo_problema_observado_zl.qmd`

Antes de tocar:

- confirmar si Municipio B debe excluirse o marcarse incompleto;
- confirmar si `Voluminosos` entra o no;
- separar `com` de `com_completo`;
- explicitar universo comparable.
- si usa clima, confirmar que es solo un experimento o documentar si pasa a baseline.

Actualizar:

- `zona_limpia/README.qmd`;
- reportes QMD si cambia lectura;
- `documentacion/HITOS.md`;
- `TAREAS.md`.

### Agregar Nueva Funcionalidad

Leer:

- [[componentes]]
- doc especifica del area;
- `TAREAS.md`.

Antes de tocar:

- definir componente propietario;
- definir salidas;
- definir documentacion fuente a actualizar;
- revisar si hay impacto en datos/modelos/app.

Actualizar:

- `TAREAS.md` al iniciar/cerrar;
- `HITOS.md` si cambia rumbo;
- documentacion tecnica especifica;
- wiki solo como sintesis posterior.

## Regla Final

Si una tarea no encaja en esta tabla, empezar por [[mapa_documental]] y [[componentes]], y dejar en `TAREAS.md` una ficha corta con contexto, plan y criterio de finalizacion.
