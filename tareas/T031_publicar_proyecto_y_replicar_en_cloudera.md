# T031 - Publicar el proyecto y completar la replica en Cloudera

- Estado: en proceso
- Prioridad: alta

## Contexto

El proyecto se prepara para el flujo local -> Git -> Cloudera. El repositorio
publico en GitHub y su clon en Cloudera ya fueron creados. El codigo todavia
debe revisarse y publicarse mediante el primer commit.

La app v2 concentra sus datos de ejecucion en `app_operativa_v2/data/`. Esos
datos, al igual que los datos generales y resultados pesados, se transfieren a
Cloudera por fuera de Git.

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

## Plan Propuesto

1. Rotar las credenciales que estuvieron escritas en el codigo anterior.
2. Revisar la lista exacta de archivos que entrara al primer commit.
3. Buscar credenciales, secretos y archivos pesados antes de publicar.
4. Inicializar o vincular el repositorio local con GitHub.
5. Crear y subir el primer commit.
6. Cargar en Cloudera los datos requeridos por fuera de Git, conservando las
   rutas relativas.
7. Configurar las variables de entorno en Cloudera y validar la app v2.

## Avance 2026-09-11

La validacion de datos y sesion en Cloudera finalizo con `HISTORICO_OK` y
`SESSION_OK`. El primer despliegue fallo porque Cloudera ejecuto
`app_operativa_v2/run_app.R` desde la raiz sin pasar `--file`; el lanzador
interpretaba entonces la raiz como `appDir`.

Se ajusto el lanzador para localizar `app_operativa_v2/app.R` tanto desde la
raiz del proyecto como desde la propia carpeta de la app. La prueba local desde
la raiz inicio correctamente en `127.0.0.1` y el puerto configurado.

## Criterio De Finalizacion

- El codigo acordado esta publicado en el repositorio sin secretos ni datos
  pesados.
- Cloudera contiene el codigo y los datos en la estructura relativa definida.
- La app v2 inicia y supera sus validaciones basicas en Cloudera.

## Decisiones Pendientes

- Definir el mecanismo concreto para transferir los datos a Cloudera por fuera
  de Git.
- Confirmar las variables y rutas de conexion disponibles en Cloudera.
