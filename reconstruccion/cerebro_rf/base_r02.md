# Base funcional R02

Estado: implementada y validada localmente el 20 de octubre de 2026. No aplica modelos, lee datasets operativos, conecta servicios ni publica resultados.

## Arranque y pruebas

Desde la raíz de reconstruccion/:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' --vanilla tests/validar_base.R config/local.dcf.example
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' --vanilla tests/test_base.R
```

En Cloudera, el equivalente es `Rscript --vanilla tests/validar_base.R config/local.dcf.example`, usando la configuración elegida. No se validó ejecución remota en R02. El ejemplo Cloudera falla deliberadamente mientras conserve placeholders.

Resultados locales: `R02_BASE_OK`, `R02_TESTS_OK: 26 comprobaciones` y `R02_AUTONOMIA_OK`. Comandos de unos 5-6 segundos cada uno. Una copia mínima de los cuatro archivos necesarios arrancó desde un directorio de trabajo ajeno al repositorio. La copia de prueba quedó en runtime/prueba_autonomia_r02/, excluida de Git. El arranque usa únicamente los módulos de su propia raíz. Hubo advertencias de locale al iniciar R, sin fallos de validación.

## Configuración y precedencia

[Configuración](../R/acceso/configuracion.R): valores predeterminados locales → archivo DCF explícito → variables de entorno reconocidas. No carga .Renviron ni descubre archivos de configuración implícitamente. Para ejecución aislada usar --vanilla. DCF es un formato de texto leído con R base; una configuración debe contener exactamente un registro y solo campos reconocidos.

Ejemplos: [local](../config/local.dcf.example) y [Cloudera](../config/cloudera.dcf.example). Los selectores INGESTA_INPUT_BACKEND, PIPELINE_STORAGE_BACKEND y APP_DATA_SOURCE son independientes; los aliases s3/cloudera se normalizan. RF_EXTRACTOR separa entrega de extracción Impala. Reutiliza nombres y semántica del contrato anterior, sin importar su código.

Valida placeholders S3 activos, ubicación del manifiesto dentro del prefijo, zona horaria y configuración requerida. Impala solo comprueba presencia del driver/configuración/credenciales del entorno; no conecta. Usuario/password no forman parte del objeto devuelto ni de los ejemplos ni del resumen de arranque. No se proporcionaron credenciales ni se realizó prueba real Impala.

RF_RUNTIME_PATH es relativa a la raíz nueva y rechaza rutas absolutas o segmentos '..'. Decisión inicial: mantener las escrituras locales del sistema nuevo confinadas a su espacio. Persistencia externa se selecciona mediante backend S3; ampliar rutas locales externas requerirá una decisión explícita. El validador de configuración no crea destinos ni descarga objetos.

## Contratos ejecutables mínimos

[Validadores](../R/registro/contratos.R), implementados con R base:

| Contrato | Comprobaciones actuales |
|---|---|
| Modelo rf_model_v1 | Identidad/versión/adaptador/target/unidad, referencia de entrenamiento/preprocesamiento, features únicas, versión espacial y disponibilidad operacional D-2/01:00/Montevideo. |
| Features | Presencia de columnas declaradas y versión espacial compatible. La receta del adaptador completará tipos, orden e imputación en R03/R06/R07. |
| Predicciones cluster/día | Columnas mínimas, clave única, fecha Date, identidades no vacías, scores finitos entre cero y uno, ranking entero positivo. No comprueba todavía política completa de empates ni observados. |
| Serie COM | Claves día/territorio/escenario, conteos válidos dentro de exposición y coherencia de suma barrios/Montevideo. Presupone producto completo por grupo, no fragmentos de una serie. |
| Publicación rf_publication_v1 | ID, modelos no repetidos, versión espacial homogénea y presencia de capas operacional/histórico/referencia. No activa una publicación ni certifica integridad de sus objetos. |

Son contratos de la futura ruta operacional; no reinterpretan retrospectivamente como conforme la muestra R01. Metadatos de cierre, observados ZL, hashes de objetos, esquema completo de detalle y activación recuperable se completan en las tareas correspondientes; R02 no sustituye R04/R08/R09.

## Dependencias y límites

[Manifiesto de dependencias](../config/dependencias.csv): base requiere solo R; las versiones observadas en R01 son referencias, no un lockfile completo. Bibliotecas de modelos y transporte están declaradas como futuras; no se instalan ni se requieren para este arranque.

El inspector de R01 sigue siendo una herramienta de migración que consulta el sistema original, no parte del arranque autónomo. No se certifica autonomía del sistema operacional completo: corresponde a R10.

Próximo paso: R03, únicamente con una nueva instrucción. La referencia local de R01 y sus 19 hashes permanecen sin cambios.
