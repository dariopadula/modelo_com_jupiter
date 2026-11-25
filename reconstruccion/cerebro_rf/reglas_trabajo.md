# Reglas de trabajo y propuestas para AGENTS

Las restricciones siguientes fueron indicadas por el usuario para la reconstrucción. Las adiciones al AGENTS principal son una propuesta y no fueron incorporadas a ese archivo.

## Lectura y alcance

Leer AGENTS aplicable, este índice, el índice de tareas y solo la ficha autorizada. Consultar fuentes originales puntualmente; no repetir la auditoría. Una tarea por chat, sin avance automático. Actualizar ficha, índice y estado sintético cuando corresponda. Cada afirmación debe distinguir confirmado, propuesto y pendiente.

Conservar el proyecto vigente y sus publicaciones. No importar código o datos de manera masiva, promover candidatos ni abrir el test sellado T032 por tareas de infraestructura. Cambios de resultados, targets, universo o disponibilidad se deciden explícitamente.

## Ejecución y validación

Codex ejecuta pruebas pertinentes rápidas y acotadas; referencia inicial: hasta dos minutos estimados por comando. Si el alcance o duración son inciertos, no iniciar la corrida grande. No crear pruebas artificiales para documentación.

Entrenamientos completos, reconstrucciones extensas y backfills quedan a cargo del usuario. Entregar comando exacto, requisitos, destino aislado, salida esperada y duración solo si hay evidencia. Revisar luego el resultado aportado. Registrar ejecutada, fallida o pendiente del usuario. No marcar finalizada una tarea con comprobaciones obligatorias pendientes ni habilitar automáticamente dependientes.

## Documentación y estados

Estados: pendiente, en proceso, bloqueada, finalizada, descartada. Prioridades: alta, media, baja. El índice de tareas es el backlog; actual.md solo enlaza la siguiente ficha. Escribir tareas en ASCII por la convención del proyecto. Las notas de cerebro deben ser breves, vigentes y enlazar fuentes, sin duplicar resultados extensos.

## Reglas propuestas para gobernar el código futuro

Configuración explícita y sin secretos; origen/destino independientes. Transformaciones separadas del acceso. Modelos mediante adaptadores y bundles versionados; conservar preprocesamiento, identidad espacial, cortes D-2/D 01:00 y universos pertinentes. Shiny solo consume productos preparados.

Al terminar la migración no habrá dependencias ejecutables al código anterior; los enlaces de procedencia son informativos. Para adaptar Shiny, leer [guía del proyecto](../../skills/shiny_skill.md): módulos NS/moduleServer, UI/server separados, bslib y reactividad explícita.

## Organización y estilo acordados

Aplicar [convenciones de código](convenciones_codigo.md): scripts/ solo para ejecución del sistema; tests/ para pruebas/validaciones; herramientas_migracion/ para inspectores y comparación con el legado; R/ para funciones. Dos espacios de sangría, separación de bloques y descripción de propósito/entradas/salida de cada función. Revisar lo ya migrado y conservar resultados mediante pruebas rápidas.

## Git y transición

R00 no cambia AGENTS ni .gitignore principal. No confundir carpetas existentes con contenido versionado. No activar la nueva publicación ni sustituir el despliegue sin autorización específica.

