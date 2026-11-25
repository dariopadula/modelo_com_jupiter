# Estado actual

Fecha: 22 de octubre de 2026.

## Confirmado al cierre de R05

R00 y R01 están finalizadas. R01 congeló una referencia local con cuatro modelos inspeccionados, 19 hashes y muestras pequeñas. No se copiaron modelos ni se implementaron pipeline o app. Véase [referencia local](referencia_local_r01.md).

R02 finalizada: configuración independiente, contratos mínimos y arranque con R base. Pasaron 26 comprobaciones y el arranque de una copia mínima sin importar código anterior. Véase [evidencia R02](base_r02.md).

R03 finalizada: bundle COM de inferencia propio, receta migrada y app de muestra con mapa/lista/scores. Para 50 clusters del 31/03/2026 hay error de score cero y ranking idéntico. Pruebas automáticas aprobadas y revisión visual general del usuario confirmada tras abrir la app local. Véase [evidencia R03](recorrido_com_r03.md).

Ordenamiento acordado aplicado: scripts/ contiene ejecución (predecir_com.R y run_app.R), tests/ las verificaciones y herramientas_migracion/ las inspecciones/importaciones. Código normalizado con dos espacios y descripción de funciones. Ver [convenciones](convenciones_codigo.md). No es todavía un pipeline completo.

R04 finalizada: nueve funciones migradas de preparación/asignación/base/historia y un ejecutable preparar_datos_com.R. Bloque real con 22.013 filas y 57 variables equivalentes; inferencia consume esas features propias y conserva los 50 scores. Pasaron 16 casos de reglas y regresiones R02/R03. Nuevos levantes con corte 01:00 Montevideo, corregido por aprobación explícita; historia preparada no recalculada. Ver [evidencia R04](datos_com_r04.md).

R05 finalizada en alcance local: motor de scoring por días pendientes, estado COM, controles de frescura y observados posteriores. Tres días de bloque equivalen a tres llamadas sucesivas; repetición conserva scores; cierre insuficiente bloquea sin avanzar; cierre posterior completa observados sin cambiar scores. Pasaron pruebas R02-R05. El test usa marcas sinteticas; snapshot real sigue sin cierre declarado y la compatibilidad del corte 01:00 con el bundle legado no está comprobada. Ver [evidencia R05](operacion_com_r05.md).

## R06 finalizada

El 22/10 se acordó aceptar la migración comparando código original y reconstruido con el mismo modelo e insumos actuales. Esa prueba ZL pasó: ocho filas, 36 variables, scores con diferencia cero, rankings y flags top iguales. El usuario ejecutó los entrenamientos completos COM/ZL (21,15 y 8,61 s); se revisaron claves, splits y métricas. El AUC COM desbordaba enteros: se corrigió y recalculó sobre predicciones existentes sin reentrenar. AUC de test COM 0,7547719 y ZL 0,6298416. Consultar los CSV `metricas_corregidas.csv` de la corrida `20261022_102731`; los artefactos originales se preservaron. Los tres desvíos contra la publicación histórica siguen como procedencia pendiente para R10. Véanse [ficha R06](../tareas/R06_zona_limpia_entrenamiento.md) y [entrenamiento](entrenamiento_r06.md).

## Decisión de diseño acordada

Las piezas se desarrollarán y validarán una por una. Al completar R10, una corrida operativa coordinará actualización de datos, features, scoring, productos, validación y publicación para la app. El reentrenamiento será separado y ocasional: permitirá evaluar degradación con datos nuevos, comparar un candidato con el modelo activo y volver atrás usando versiones anteriores identificables. No se fijaron todavía frecuencia, umbrales ni política de retención. Véase [decisiones vigentes](decisiones.md).

## R07 finalizada

Receta canónica de A0/P3, adaptador de predicción, OOF mensual y selección/refit implementados. Los targets se construyen desde COM, sin consultar la app. La muestra fija del 24/05/2026 reproduce 924 segmentos y 62 barrios: diferencia total frente al CSV de 3,41e-13. Las features propias coinciden con bloques originales en 2.508 filas de fixture. Pasaron pruebas D-2, exposición, territorios, puente canónico sin app y entrenamiento pequeño de nueve folds OOF. La corrida completa del usuario 20261022_111500 fue revisada: 469.817 filas A0, 380.815 filas P3, nueve folds OOF temporalmente correctos y 44 iteraciones P3; duración 264,97 s. Claves, probabilidades y sumas barrio/Montevideo verificadas. Candidato no promovido. Véanse [evidencia y comandos R07](agregado_r07.md).

## R08 finalizada

Se migraron los modulos operativos e historicos y el constructor de productos locales. La publicacion piloto `runtime/r08_app/publicacion_piloto` esta lista para dos fechas del snapshot vigente (31/03 y 24/05/2026; 31.694 filas), con scores importados, no recalculados, y candidatos sin promover. El arranque se corrigio y `tests/test_app_r08.R` paso, incluyendo ida y vuelta de productos, servidor operativo, evolucion, evaluaciones COM/ZL, render de UI en entorno aislado y cargador de Shiny. Shiny informa que escucha en el puerto 3843. Revision visual del piloto aprobada. Intermitencia de validacion resuelta: indice heredado de Arrow, con regresion y 60 lecturas aprobadas. Snapshot completo construido y manifiesto ready verificado (509 dias, 7.902.058 filas); revision visual de la publicacion completa aprobada por el usuario; el comando aislado esta en [productos e interfaz R08](productos_app_r08.md). La verificacion HTTP desde el proceso de herramientas fue bloqueada por permisos de socket. No iniciar R09 hasta cerrar R08 y recibir instruccion.

## R09 en proceso

Acceso por propietario, entregas fuentes_v2 con cierre explicito, extractor mensual Impala y publicacion versionada recuperable implementados. La app fija una version y descarga detalle por fecha/modelo; fechas cerradas iguales en local y S3. Pasaron matriz local/S3 simulada, fallos/recuperacion, integridad, caché y HTTP de app versionada; regresion R08 y 26 comprobaciones R02 aprobadas. El usuario confirmo que aun no hay ubicaciones ni acceso remoto: Impala/S3 reales y app remota siguen pendientes obligatorios. No se ejecutaron conexiones ni se inicio R10. [Evidencia y comandos R09](acceso_publicacion_r09.md).

## Próximo paso

[R09 — Acceso dual, extraccion y publicacion](../tareas/R09_acceso_publicacion.md), en proceso, pendiente de validacion remota cuando haya ubicaciones confirmadas. La [tarea actual](../tareas/actual.md) enlaza la ficha.

## No verificado

La equivalencia numérica COM se comprobó únicamente en el bloque de marzo. En mayo los siete campos resumidos coinciden, pero sigue la diferencia de score (máximo 0,00873078); falta el vector completo para atribuir causa. No ampliar equivalencia ni corregir scores históricos por inferencia. Nuevas fuentes con corte local requieren evaluación del efecto antes de operación. Persisten tres diferencias ZL frente a la publicación histórica, aunque con insumos iguales su implementación coincide. A0/P3 pasa en muestra fija, fixtures y corrida completa; su candidato no se promovió. No se probó Cloudera ni cobertura espacial integral. Cierre contractual del snapshot desconocido: no habilita scoring diario.

## Convivencia con la versión original

El backlog T034-T040 permanece en el [plan original](../../tareas/PLAN_pipeline_local_s3.md): T034 finalizada y T035-T040 pendientes. No se copia aquí ni se considera completado por avances R. Consultarlo solo cuando una tarea R necesite una capacidad concreta; registrar entonces procedencia y evidencia en esa ficha. No ejecutar una tarea T sin indicación explícita. Los otros pendientes originales siguen en [TAREAS.md](../../TAREAS.md).

Al retomar: R09, con validacion local aprobada y comprobacion remota diferida por el usuario porque los datos de ingesta aun no estan subidos. Configuracion reunida en [`.Renviron.example`](../.Renviron.example) y lectura real comprobada con readRenviron/rf_config (R09_ENV_EXAMPLE_OK). --vanilla omite .Renviron. R10 no iniciado: cualquier cambio de alcance/secuencia requiere indicacion del usuario. Preservar los limites R04-R06 y la politica de tests rapidos/corridas largas por el usuario.

## Cierre de sesion 22/10/2026

Mini auditoria de wiki realizada segun AGENTS: revisados estado y terminos de pendientes; corregidas referencias obsoletas a R02 y validaciones R08. Backlog original T034-T040 conservado aparte. No repetir entrenamientos ni construir otra vez el historico: publicacion completa en `runtime/r08_app_completa_20261022_150057/publicacion`; piloto versionado R09 en `runtime/r09_piloto_20261022_153807/almacen`. Para retomar leer este estado, tareas/actual.md y la ficha R09. Pendiente remoto detallado en [R09](acceso_publicacion_r09.md). No hubo nuevas corridas funcionales en el cierre; solo comprobaciones documentales. Git sigue ignorando reconstruccion/; inclusion pendiente, no se modifico .gitignore ni se hicieron commits.

## Límites

Se migraron procesamiento e inferencia en alcances acotados y se validaron los entrenamientos COM/ZL completos ejecutados por el usuario. Los candidatos no se promovieron ni se modificó el sistema original. Esto no demuestra autonomía del pipeline completo ni conexiones reales; esas pruebas siguen pendientes en sus tareas. Se debe resolver el versionado de reconstruccion/ antes de depender de su persistencia en Git.




