# Operacion incremental COM R05

Estado: motor y prueba local finalizados el 21 de octubre de 2026. Es una validacion controlada sobre features historicas R04 con marcas de frescura sinteticas; no certifica fuentes nuevas ni habilita operacion productiva. R06 sigue pendiente.

## Flujo implementado

`R/operacion/scoring_incremental_com.R` procesa los dias posteriores al estado inicial. Para cada dia exige una marca de levantes disponible al menos hasta las 01:00 de Montevideo y cierre COM declarado hasta D-2. Si una marca no alcanza, registra el motivo, bloquea los dias siguientes y conserva el estado hasta el ultimo dia procesado.

Las predicciones previas se identifican por dia y cluster. Un dia previo debe tener el universo completo; no se vuelve a puntuar. Se verifica que score, ranking y flags sigan iguales despues de agregar observados. Un cierre posterior puede completar los observados. `R/operacion/estado_com.R` construye el estado agregado de clusters desde las features retenidas.

El motor recibe la historia de features completa hasta el periodo a puntuar, el bundle R03, un estado inicial y las marcas declaradas. El estado devuelto y las predicciones sirven como checkpoint para la siguiente llamada. Esta version reconstruye el resumen del estado desde las features retenidas; no trunca historia ni optimiza almacenamiento.

## Uso aislado

El ejecutable `scripts/scoring_com_incremental.R` recibe dos rutas: un paquete RDS de entrada y una ruta nueva para el resultado. El paquete contiene:

- `features`: tabla historica R04 con version espacial uniforme;
- `model`: bundle reducido COM D-2;
- `state`: estado inicial generado con `rf_build_com_state()`;
- `marks`: `levante_available_through` (POSIXct), `com_complete_through` (Date), `timezone = "America/Montevideo"` y `cutoff_policy = "01:00_America/Montevideo_R04"`;
- `through_day`: ultimo dia que se intenta procesar;
- opcionales `predictions` (salida previa) y `universe_n`.

El resultado RDS incluye `predictions`, `state`, `controls`, `state_day` y `state_closed_through`. El ejecutable escribe a una ruta nueva y detiene si ya existe. No lee fuentes ni publica en la app.

Comando de prueba automatica, desde `reconstruccion/`:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' --vanilla tests/test_scoring_incremental_com.R
```

## Validacion y limites

La prueba usa el bloque historico R04 del 29 al 31 de marzo de 2026. Las marcas de frescura son sinteticas y se declaran solo para probar las reglas del motor. Verifica equivalencia entre bloque de tres dias y tres llamadas sucesivas, repeticion, bloqueo ante cierre atrasado, actualizacion tardia de observados, inmutabilidad de scores, falta de cierre y politica de corte incorrecta.

El cierre del snapshot R04 permanece desconocido. Los levantes historicos preparados tampoco verifican el efecto del nuevo corte 01:00 sobre la inferencia del bundle legado. Por eso esta validacion prueba la operacion con marcas controladas, no el cierre de fuentes reales ni la compatibilidad del modelo con datos nuevos. Antes de una corrida operativa, esas evidencias deben estar disponibles. La app R03 no consume estos resultados; R08 y R09 cubren el producto completo y su publicacion.

Fuentes migradas: `funciones/scoring_operativo_utils.R` (construccion del estado y ciclo de bloque) y `scripts/emular_scoring_operativo_bloque_cluster_dia.R` (orden de procesamiento, bloqueos y observados). Los originales no se modificaron.
