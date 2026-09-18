library(arrow)
library(data.table)
library(dplyr)
library(mgcv)

source("funciones/splits_temporales.R")

boot_desde <- as.integer(Sys.getenv("BOOT_CUAD_DESDE", "1"))
boot_hasta <- as.integer(Sys.getenv("BOOT_CUAD_HASTA", "50"))
ejecutar_boot <- Sys.getenv("BOOT_CUAD_EJECUTAR", "1") == "1"
solo_resumir <- Sys.getenv("BOOT_CUAD_SOLO_RESUMIR", "0") == "1"

if (is.na(boot_desde) || is.na(boot_hasta) || boot_desde < 1L ||
    boot_hasta > 50L || boot_desde > boot_hasta) {
  stop("Rango de replicas invalido")
}

path_base <- "data/processed/features_compartidas/segmento_dia"
path_exploracion <- paste0(
  "outputs/reevaluacion_2026/",
  "exploracion_inferencia_curvatura_interaccion_q30_delta"
)
path_out <- file.path(path_exploracion, "bootstrap_cuadratico_completo")
path_replicas <- file.path(path_out, "replicas")
dir.create(path_replicas, recursive = TRUE, showWarnings = FALSE)

base <- as.data.table(as.data.frame(
  arrow::open_dataset(path_base, format = "parquet") |>
    dplyr::filter(dia <= as.Date("2026-03-31")) |>
    dplyr::collect()
))
base[, dia := as.IDate(dia)]
base <- asignar_split_congelado(base)
train <- base[split == "entrenamiento"]
train[, `:=`(
  prop_reclamo = observado / n_clusters,
  dia_semana = factor(dia_semana),
  es_feriado = factor(as.integer(es_feriado)),
  barrio = factor(barrio),
  segmento = factor(segmento)
)]

preparacion <- fread(file.path(path_exploracion, "preparacion_variables.csv"))
for (variable in preparacion$variable) {
  p <- preparacion[match(variable, preparacion[["variable"]])]
  x <- train[[variable]]
  x[!is.finite(x)] <- p$mediana_train
  train[, paste0("z_", variable) := (x - p$media_train) / p$sd_train]
}
train[, z_delta_q_7_30_sq := z_delta_q_7_30^2]
train <- droplevels(train)

formula_cuadratica <- prop_reclamo ~
  dia_semana + es_feriado + sin_anual + cos_anual +
  z_log_densidad_pob + z_porc_nbi_segmento +
  z_media_h + z_media_q_30 + z_delta_q_7_30 + z_delta_q_7_30_sq +
  z_media_h:z_delta_q_7_30 + z_media_h:dia_semana +
  s(barrio, bs = "re") + s(segmento, bs = "re")

ajustar <- function(datos) {
  bam(
    formula_cuadratica,
    data = datos,
    family = binomial(),
    weights = n_clusters,
    method = "fREML",
    discrete = TRUE,
    nthreads = 1L,
    gc.level = 1L
  )
}

train[, `:=`(
  semana_inicio = dia - (as.integer(format(dia, "%u")) - 1L),
  segmento_original = as.character(segmento)
)]
semanas <- sort(unique(train$semana_inicio))
segmentos <- sort(unique(train$segmento_original))

if (ejecutar_boot && !solo_resumir) {
  for (b in seq.int(boot_desde, boot_hasta)) {
    path_replica <- file.path(path_replicas, sprintf("replica_%03d.csv", b))
    if (file.exists(path_replica)) next
    set.seed(2026091700L + b)

    muestra_semanas <- data.table(
      semana_inicio = sample(semanas, length(semanas), replace = TRUE),
      copia_semana = seq_along(semanas)
    )
    boot_temporal <- train[
      muestra_semanas,
      on = "semana_inicio",
      nomatch = 0L,
      allow.cartesian = TRUE
    ]

    muestra_segmentos <- data.table(
      segmento_original = sample(segmentos, length(segmentos), replace = TRUE),
      copia_segmento = seq_along(segmentos)
    )
    boot <- boot_temporal[
      muestra_segmentos,
      on = "segmento_original",
      nomatch = 0L,
      allow.cartesian = TRUE
    ]
    boot[, `:=`(
      segmento = factor(sprintf("segmento_boot_%04d", copia_segmento)),
      barrio = factor(as.character(barrio)),
      dia_semana = factor(
        as.character(dia_semana), levels = levels(train$dia_semana)
      ),
      es_feriado = factor(
        as.character(es_feriado), levels = levels(train$es_feriado)
      )
    )]

    cat("Bootstrap cuadratico", b, "de 50\n")
    resultado <- tryCatch({
      fit <- ajustar(boot)
      tabla <- as.data.table(summary(fit)$p.table, keep.rownames = "termino")
      setnames(
        tabla, 2:5,
        c("estimacion", "error_std_modelo", "estadistico", "p_valor_modelo")
      )
      tabla[, .(
        replica = b,
        termino,
        estimacion,
        error_std_modelo,
        convergio = isTRUE(fit$converged),
        n_filas = nrow(boot),
        n_semanas = uniqueN(boot$copia_semana),
        n_segmentos = uniqueN(boot$copia_segmento),
        error = NA_character_
      )]
    }, error = function(e) {
      data.table(
        replica = b,
        termino = NA_character_,
        estimacion = NA_real_,
        error_std_modelo = NA_real_,
        convergio = FALSE,
        n_filas = nrow(boot),
        n_semanas = uniqueN(boot$copia_semana),
        n_segmentos = uniqueN(boot$copia_segmento),
        error = conditionMessage(e)
      )
    })
    fwrite(resultado, path_replica)
    rm(boot, boot_temporal, resultado)
    gc()
  }
}

archivos <- list.files(
  path_replicas,
  pattern = "^replica_[0-9]+[.]csv$",
  full.names = TRUE
)
if (length(archivos)) {
  boot_resultados <- rbindlist(lapply(archivos, fread), fill = TRUE)
  fwrite(boot_resultados, file.path(path_out, "bootstrap_coeficientes.csv"))

  boot_resumen <- boot_resultados[
    convergio == TRUE & !is.na(termino),
    .(
      n_replicas = .N,
      media_bootstrap = mean(estimacion),
      error_std_bootstrap = sd(estimacion),
      q025 = quantile(estimacion, 0.025),
      mediana = median(estimacion),
      q975 = quantile(estimacion, 0.975),
      proporcion_positiva = mean(estimacion > 0),
      proporcion_negativa = mean(estimacion < 0)
    ),
    by = termino
  ]

  coef_originales <- fread(file.path(path_exploracion, "coeficientes.csv"))[
    candidato == "inferencial_delta_cuadratico",
    .(
      termino,
      estimacion_original = Estimate,
      error_std_convencional = `Std. Error`
    )
  ]
  boot_resumen <- merge(
    coef_originales,
    boot_resumen,
    by = "termino",
    all.y = TRUE
  )
  boot_resumen[, razon_error_std :=
    error_std_bootstrap / error_std_convencional]
  fwrite(boot_resumen, file.path(path_out, "bootstrap_resumen.csv"))

  coef_forma <- dcast(
    boot_resultados[
      convergio == TRUE & termino %in% c(
        "z_delta_q_7_30", "z_delta_q_7_30_sq",
        "z_media_h:z_delta_q_7_30"
      )
    ],
    replica ~ termino,
    value.var = "estimacion"
  )
  p_delta <- preparacion[variable == "delta_q_7_30"]
  z_delta_cero <- (0 - p_delta$media_train) / p_delta$sd_train
  coef_forma[, `:=`(
    z_minimo_h_medio = -z_delta_q_7_30 / (2 * z_delta_q_7_30_sq),
    delta_minimo_h_medio = p_delta$media_train +
      p_delta$sd_train * (-z_delta_q_7_30 / (2 * z_delta_q_7_30_sq)),
    pendiente_en_delta_cero_h_medio = z_delta_q_7_30 +
      2 * z_delta_q_7_30_sq * z_delta_cero
  )]
  fwrite(coef_forma, file.path(path_out, "bootstrap_forma_replicas.csv"))

  columnas_forma <- c(
    "z_minimo_h_medio", "delta_minimo_h_medio",
    "pendiente_en_delta_cero_h_medio"
  )
  forma_resumen <- rbindlist(lapply(columnas_forma, function(variable) {
    valores <- coef_forma[[variable]]
    data.table(
      variable = variable,
      media = mean(valores),
      error_std = sd(valores),
      q025 = quantile(valores, 0.025),
      mediana = median(valores),
      q975 = quantile(valores, 0.975),
      proporcion_positiva = mean(valores > 0),
      proporcion_negativa = mean(valores < 0)
    )
  }))
  fwrite(forma_resumen, file.path(path_out, "bootstrap_forma_resumen.csv"))
}

metadata <- data.table(
  modelo = "inferencial_delta_cuadratico",
  version_split = "reevaluacion_2026_v1",
  replicas_objetivo = 50L,
  replicas_disponibles = length(archivos),
  n_filas_train = nrow(train),
  n_dias_train = uniqueN(train$dia),
  n_semanas_train = length(semanas),
  n_segmentos_train = length(segmentos),
  remuestreo = "semanas_y_segmentos_completos",
  usa_test = FALSE
)
fwrite(metadata, file.path(path_out, "metadata.csv"))

if (file.exists(file.path(path_out, "bootstrap_resumen.csv"))) {
  print(fread(file.path(path_out, "bootstrap_resumen.csv"))[
    termino %in% c(
      "z_log_densidad_pob", "z_porc_nbi_segmento", "z_media_h",
      "z_media_q_30", "z_delta_q_7_30", "z_delta_q_7_30_sq",
      "z_media_h:z_delta_q_7_30"
    )
  ])
}
