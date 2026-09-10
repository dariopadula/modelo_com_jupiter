# Arquitectura

Ver tambien [[componentes]], [[flujo_trabajo]], [[tareas_por_tipo]], [[datos_y_leakage]], [[decisiones]] y [[glosario]].

## Objetivo Del Sistema

El proyecto construye un flujo reproducible para identificar zonas calientes de problemas y reclamos asociados a contenedores. La unidad principal de modelado es `cluster_id`/`dia`.

El sistema combina:

- levantes diarios de contenedores;
- reclamos COM georreferenciados;
- referencia espacial estable de clusters;
- features historicas y operativas;
- modelos de riesgo;
- scoring operativo acumulado;
- app Shiny de solo lectura;
- analisis separados de Zona Limpia.

## Capas Principales

### 1. Ingesta Y Preparacion

Entradas principales:

- levantes desde servidor o `data/paraprobar/datos_levante.parquet`;
- COM desde servidor o `data/paraprobar/datos_com.parquet`;
- shapes territoriales en `shp/`.

Salidas base:

- `data/parquet/levante/`;
- `data/parquet/com/`;
- `data/parquet/com_completo/` solo para analisis Zona Limpia.

### 2. Espacio Y Clusters

Los contenedores se agrupan en una referencia espacial versionada. Las posiciones nuevas se asignan contra esa referencia sin modificarla.

Salidas:

- `data/reference/clusters/`;
- `data/processed/cluster_update_check/`;
- `data/processed/cluster_territorial/`.

La arquitectura usa clusters porque un reclamo puntual puede representar un problema de una zona de contenedores cercanos, no necesariamente de un unico contenedor.

### 3. Base De Modelado

La base `cluster_id`/`dia` integra reclamos COM, estado de contenedores, features de levante y memoria historica.

Salidas:

- `data/processed/com_contenedor_cluster/`;
- `data/processed/modelo_cluster_dia/base_cluster_dia/`;
- `data/processed/modelo_cluster_dia/features_cluster_dia/`.

Regla clave: las features historicas excluyen el dia objetivo y las variables de levante operativas usan sufijo `_pred`.

### 4. Modelos

Los modelos principales predicen reclamos COM (`tuvo_reclamo`) a nivel `cluster_id`/`dia`.

Modelos documentados:

- logistico completo;
- logistico reducido;
- logistico reducido D-2 para scoring matinal;
- Random Forest;
- XGBoost;
- baseline XGBoost de problema observado Zona Limpia.

### 5. Scoring Operativo

El scoring operativo corre fuera de la app. La app consume salidas ya publicadas.

Reglas principales:

- levantes disponibles hasta `D 01:00`;
- reclamos historicos cerrados hasta `D-2`;
- reclamos de `D` no entran como features;
- predicciones historicas se congelan;
- observados se completan despues, cuando COM queda cerrado.

Salidas operativas:

- predicciones acumuladas;
- control de scoring;
- metricas diarias;
- estado historico por cluster.

### 6. App Operativa

La app Shiny es de solo lectura. Muestra predicciones, mapas, historico y estado de datos. No recalcula features ni aplica modelos.

### 7. Zona Limpia

Zona Limpia es un frente analitico separado. Usa registros COM que empiezan con `Zona limpia` para auditar seleccion, problemas observados, brechas con COM y sesgos territoriales.

No altera el pipeline operativo COM ni la app.

## Flujo Simplificado

```text
Levantes + COM
  -> preparacion parquet
  -> clusters y asignacion espacial
  -> base cluster-dia
  -> features historicas y operativas
  -> modelos
  -> scoring operativo
  -> app

COM completo + Zona Limpia
  -> asignacion a clusters
  -> comparacion COM-ZL
  -> diagnosticos, modelos y reportes Zona Limpia
```

## Fronteras De Responsabilidad

- `scripts/`: procesos reproducibles del pipeline principal, modelado y scoring.
- `funciones/`: funciones reutilizables.
- `documentacion/`: reportes y decisiones tecnicas.
- `app_operativa/`: interfaz Shiny de consumo.
- `zona_limpia/`: analisis separado de Zona Limpia.
- `data/`: insumos y salidas materializadas.
- `knowledge/`: sintesis navegable, no fuente primaria.

## Pendiente De Confirmar

- Ruta productiva final de scoring (`data/processed/app/`) frente a rutas de emulacion.
- Definicion final de columnas explicativas que debe consumir la app.
- Integracion de la fuente faltante de Zona Limpia para Municipio B.
