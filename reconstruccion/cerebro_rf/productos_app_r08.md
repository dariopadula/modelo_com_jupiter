# Productos e interfaz R08

Estado: revision visual del piloto aprobada por el usuario; R08 sigue en proceso hasta validar el snapshot historico completo.

## Alcance implementado

- `R/publicacion/productos_app.R` valida scores COM/ZL, claves, rankings, targets, maestro territorial y sumas del agregado. Escribe detalle historico particionado por fecha/modelo, scores operativos, serie, maestro, barrios y manifiesto `ready` al final. Rechaza sobrescribir un destino existente.
- `app/` contiene UI y servidor separados, modulos migrados de seleccion, resumen, mapa, lista, scores, evolucion y evaluacion COM/ZL. La app lee una publicacion local fija. El acceso S3 y la activacion recuperable corresponden a R09.
- `herramientas_migracion/preparar_piloto_app_r08.R` importa productos del snapshot vigente sin recalcular scores ni promover modelos. Por defecto limita la entrada a dos fechas reales; `todas` habilita el snapshot historico completo.
- `scripts/run_app.R` valida el manifiesto local y arranca la app. El piloto se sirve desde `runtime/r08_app/publicacion_piloto` salvo que `RF_APP_PUBLICATION` indique otra publicacion.
- `tests/test_app_r08.R` comprueba ida y vuelta de productos, rechazo de scores/rankings invalidos, rechazo de sobrescritura, seleccion operativa COM/ZL y evaluacion historica de ambas familias.

## Evidencia

Confirmado el 22/10/2026: la publicacion piloto tiene estado `ready`, dias 31/03/2026 y 24/05/2026, version territorial `v2026_05_25` y 31.694 filas. Su procedencia indica `snapshot_importado_app_vigente`, scores sin recalcular y candidatos sin promover. La prueba `Rscript --vanilla tests/test_app_r08.R` paso en 21 segundos; incluye productos (31.694 filas), servidor operacional, evolucion, historia COM, historia ZL, contratos de UI y carga de app.R con el cargador de Shiny. Prueba scores, rankings duplicados, targets ZL sin visita y rechazo de sobrescritura.

El arranque inicial fallo por un indice interno invalido en la serie agregada materializada desde Arrow. Reconstruir el resultado de `collect()` como `data.frame` antes de convertirlo a `data.table` resolvio el fallo. El usuario luego informo que la app no encontraba `bs_theme` y despues que no encontraba `dia_operativo` al servir la UI. Se calificaron las llamadas de `bslib` con su namespace, el lanzador desactiva la carga automatica duplicada de `R/`, `app.R` comparte explicitamente su entorno con UI/server y la fecha operativa se calcula antes de construir la UI. La prueba renderiza esa interfaz en un entorno aislado y reproduce el cargador de `runApp`. La solicitud HTTP directa desde el proceso de validacion fallo por restriccion de socket del entorno y no se toma como fallo de la app.

## Pendiente obligatorio

1. Revision visual del piloto aprobada por el usuario.
2. Importar y construir el snapshot historico completo para verificar filtros y lecturas sobre todo el periodo. Se deja esta corrida a cargo del usuario porque su duracion no esta medida.

Desde PowerShell, iniciar en `reconstruccion/` y ejecutar:

```powershell
$r08Rscript = 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe'
$r08Original = 'C:\DARIO\Git\modelo_com_jupiter'
$r08Run = Join-Path 'runtime' ('r08_app_completa_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $r08Run -ErrorAction Stop | Out-Null

& $r08Rscript --vanilla herramientas_migracion/preparar_piloto_app_r08.R `
  $r08Original (Join-Path $r08Run 'insumos') todas
if ($LASTEXITCODE -ne 0) { throw 'Fallo la importacion historica R08; compartir la salida' }

& $r08Rscript --vanilla scripts/construir_productos_app.R `
  (Join-Path $r08Run 'insumos/entrada.rds') (Join-Path $r08Run 'publicacion')
if ($LASTEXITCODE -ne 0) { throw 'Fallo la construccion historica R08; compartir la salida' }

$env:RF_APP_PUBLICATION = (Resolve-Path (Join-Path $r08Run 'publicacion')).Path
& $r08Rscript --vanilla scripts/run_app.R
```

Salida esperada de la construccion: `R08_PRODUCTS_OK` con dias y filas del snapshot y estado `ready` en `publicacion/publicacion.rds`. El proceso de app queda en primer plano; detenerlo con Ctrl+C. Confirmar que la app abre en el navegador y revisar operacion, mapa/lista/scores, evolucion, evaluacion COM y ZL. No compartir ni incluir `runtime/` en Git.

Si termina bien, comunicar la salida `R08_INPUT_OK`, `R08_PRODUCTS_OK` y cualquier error visual. Cerrar R08 actualizando esta nota y la ficha; no iniciar R09 sin una nueva instruccion.

[Tarea R08](../tareas/R08_productos_app_completa.md) | [Indice del cerebro](index.md)

## Diagnostico de la validacion intermitente

Reproducido en la quinta lectura: la conversion directa Arrow -> data.table conservaba un indice __modelo_id vacio; el filtro COM devolvia cero filas y fallaba uniqueN(version_modelo), no los rankings ni los percentiles. El constructor y el importador ahora materializan data.frame antes de data.table. El validador trabaja sobre una copia sin indices ni clave heredados, sin alterar scores ni tolerancias. Regresion con indice vacio inyectado y suite R08 completa aprobadas (salida 0); 60 lecturas/validaciones del piloto aprobadas. El manejador HTTP devuelve 200 y la fecha esperada. La importacion completa sigue a cargo del usuario; no se ejecuto ni se habilito R09.

## Historico completo construido

Corrida del usuario runtime/r08_app_completa_20261022_150057: 26.280 filas de serie importadas y 7.902.058 filas de detalle en 509 dias, del 01/01/2025 al 24/05/2026. Constructor completo aprobado; manifiesto comprobado localmente con estado ready, historia_publicada, scores sin recalcular y candidatos sin promover. Revision visual del piloto ya aprobada. Solo resta comprobar filtros y vistas historicas con esta publicacion completa; no repetir construccion. R08 sigue en proceso hasta esa comprobacion; R09 no iniciado.

## Cierre de R08

Revision visual de la publicacion completa aprobada por el usuario. R08 finalizada: pruebas, manifiesto ready e historico completo verificados. Los pendientes previos de esta nota quedan cumplidos. R09 queda pendiente, sin ejecutar.

