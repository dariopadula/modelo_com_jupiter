all_args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", grep("^--file=", all_args, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
source(file.path(root, "R/acceso/configuracion.R"))
source(file.path(root, "R/registro/contratos.R"))
n <- 0L

# Registra una comprobacion satisfactoria de la suite.  Entrada: expresion logica.
# Salida: contador actualizado o fallo.
ok <- function(expr) {
  stopifnot(isTRUE(expr))
  n <<- n + 1L
}

# Comprueba que una expresion falle con el mensaje esperado.  Entradas: expresion y
# patron de error. Salida: comprobacion registrada.
bad <- function(expr, pattern) {
  msg <- tryCatch({
    force(expr)
    NA_character_
  }, error = function(e) conditionMessage(e))
  ok(!is.na(msg) && grepl(pattern, msg))
}
empty <- setNames(character(), character())
cfg <- rf_config(root, file.path(root, "config/local.dcf.example"), env = empty)
ok(cfg$values[["INGESTA_INPUT_BACKEND"]] == "local")
ok(startsWith(cfg$values[["RF_RUNTIME_PATH"]], root))
bad(rf_config(root, env = c(INGESTA_INPUT_BACKEND = "invalid")), "Valor invalido")
bad(rf_config(root, env = c(RF_RUNTIME_PATH = "../data")), "salir")
bad(rf_config(root, env = c(RF_RUNTIME_PATH = "/data")), "relativa")
bad(rf_config(root, file.path(root, "config/cloudera.dcf.example"), env = empty), "definitivo")
s3 <- c(INGESTA_INPUT_BACKEND = "s3", PIPELINE_STORAGE_BACKEND = "local", PIPELINE_S3_BUCKET = "fixture",
  INGESTA_S3_PREFIX = "entregas", INGESTA_S3_MANIFEST_KEY = "entregas/m.json")
cfg <- rf_config(root, env = s3)
ok(cfg$values[["PIPELINE_STORAGE_BACKEND"]] == "local" && cfg$values[["APP_DATA_SOURCE"]] ==
  "local")
bad(rf_config(root, env = c(s3[names(s3) != "INGESTA_S3_MANIFEST_KEY"], INGESTA_S3_MANIFEST_KEY = "otro/m.json")),
  "dentro")
bad(rf_config(root, env = c(RF_EXTRACTOR = "impala")), "definitivo")
bad(rf_config(root, env = c(RF_TIMEZONE = "UTC")), "Zona horaria")
m <- list(contract_version = "rf_model_v1", model_id = "com", model_version = "fixed", adapter = "logistico",
  target = "reclamo_com", unit = "cluster_dia", cluster_version = "v1", features = c("f1",
    "f2"), preprocessing_id = "prep1", training_reference = "historia_fija", availability = list(timezone = "America/Montevideo",
    com_lag_days = 2L, levante_cutoff = "01:00:00"))
ok(rf_model_contract(m))
wrong <- m
wrong$features <- c("f1", "f1")
bad(rf_model_contract(wrong), "duplicadas")
wrong <- m
wrong$availability$com_lag_days <- 1L
bad(rf_model_contract(wrong), "Disponibilidad")
ok(rf_feature_contract(data.frame(version_cluster = "v1", f1 = 1, f2 = 2), m))
bad(rf_feature_contract(data.frame(version_cluster = "v2", f1 = 1, f2 = 2), m), "espacial")
bad(rf_feature_contract(data.frame(version_cluster = "v1", f1 = 1), m), "faltan")
d <- data.frame(cluster_id = "c1", dia_objetivo = as.Date("2026-01-01"), modelo_id = "com",
  version_modelo = "fixed", version_cluster = "v1", pred_prob = 0.4, ranking_dia = 1L,
  target_app = "reclamo_com")
ok(rf_prediction_contract(d))
bad(rf_prediction_contract(rbind(d, d)), "duplicada")
wrong <- d
wrong$pred_prob <- 1.1
bad(rf_prediction_contract(wrong), "rango")
wrong <- d
wrong$dia_objetivo <- "2026-01-01"
bad(rf_prediction_contract(wrong), "Date")
pub <- list(contract_version = "rf_publication_v1", publication_id = "p1", cluster_version = "v1",
  models = list(m), layers = list(operacional = "o", historico = "h", referencia = "r"))
ok(rf_publication_contract(pub))
wrong <- pub
wrong$cluster_version <- "v2"
bad(rf_publication_contract(wrong), "mezcla")
wrong <- pub
wrong$layers$historico <- NULL
bad(rf_publication_contract(wrong), "faltan")
s <- data.frame(dia_objetivo = as.Date(rep("2026-01-01", 3)), nivel_territorial = c("montevideo",
  "barrio", "barrio"), territorio_id = c("m", "b1", "b2"), escenario = "P3_compacto", clusters_estimados = c(3,
  1, 2), clusters_observados = c(2, 1, 1), clusters_evaluados = c(6, 3, 3), estado_observacion = "cerrado")
ok(rf_series_contract(s))
wrong <- s
wrong$clusters_estimados[1] <- 4
bad(rf_series_contract(wrong), "inconsistentes")
wrong <- s
wrong$clusters_observados[2] <- 4
bad(rf_series_contract(wrong), "exposicion")
cat("R02_TESTS_OK:", n, "comprobaciones\n")
