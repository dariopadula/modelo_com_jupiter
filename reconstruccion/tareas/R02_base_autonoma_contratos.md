# R02 - Base autonoma y contratos

- Estado: finalizada
- Prioridad: alta
- Dependencias: R01

## Contexto y objetivo

Convertir la estructura documental en una base funcional minima, sin migrar todos los componentes.

## Fuentes originales concretas

- [Renviron.example](../../Renviron.example)
- [funciones/backend_local_s3_utils.R](../../funciones/backend_local_s3_utils.R)
- [app_operativa_v2/run_app.R](../../app_operativa_v2/run_app.R)
- [documentacion/contrato_fuentes_backend_local_s3.qmd](../../documentacion/contrato_fuentes_backend_local_s3.qmd)
- [documentacion/contrato_datos_app_operativa_v2.qmd](../../documentacion/contrato_datos_app_operativa_v2.qmd)

## Entradas

Referencia R01 y contratos conceptuales.

## Salidas

Configuracion validada, entradas minimas, contratos ejecutables y manifiesto de dependencias.

## Plan propuesto

Reutilizar estructura R00; resolver raiz propia, configuracion explicita y contratos; documentar entorno sin secretos.

## Validacion

Arranque desde raiz nueva; errores claros; ninguna importacion ejecutable del codigo anterior.

Estado de validacion: ejecutada, satisfactoria el 2026-10-20.

Evidencia: [base R02](../cerebro_rf/base_r02.md). Arranque local R02_BASE_OK, suite de 26 comprobaciones R02_TESTS_OK y copia minima desde directorio ajeno R02_AUTONOMIA_OK. Solo R base; sin instalaciones, lecturas de datos ni conexiones. Cada comando demoro aproximadamente 5-6 segundos. Sin validaciones obligatorias pendientes de esta base local; servicios reales y autonomia del sistema completo siguen en R09/R10.

Archivos funcionales: R/acceso/configuracion.R, R/registro/contratos.R, tests/validar_base.R, tests/test_base.R. Ejemplos DCF y manifiesto de dependencias en config/. Contratos cubren descriptores de modelo/publicacion y tablas minimas de features/predicciones/serie; no implementan adaptadores.

## Criterio de finalizacion

Base minima y validaciones rapidas pasan sin copiar componentes completos.

## Notas y decisiones pendientes

No se reinstalaron dependencias ni se extendio infraestructura. R03 sigue pendiente de nueva instruccion. La configuracion local queda confinada a la raiz nueva; no se importan modulos originales. Ver limites y precedencia en la evidencia enlazada.

Aplicar [politica de pruebas y corridas largas](../cerebro_rf/reglas_trabajo.md). No finalizar con validaciones obligatorias pendientes. No ejecutar la tarea siguiente sin instruccion.

[Volver al indice](index.md)

