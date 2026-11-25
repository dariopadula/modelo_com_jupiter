# Organización y estilo de código

Acuerdo del usuario, 20 de octubre de 2026. Aplicado al código migrado y obligatorio para las próximas tareas.

## Carpetas y ejecución

| Carpeta | Responsabilidad |
|---|---|
| scripts/ | Entradas ejecutables del sistema: preparación, entrenamiento, inferencia, publicación y arranque de app cuando estén implementadas. |
| R/ | Funciones reutilizables por responsabilidad, sin ejecutar procesos al importarse. |
| tests/ | Pruebas, comprobaciones y validaciones de arranque. |
| herramientas_migracion/ | Inspectores, importaciones y comparaciones contra el sistema anterior. No forman parte del pipeline operacional. |
| app/ | Interfaz y selección sobre productos preparados; sin entrenar ni aplicar modelos. |

No crear scripts vacíos para aparentar un pipeline terminado. Al completar los componentes habrá un punto de entrada de punta a punta; hoy existen solamente inferencia COM sobre muestra propia y arranque de app. R04 y tareas posteriores incorporarán preparación, actualización y publicación reales.

## Convenciones

- Sangría de dos espacios, sin tabuladores; espacios alrededor de operadores y después de comas.
- Líneas en blanco entre funciones y bloques lógicos. Dividir llamadas largas para facilitar lectura.
- Nombres descriptivos; una responsabilidad por función. Evitar abreviaturas salvo en herramientas pequeñas cuando el contexto sea inequívoco.
- Antes de cada función nombrada, descripción breve de su propósito, entradas y salida; documentar errores o restricciones cuando aporten información.
- Comentar decisiones y reglas temporales; evitar comentarios que solo repitan instrucciones evidentes.
- Mantener separación entre cálculo, acceso, ejecución y visualización.
- No modificar resultados al ordenar/formatear. Ejecutar pruebas de regresión pertinentes y conservar referencias congeladas.
- Mantener español correcto en textos de interfaz; evitar corrupción de tildes al procesar fuentes en Windows.

## Aplicación realizada

Inspectores R01 y preparación de muestra R03 se movieron de scripts/ a herramientas_migracion/. La validación de base pasó a tests/. Las referencias documentales fueron actualizadas. Se formatearon los 15 archivos R actuales y se documentaron sus funciones; se contrastó el árbol de expresiones antes/después de cada formateo, normalizando agrupaciones sin efecto en la evaluación.

Se agregó [scripts/predecir_com.R](../scripts/predecir_com.R): ejecuta el adaptador migrado usando entrada y bundle propios, conserva la instantánea de metadatos de la muestra y escribe producto_com_actual.rds sin tocar producto_com.rds congelado. La app lee ese producto actual. No importa datos del proyecto anterior ni entrena. La inferencia y la app son comandos separados.

El ordenamiento por sí solo no cerró R03. Posteriormente el usuario confirmó la apertura y funcionamiento general de la app reducida, completando esa revisión; R03 quedó finalizada. No se iniciaron R04 ni tareas T035-T040.

Validación posterior: COM_PREDICCIONES_OK (50 filas), R02_TESTS_OK (26 comprobaciones), R02_BASE_OK y R03_COM_OK. Enlaces, codificación y ausencia de tabuladores comprobados. Los 19 hashes R01 y el producto COM congelado permanecen intactos; no se modificaron archivos fuera de reconstruccion/.
