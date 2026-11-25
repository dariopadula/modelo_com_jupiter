# Recorrido COM R03

Estado: **R03 finalizada**. Pruebas automáticas aprobadas y revisión visual general confirmada por el usuario el 20 de octubre de 2026: abrió la app reducida y parece funcionar bien. No se presume ejecución de cada paso del checklist. Las referencias posteriores a impedimentos visuales documentan intentos previos, ya resueltos mediante revisión local. R04 queda pendiente.

## Alcance implementado

Primera sección vertical sobre un bloque retrospectivo real, no una operación diaria completa. El producto contiene los 50 primeros clusters COM del 31/03/2026; el universo de referencia de ese día tiene 7.996 clusters. Se importaron 9.011 filas de features para esos IDs, con hasta 180 días de contexto, aplicando filtros antes de materializar. No se entrenó ni se abrió el test nuevo T032.

Se migraron únicamente preparar_matriz, agregar_features_logistico_reducido y aplicar_rezago_historia_reclamos de funciones/modelos_utils.R a [receta propia](../R/features/com_receta.R). El [adaptador COM](../R/modelos/com_logistico.R) reproduce preparación, imputación/estandarización y producto logístico con coeficientes fijos. No tiene dependencias ejecutables al código original.

El bundle de inferencia excluye fit y datos de entrenamiento: conserva features, prep, coeficientes, rezago y versión espacial. Su hash original se verificó contra R01; el hash del bundle reducido y del producto quedan en [informe de equivalencia](../config/equivalencia_com_r03.json). El bundle reducido es un derivado de inferencia, no una copia binaria ni un nuevo entrenamiento.

La [app](../app/app.R) solo lee el producto preparado. La selección está separada del adaptador y se comparte entre mapa, lista y scores mediante un módulo UI/server. Muestra fecha y tamaño de la muestra; los porcentajes se aplican a sus 50 filas. Ranking y flags top conservan el denominador del universo de referencia. ZL, agregado, cupos barriales e histórico completo permanecen explícitamente pendientes; no se simulan resultados.

## Evidencia automática

- Bloque 31/03: error máximo absoluto de score **0**, con tolerancia previa 1e-10; mismo orden y ranking. Flags top, selecciones globales por umbral/cantidad/porcentaje y estados observados coinciden con la referencia del bloque.
- Coordenadas del maestro transformadas de EPSG:32721 a EPSG:4326, 50 clusters con coordenadas válidas.
- R03_COM_OK: comparación de scores, ranking, flags, estados, selección vacía/empates, versión espacial inválida y reactividad con shiny::testServer.
- R02_TESTS_OK: 26 comprobaciones de regresión de la base.
- La app inició en 127.0.0.1:3843. El navegador integrado falló por timeout y la comprobación de acceso local al socket fue rechazada por restricciones del entorno. No hubo aprobación visual de mapa/lista/scores.

Los estados y metadatos retrospectivos de observación se preservan desde la publicación; **no se reconstruyó ni se certificó su cierre operativo**. El campo de fecha de reclamos del legado no se convierte en prueba de disponibilidad D-2.

## Diferencia detectada en mayo

El primer intento sobre el 24/05/2026 con el mismo modelo y features canónicas actuales produjo diferencia máxima 0,008730778733081257 y ranking distinto. La referencia no fue sobrescrita ni se toleró el error. El día 31/03 sí coincide exactamente. No está determinada la causa de la diferencia de mayo: puede involucrar cambios de insumos o contexto, y requiere comparación dirigida antes de ampliar el período (R04/R05). Esta evidencia no autoriza declarar equivalencia global del histórico.

Otros problemas de preparación corregidos: hash por conexión R en vez de lectura nativa de digest, indexado de data.table y serialización de la clase hash. El producto quedó validado y el JSON se completó tras corregir la serialización. No se realizaron reentrenamientos.

## Comandos rápidos y revisión pendiente

Desde la raíz del repositorio, con paquetes ya instalados:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' --vanilla reconstruccion/tests/test_com_r03.R
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' --vanilla reconstruccion/scripts/predecir_com.R
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' --vanilla reconstruccion/scripts/run_app.R
```

Abrir http://127.0.0.1:3843 en un navegador local. Si el puerto está ocupado, fijar APP_PORT a otro puerto libre antes del comando.

Ajuste de arranque: run_app.R ahora anuncia inicio/dirección, verifica paquetes y producto, y abre el navegador por defecto. Mantener la consola abierta; Ctrl+C detiene la app. RF_OPEN_BROWSER=0 permite probar el servidor sin abrir ventanas. Se comprobó el arranque con dirección explícita y `Listening on http://127.0.0.1:3843`; no se certifica todavía la revisión visual del usuario. El reporte de ausencia de salida en su PowerShell no se pudo reproducir; usar la ruta absoluta del script evita depender del directorio actual.

Revisión del usuario necesaria:

1. Verificar la fecha 31/03/2026, aviso de muestra y pendientes ZL/agregado.
2. En Mapa, cambiar entre umbral, cantidad fija 10 y porcentaje 10 %; comprobar puntos sin errores y resumen coherente (10 y 5 seleccionados respectivamente).
3. En Lista, comprobar que los IDs y cantidades corresponden a esa selección, con barrio, score, ranking y estado observado.
4. En Scores, comprobar histograma y línea de umbral; probar umbral 1 y cantidad 0 sin fallos de interfaz.
5. Compartir resultado o captura. Solo tras revisión satisfactoria se puede finalizar R03; no ejecutar R04 automáticamente.

## Reproducibilidad y destinos

[Puente de importación](../herramientas_migracion/preparar_muestra_com_r03.R): requiere raíz original explícita y verifica el hash R01; es la única herramienta R03 que consulta el código/datos anteriores. Puede ejecutarse con día opcional; el default validado es 2026-03-31. Rechaza sobrescribir runtime/r03_com/ existente. Para este bloque el cálculo fue acotado y sin corrida costosa; no ampliar automáticamente a todo el universo/historia.

La app y las pruebas posteriores usan solo archivos propios de runtime/r03_com/: entrada, bundle reducido, maestro, referencia y productos. Tras el ordenamiento acordado, scripts/predecir_com.R genera producto_com_actual.rds y la app lo lee; producto_com.rds sigue congelado como referencia. Inspectores/importaciones están en herramientas_migracion/ y validaciones en tests/. No se modificaron publicaciones originales. runtime sigue excluido de Git; aún debe resolverse el respaldo/versionado de reconstruccion/.
