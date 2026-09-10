library(data.table)

source("funciones/scoring_operativo_utils.R")

fallar <- function(mensaje) {
  stop("Validacion operativa fallida: ", mensaje)
}

plan_un_dia <- resolver_plan_scoring("2026-01-01", "2026-01-02")
if (plan_un_dia$dias_pendientes != 1L || !plan_un_dia$requiere_scoring) {
  fallar("deteccion de un dia pendiente")
}

plan_diez_dias <- resolver_plan_scoring("2025-12-31", "2026-01-10")
if (plan_diez_dias$dias_pendientes != 10L) {
  fallar("deteccion de diez dias pendientes")
}

plan_existente <- resolver_plan_scoring("2026-01-10", "2026-01-10")
if (plan_existente$dias_pendientes != 0L || plan_existente$requiere_scoring) {
  fallar("dia ya procesado")
}

frescura_ok <- evaluar_frescura_scoring(
  fecha_objetivo_hasta = "2026-01-10",
  timestamp_max_levante = as.POSIXct(
    "2026-01-10 08:30:00",
    tz = "America/Montevideo"
  ),
  fecha_com_cerrada_hasta = "2026-01-08"
)
if (!frescura_ok$puede_procesar) {
  fallar("fuentes frescas")
}

frescura_levante_atrasado <- evaluar_frescura_scoring(
  fecha_objetivo_hasta = "2026-01-10",
  timestamp_max_levante = as.POSIXct(
    "2026-01-09 23:59:59",
    tz = "America/Montevideo"
  ),
  fecha_com_cerrada_hasta = "2026-01-08"
)
if (
  frescura_levante_atrasado$puede_procesar ||
    frescura_levante_atrasado$estado_levante != "atrasado"
) {
  fallar("bloqueo por levantes atrasados")
}

frescura_com_atrasado <- evaluar_frescura_scoring(
  fecha_objetivo_hasta = "2026-01-10",
  timestamp_max_levante = as.POSIXct(
    "2026-01-10 08:30:00",
    tz = "America/Montevideo"
  ),
  fecha_com_cerrada_hasta = "2026-01-07"
)
if (
  frescura_com_atrasado$puede_procesar ||
    frescura_com_atrasado$estado_com != "atrasado"
) {
  fallar("bloqueo por COM atrasado")
}

path_lock_test <- file.path(tempdir(), "scoring_operativo_test.lock")
if (dir.exists(path_lock_test)) {
  unlink(path_lock_test, recursive = TRUE)
}
adquirir_lock_operativo(path_lock_test, "test_activo", max_minutos = 180)
segundo_lock_bloqueado <- inherits(
  try(
    adquirir_lock_operativo(path_lock_test, "test_segundo", max_minutos = 180),
    silent = TRUE
  ),
  "try-error"
)
liberar_lock_operativo(path_lock_test)
if (!segundo_lock_bloqueado || dir.exists(path_lock_test)) {
  fallar("lock de corrida y liberacion")
}

dir.create(path_lock_test, recursive = TRUE)
Sys.setFileTime(path_lock_test, Sys.time() - 4 * 60 * 60)
adquirir_lock_operativo(path_lock_test, "test_recuperado", max_minutos = 180)
lock_vencido_recuperado <- dir.exists(path_lock_test)
liberar_lock_operativo(path_lock_test)
if (!lock_vencido_recuperado) {
  fallar("recuperacion de lock vencido")
}

raiz_publicacion <- file.path(tempdir(), "scoring_operativo_publicacion")
path_nuevo <- file.path(raiz_publicacion, "nuevo")
path_destino <- file.path(raiz_publicacion, "destino")
path_backup <- file.path(raiz_publicacion, "backup")
unlink(raiz_publicacion, recursive = TRUE)
dir.create(path_nuevo, recursive = TRUE)
dir.create(path_destino, recursive = TRUE)
saveRDS("nuevo", file.path(path_nuevo, "valor.rds"))
saveRDS("anterior", file.path(path_destino, "valor.rds"))
publicar_directorio_transaccional(path_nuevo, path_destino, path_backup)
if (
  readRDS(file.path(path_destino, "valor.rds")) != "nuevo" ||
    readRDS(file.path(path_backup, "valor.rds")) != "anterior"
) {
  fallar("publicacion transaccional con respaldo")
}
unlink(raiz_publicacion, recursive = TRUE)

resultado <- data.table(
  prueba = c(
    "un_dia_pendiente",
    "diez_dias_pendientes",
    "dia_ya_procesado",
    "fuentes_frescas",
    "levantes_atrasados",
    "com_atrasado",
    "lock_concurrente",
    "lock_vencido",
    "publicacion_transaccional"
  ),
  resultado = "ok"
)

print(resultado)
