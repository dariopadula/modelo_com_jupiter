# Matriz local/S3 simulada, fallos, recuperacion, integridad y extraccion sin red.
arguments <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", grep("^--file=", arguments, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
source(file.path(root, "R/configuracion/runtime_r07.R")); rf_init_r07()
source(file.path(root, "R/acceso/cargar_acceso.R")); rf_load_access(root)

# Un fallo esperado debe producir error; los tests nunca usan credenciales reales.
expect_error <- function(expression) {
  stopifnot(inherits(try(force(expression), silent = TRUE), "try-error"))
}

# Encapsula los archivos temporales para limpiarlos incluso si una asercion falla.
run_tests <- function() {
  temporary <- tempfile("r09_test_", tmpdir = file.path(root, "runtime"))
  dir.create(temporary)
  on.exit(unlink(temporary, recursive = TRUE), add = TRUE)
  remote <- file.path(temporary, "s3_fixture")
  dir.create(remote)
  downloads <- character()
  ops <- list(
    list = function(bucket, prefix) {
      files <- list.files(remote, recursive = TRUE, full.names = FALSE)
      files[startsWith(files, prefix)]
    },
    upload = function(bucket, key, source) {
      target <- file.path(remote, key)
      dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
      stopifnot(file.copy(source, target, overwrite = TRUE))
    },
    download = function(bucket, key, destination) {
      downloads <<- c(downloads, key)
      if (!file.copy(file.path(remote, key), destination, overwrite = TRUE)) stop("Objeto S3 simulado ausente")
    }
  )
  local_config <- rf_config(root, env = character())
  stopifnot(as.numeric(rf_delivery_time("2026-01-21T01:00:00-03:00")) ==
    as.numeric(rf_delivery_time("2026-01-21 01:00:00")))
  expect_error(rf_delivery_time("2026-01-21"))
  remote_env <- c(RF_RUNTIME_PATH = paste0("runtime/", basename(temporary), "/context_runtime"),
    INGESTA_INPUT_BACKEND = "cloudera_s3", PIPELINE_STORAGE_BACKEND = "cloudera_s3",
    APP_DATA_SOURCE = "cloudera_s3", PIPELINE_S3_BUCKET = "fixture-bucket",
    INGESTA_S3_PREFIX = "entregas", INGESTA_S3_MANIFEST_KEY = "entregas/manifest.json",
    PIPELINE_S3_PREFIX = "publicaciones", APP_S3_BUCKET = "fixture-bucket", APP_S3_PREFIX = "publicaciones")
  remote_config <- rf_config(root, env = remote_env)
  expect_error(rf_config(root, env = c(PIPELINE_STORAGE_BACKEND = "cloudera_s3")))
  for (key in c("../x", "/x", "C:/x", "x//y", "x/../y", "x\\y")) expect_error(rf_object_key(key))

  # La consulta se restringe a tablas conocidas y una particion mensual completa.
  queries <- character()
  fake_query <- function(sql) {
    queries <<- c(queries, sql)
    if (startsWith(sql, "DESCRIBE")) return(data.frame(name = c(rf_raw_columns("com"), "direccion")))
    month <- sub(".* = ", "", sql)
    if (grepl("reclamos_com", sql, fixed = TRUE)) {
      return(data.frame(id = paste0("com_", month), municipio = "A", circuito = "1", estado = "resuelto",
        repetido = NA_character_, fecha_resuelto = NA_character_, incidente = "Contenedor desbordado",
        latitud = -34.9, longitud = -56.16, tipo_de_reclamo = "Limpieza", anio = 2026L,
        fecha_de_reclamo = paste0(substr(month, 1, 4), "-", substr(month, 5, 6), "-03 12:00:00"), anio_mes = as.integer(month)))
    }
    data.frame(levante_contenedor_id = "CONT_00001", levante_circuito = "1", levante_posicion_en_circuito = 1L,
      levante_activo = 1L, levante_motivo_no_levante_id = NA_integer_, levante_motivo_no_levante_descripcion = NA_character_,
      levante_fact = paste0(substr(month, 1, 4), "-", substr(month, 5, 6), "-03 01:00:00"),
      levante_porcentaje_llenado = 50, levante_periodo = 1, levante_longitud = 573000, levante_latitud = 6139000,
      anio = as.integer(substr(month, 1, 4)), levante_fecha_levante = paste0(substr(month, 1, 4), "-", substr(month, 5, 6), "-03 01:00:00"),
      anio_mes = as.integer(month))
  }
  request <- list(delivery_id = "fixture_delivery",
    com = list(partitions_replaced = "202601", complete_through = "2026-01-20", available_through_timestamp = "2026-01-21 01:00:00"),
    levante = list(partitions_replaced = "202601", complete_through = "2026-01-20", available_through_timestamp = "2026-01-21 01:00:00"))
  delivery_root <- file.path(temporary, "delivery")
  manifest <- rf_extract_impala(request, delivery_root, local_config, query = fake_query)
  stopifnot(length(queries) == 6L, !any(grepl("SELECT .*direccion", queries)))
  expect_error(rf_impala_sql("com", "202601 OR 1=1", "id"))
  expect_error(rf_impala_sql("com", "202601", "id;DROP"))
  bad <- manifest; bad$com$complete_through <- NULL
  expect_error(rf_validate_delivery(bad))
  bad <- manifest; bad$com["complete_through"] <- list(NULL)
  expect_error(rf_validate_delivery(bad))
  bad <- manifest; bad$com$replacement_scope_by_partition[[1L]] <- "partial"
  expect_error(rf_validate_delivery(bad))
  bad <- manifest; bad$levante$objects <- bad$levante$objects[-1L]
  expect_error(rf_validate_delivery(bad))
  invalid_request <- request
  invalid_request$com$partitions_replaced <- c("202501", "202502", "202503", "202504", "202505", "202506", "202507")
  before <- length(queries)
  expect_error(rf_extract_impala(invalid_request, file.path(temporary, "invalid"), local_config, query = fake_query))
  stopifnot(length(queries) == before)
  cat("R09_IMPALA_QUERY_AND_CLOSURE_OK\n")

  local_input <- rf_store(local_config, "input", delivery_root)
  remote_input <- rf_store(remote_config, "input", "", ops)
  rf_publish_delivery(delivery_root, remote_input, "manifest.json", file.path(temporary, "delivery_publish_cache"))
  expect_error(rf_publish_delivery(delivery_root, remote_input, "manifest.json", file.path(temporary, "delivery_publish_cache")))
  # El objeto ajeno no debe descargarse ni incorporarse al resultado.
  rf_store_put(remote_input, "ajeno.parquet", file.path(delivery_root, "com/202601.parquet"))
  local_delivery <- rf_materialize_delivery(local_input, "manifest.json", file.path(temporary, "input_cache"))
  remote_delivery <- rf_materialize_delivery(remote_input, "manifest.json", file.path(temporary, "input_cache"))
  local_raw <- as.data.frame(arrow::open_dataset(local_delivery$raw_com_path, partitioning = NULL))
  remote_raw <- as.data.frame(arrow::open_dataset(remote_delivery$raw_com_path, partitioning = NULL))
  stopifnot(identical(local_raw, remote_raw), !any(grepl("ajeno", downloads)))
  # Una correccion retrospectiva y un mes con cero eventos siguen siendo entregas completas.
  correction <- request
  correction$delivery_id <- "correction"
  correction$com$partitions_replaced <- c("202512", "202601")
  correction$com$zero_event_dates <- "2026-01-10"
  zero_query <- function(sql) {
    data <- fake_query(sql)
    if (startsWith(sql, "SELECT") && grepl("reclamos_com", sql, fixed = TRUE)) data <- data[0, ]
    data
  }
  correction_root <- file.path(temporary, "correction")
  zero_manifest <- rf_extract_impala(correction, correction_root, local_config, query = zero_query)
  zero_store <- rf_store(local_config, "input", correction_root)
  zero_delivery <- rf_materialize_delivery(zero_store, "manifest.json", file.path(temporary, "input_cache"))
  stopifnot(nrow(as.data.frame(arrow::open_dataset(zero_delivery$raw_com_path, partitioning = NULL))) == 0L,
    zero_manifest$com$row_count_by_partition[["202512"]] == 0L,
    zero_manifest$com$zero_event_dates == "2026-01-10")
  cat("R09_DELIVERY_LOCAL_S3_EQUIVALENCE_OK\n")

  source <- file.path(root, "runtime/r08_app/publicacion_piloto")
  original_manifest_hash <- unname(tools::md5sum(file.path(source, "publicacion.rds")))
  local_store <- rf_store(local_config, "pipeline", file.path(temporary, "publications"))
  remote_store <- rf_store(remote_config, "pipeline", "", ops)
  # Las cuatro combinaciones usan el mismo resultado de entrega, sin modelos ni red.
  for (input in c("local", "s3")) for (output in c("local", "s3")) {
    store <- if (output == "local") local_store else remote_store
    id <- paste(input, output, sep = "_")
    delivery <- if (input == "local") local_delivery else remote_delivery
    raw <- as.data.frame(arrow::open_dataset(delivery$raw_com_path, partitioning = NULL))
    artifact <- file.path(temporary, paste0(id, ".parquet"))
    arrow::write_parquet(raw, artifact)
    rf_store_put(store, paste0("matrix/", id, ".parquet"), artifact)
    downloaded <- rf_store_get(store, paste0("matrix/", id, ".parquet"), file.path(temporary, paste0("matrix_check_", id, ".parquet")))
    stopifnot(unname(tools::md5sum(artifact)) == unname(tools::md5sum(downloaded)),
      isTRUE(all.equal(raw, as.data.frame(arrow::read_parquet(downloaded)), check.attributes = FALSE, tolerance = 0)))
    rf_publish_version(source, store, id)
    rf_activate_version(store, id, file.path(temporary, "publisher_cache"))
    view <- rf_open_publication(store, file.path(temporary, "reader_cache"))
    stopifnot(view$id == id)
  }
  cat("R09_BACKEND_MATRIX_4_OK\n")
  stopifnot(original_manifest_hash == unname(tools::md5sum(file.path(source, "publicacion.rds"))))

  for (store in list(local_store, remote_store)) {
    initial <- rf_store_json(store, "current.json")$publication_id
    view <- rf_open_publication(store, file.path(temporary, "reader_cache"))
    expect_error(rf_publish_version(source, store, "incomplete", fail_after = 1L))
    expect_error(rf_activate_version(store, "incomplete", file.path(temporary, "publisher_cache")))
    stopifnot(rf_store_json(store, "current.json")$publication_id == initial)
    rf_publish_version(source, store, "next_version")
    expect_error(rf_activate_version(store, "next_version", file.path(temporary, "publisher_cache"), fail_before_pointer = TRUE))
    stopifnot(rf_store_json(store, "current.json")$publication_id == initial)
    rf_activate_version(store, "next_version", file.path(temporary, "publisher_cache"))
    stopifnot(view$id == initial, rf_store_json(store, "current.json")$publication_id == "next_version")
    rf_restore_publication(store, file.path(temporary, "publisher_cache"))
    stopifnot(rf_store_json(store, "current.json")$publication_id == initial)
    expect_error(rf_publish_version(source, store, initial))
    if (store$backend == "local") {
      expect_error(rf_activate_version(store, "next_version", file.path(temporary, "publisher_cache"), fail_after_remove = TRUE))
      expect_error(rf_open_publication(store, file.path(temporary, "reader_cache")))
      rf_restore_publication(store, file.path(temporary, "publisher_cache"))
      stopifnot(rf_store_json(store, "current.json")$publication_id == initial)
    }
  }
  cat("R09_FAILURE_RECOVERY_PINNING_OK\n")

  # La app real usa el cargador publico de Shiny tambien desde un almacen local versionado.
  old_store <- Sys.getenv("RF_APP_STORE", unset = NA_character_)
  old_source <- Sys.getenv("APP_DATA_SOURCE", unset = NA_character_)
  old_directory <- getwd()
  on.exit({
    setwd(old_directory)
    if (is.na(old_store)) Sys.unsetenv("RF_APP_STORE") else Sys.setenv(RF_APP_STORE = old_store)
    if (is.na(old_source)) Sys.unsetenv("APP_DATA_SOURCE") else Sys.setenv(APP_DATA_SOURCE = old_source)
  }, add = TRUE)
  Sys.setenv(RF_APP_STORE = local_store$root, APP_DATA_SOURCE = "local")
  setwd(file.path(root, "app"))
  library(shiny)
  options(shiny.autoload.r = FALSE)
  app <- shiny::shinyAppDir(normalizePath("."))
  stopifnot(is.function(app$serverFuncSource()))
  response <- app$httpHandler(list(REQUEST_METHOD = "GET", PATH_INFO = "/", QUERY_STRING = "",
    SCRIPT_NAME = "", HTTP_ACCEPT = "text/html"))
  stopifnot(response$status == 200L, grepl("24/05/2026", response$body, fixed = TRUE))
  setwd(old_directory)
  cat("R09_VERSIONED_APP_HTTP_OK\n")

  downloads <- character()
  context <- rf_app_context(remote_config, ops = ops)
  stopifnot(!any(grepl("detalle_cluster_dia", downloads)))
  rf_app_fetch_day(context, "2026-03-31", "com_reclamo")
  history_downloads <- downloads[grepl("detalle_cluster_dia", downloads)]
  stopifnot(length(history_downloads) > 0L, all(grepl("dia_objetivo=2026-03-31/modelo_id=com_reclamo/", history_downloads, fixed = TRUE)))
  number_downloads <- length(downloads)
  rf_app_fetch_day(context, "2026-03-31", "com_reclamo")
  stopifnot(length(downloads) == number_downloads)
  # Alterar un objeto ya publicado debe impedir usarlo, aunque exista en cache.
  path <- "publicacion.rds"
  key <- paste0("versions/", context$view$id, "/", path)
  corrupt <- file.path(temporary, "corrupt")
  writeLines("corrupt", corrupt)
  rf_store_put(remote_store, key, corrupt)
  file.remove(file.path(context$root, path))
  expect_error(rf_fetch_files(context$view, path))
  cat("R09_APP_PARTITION_CACHE_INTEGRITY_OK\n")
}

run_tests()
cat("R09_LOCAL_AND_SIMULATED_OK: remote_real=pending\n")
