# T031 - Publicar el proyecto y completar la replica en Cloudera

- Estado: finalizada
- Prioridad: alta

## Contexto

El proyecto quedo integrado al flujo local -> Git -> Cloudera. El repositorio
publico en GitHub contiene el codigo acordado y su clon en Cloudera sirve la
app v2.

La app v2 concentra sus datos de ejecucion en `app_operativa_v2/data/`. Esos
datos, al igual que los datos generales y resultados pesados, se transfirieron
a Cloudera por fuera de Git.

## Avance 2026-09-10

- Las credenciales pasan a `.Renviron`, excluido de Git.
- `Renviron.example` conserva el contrato de configuracion sin secretos.
- `.gitignore` usa una lista explicita de carpetas y documentos publicables.
- Se excluyen la app anterior, `AGENTS.md`, archivos de RStudio, datos pesados y
  `zona_limpia/outputs/`.
- La estructura vacia de `data/` se conserva con archivos `.gitkeep` y un
  `README.md`.
- Los datos especificos de la app se generan directamente dentro de
  `app_operativa_v2/data/`.
- El usuario creo el repositorio publico en GitHub y lo clono en Cloudera.

## Plan Ejecutado

1. Revisar los archivos del primer commit y excluir secretos y datos pesados.
2. Vincular el repositorio local con GitHub y publicar `main`.
3. Cargar en Cloudera los datos requeridos por fuera de Git, conservando las
   rutas relativas.
4. Instalar las dependencias R y unificar `R_LIBS_USER` en Cloudera.
5. Validar los datos, la sesion Shiny y la aplicacion desplegada.

## Avance 2026-09-11

La validacion de datos y sesion en Cloudera finalizo con `HISTORICO_OK` y
`SESSION_OK`. El primer despliegue fallo porque Cloudera ejecuto
`app_operativa_v2/run_app.R` desde la raiz sin pasar `--file`; el lanzador
interpretaba entonces la raiz como `appDir`.

Se ajusto el lanzador para localizar `app_operativa_v2/app.R` tanto desde la
raiz del proyecto como desde la propia carpeta de la app. La prueba local desde
la raiz inicio correctamente en `127.0.0.1` y el puerto configurado.

Las dependencias R se instalaron en la biblioteca persistente del proyecto y
`R_LIBS_USER` quedo configurado en el `.Renviron` local de Cloudera. Las pruebas
finalizaron con `HISTORICO_OK` y `SESSION_OK`. La aplicacion quedo en estado
`Running`; se verifico en navegador que carga la interfaz y muestra los mapas.

El repositorio local quedo limpio sobre `main`, vinculado a GitHub. La revision
de archivos versionados confirmo que no contiene `.Renviron`, Parquet ni
GeoPackage. Los datos se transfirieron mediante upload por fuera de Git.

## Criterio De Finalizacion

- El codigo acordado esta publicado en el repositorio sin secretos ni datos
  pesados.
- Cloudera contiene el codigo y los datos en la estructura relativa definida.
- La app v2 inicia y supera sus validaciones basicas en Cloudera.

## Cierre

Se cumple el criterio de finalizacion: codigo publicado sin datos pesados,
estructura relativa replicada, dependencias disponibles y app validada en
Cloudera. La rotacion de las credenciales locales anteriores sigue siendo una
recomendacion administrativa independiente del despliegue.
