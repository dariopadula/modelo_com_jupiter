library(arrow)
library(data.table)

source("funciones/modelos_utils.R")

################################
### Parametros
path_features <- "data/processed/modelo_cluster_dia/features_cluster_dia"
path_modelo_logistico <- "data/processed/modelos/logistico_cluster_dia_reducido/modelo_logistico_reducido.rds"
out_base <- "data/processed/modelos/diagnostico_variables"

target_col <- "tuvo_reclamo"
umbral_correlacion_alta <- 0.70

################################
### Cargo parametros del modelo actual
modelo_logistico <- readRDS(path_modelo_logistico)

features_modelo <- modelo_logistico$features_modelo
meses_train <- modelo_logistico$meses_train
meses_validacion <- modelo_logistico$meses_validacion
fecha_min_modelo <- modelo_logistico$fecha_min_modelo
target_version_cluster <- modelo_logistico$version_cluster
no_agregar_na_features <- modelo_logistico$no_agregar_na_features

if (is.null(fecha_min_modelo)) fecha_min_modelo <- data.table::as.IDate("1900-01-01")
if (is.null(no_agregar_na_features)) no_agregar_na_features <- character()

################################
### Cargo datos
datos <- as.data.table(arrow::open_dataset(path_features, format = "parquet"))
datos <- datos[version_cluster == target_version_cluster]
datos <- datos[dia >= fecha_min_modelo]
datos <- agregar_features_logistico_reducido(datos)

faltantes <- setdiff(c(target_col, features_modelo, "cluster_id", "dia", "anio_mes"), names(datos))
if (length(faltantes) > 0L) {
  stop("Faltan columnas para diagnostico: ", paste(faltantes, collapse = ", "))
}

train <- datos[anio_mes %in% meses_train]
valid <- datos[anio_mes %in% meses_validacion]

if (nrow(train) == 0L) stop("Train quedo vacio")

################################
### Resumen de variables crudas
resumen_variables <- data.table::rbindlist(lapply(features_modelo, function(col) {
  vals <- train[[col]]
  vals_num <- vals
  if (is.logical(vals_num)) vals_num <- as.integer(vals_num)
  vals_num <- suppressWarnings(as.numeric(vals_num))

  data.table::data.table(
    variable = col,
    clase = paste(class(vals), collapse = ","),
    n = length(vals),
    n_na = sum(is.na(vals)),
    pct_na = mean(is.na(vals)),
    media = mean(vals_num, na.rm = TRUE),
    desvio = stats::sd(vals_num, na.rm = TRUE),
    p05 = as.numeric(stats::quantile(vals_num, 0.05, na.rm = TRUE, names = FALSE)),
    mediana = stats::median(vals_num, na.rm = TRUE),
    p95 = as.numeric(stats::quantile(vals_num, 0.95, na.rm = TRUE, names = FALSE)),
    min = suppressWarnings(min(vals_num, na.rm = TRUE)),
    max = suppressWarnings(max(vals_num, na.rm = TRUE))
  )
}))

for (col in c("media", "desvio", "p05", "mediana", "p95", "min", "max")) {
  resumen_variables[is.infinite(get(col)), (col) := NA_real_]
}

################################
### Matriz preparada como en el modelo
mat_train <- preparar_matriz(
  train,
  features_modelo,
  no_agregar_na_features = no_agregar_na_features
)

x_train <- as.data.table(mat_train$x)
variables_matriz <- names(x_train)

################################
### Correlaciones
cor_mat <- stats::cor(as.matrix(x_train), use = "pairwise.complete.obs")

pares <- data.table::as.data.table(as.table(cor_mat))
data.table::setnames(pares, c("variable_1", "variable_2", "correlacion"))
pares <- pares[as.character(variable_1) < as.character(variable_2)]
pares[, abs_correlacion := abs(correlacion)]
data.table::setorder(pares, -abs_correlacion)

correlaciones_altas <- pares[abs_correlacion >= umbral_correlacion_alta]

################################
### VIF
calcular_vif <- function(x) {
  x_mat <- as.matrix(x)
  out <- lapply(seq_len(ncol(x_mat)), function(j) {
    y <- x_mat[, j]
    otros <- x_mat[, -j, drop = FALSE]
    fit <- stats::lm.fit(
      x = cbind(intercept = 1, otros),
      y = y
    )
    ss_res <- sum(fit$residuals^2)
    ss_tot <- sum((y - mean(y))^2)
    r2 <- data.table::fifelse(ss_tot > 0, 1 - ss_res / ss_tot, NA_real_)
    vif <- data.table::fifelse(!is.na(r2) && r2 < 1, 1 / (1 - r2), Inf)

    data.table::data.table(
      variable = colnames(x_mat)[j],
      r2_contra_otros_predictores = r2,
      tolerancia = 1 / vif,
      vif = vif
    )
  })

  data.table::rbindlist(out)
}

vif_variables <- calcular_vif(x_train)
data.table::setorder(vif_variables, -vif)

################################
### Relacion marginal con target
target_por_variable <- data.table::rbindlist(lapply(variables_matriz, function(col) {
  tmp <- data.table::data.table(
    valor = x_train[[col]],
    target = as.integer(train[[target_col]])
  )
  tmp[, grupo := data.table::frank(valor, ties.method = "average")]
  tmp[, grupo := pmin(5L, pmax(1L, ceiling(grupo / .N * 5L)))]
  tmp[
    ,
    .(
      n = .N,
      valor_medio_estandarizado = mean(valor),
      positivos = sum(target),
      tasa_reclamo = mean(target)
    ),
    by = grupo
  ][
    ,
    variable := col
  ][
    ,
    .(variable, grupo, n, valor_medio_estandarizado, positivos, tasa_reclamo)
  ]
}))

################################
### Grafico de correlaciones
dir.create(file.path(out_base, "figuras"), recursive = TRUE, showWarnings = FALSE)

if (requireNamespace("ggplot2", quietly = TRUE)) {
  cor_plot_dt <- data.table::copy(pares)
  cor_plot_dt <- cor_plot_dt[abs_correlacion >= 0.40]

  p <- ggplot2::ggplot(
    cor_plot_dt,
    ggplot2::aes(x = variable_1, y = variable_2, fill = correlacion)
  ) +
    ggplot2::geom_tile(color = "white", linewidth = 0.15) +
    ggplot2::scale_fill_gradient2(
      low = "#b13f3f",
      mid = "white",
      high = "#2f6fbd",
      midpoint = 0,
      limits = c(-1, 1)
    ) +
    ggplot2::labs(
      title = "Correlaciones entre predictores",
      x = NULL,
      y = NULL,
      fill = "cor"
    ) +
    ggplot2::theme_minimal(base_size = 9) +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 90, hjust = 1, vjust = 0.5),
      panel.grid = ggplot2::element_blank()
    )

  ggplot2::ggsave(
    file.path(out_base, "figuras", "correlaciones_predictores.png"),
    plot = p,
    width = 10,
    height = 8,
    dpi = 150
  )
}

################################
### Guardo resultados
dir.create(out_base, recursive = TRUE, showWarnings = FALSE)
unlink(
  file.path(out_base, c(
    "resumen_variables",
    "correlaciones",
    "correlaciones_altas",
    "vif_variables",
    "target_por_variable"
  )),
  recursive = TRUE
)

agregar_metadata <- function(dt) {
  dt[, `:=`(
    version_cluster = target_version_cluster,
    fecha_min_modelo = fecha_min_modelo,
    meses_train = paste(meses_train, collapse = ","),
    meses_validacion = paste(meses_validacion, collapse = ",")
  )]
  dt
}

arrow::write_dataset(
  agregar_metadata(data.table::copy(resumen_variables)),
  path = file.path(out_base, "resumen_variables"),
  format = "parquet",
  existing_data_behavior = "overwrite",
  compression = "zstd"
)

arrow::write_dataset(
  agregar_metadata(data.table::copy(pares)),
  path = file.path(out_base, "correlaciones"),
  format = "parquet",
  existing_data_behavior = "overwrite",
  compression = "zstd"
)

arrow::write_dataset(
  agregar_metadata(data.table::copy(correlaciones_altas)),
  path = file.path(out_base, "correlaciones_altas"),
  format = "parquet",
  existing_data_behavior = "overwrite",
  compression = "zstd"
)

arrow::write_dataset(
  agregar_metadata(data.table::copy(vif_variables)),
  path = file.path(out_base, "vif_variables"),
  format = "parquet",
  existing_data_behavior = "overwrite",
  compression = "zstd"
)

arrow::write_dataset(
  agregar_metadata(data.table::copy(target_por_variable)),
  path = file.path(out_base, "target_por_variable"),
  format = "parquet",
  existing_data_behavior = "overwrite",
  compression = "zstd"
)

################################
### Salida de control
print(data.table::data.table(
  version_cluster = target_version_cluster,
  fecha_min_modelo = fecha_min_modelo,
  filas_train = nrow(train),
  predictores_originales = length(features_modelo),
  predictores_matriz = length(variables_matriz),
  correlaciones_altas = nrow(correlaciones_altas)
))

print(head(correlaciones_altas, 20))
print(head(vif_variables, 20))
