library(data.table)
library(mgcv)

path_base <- file.path(
  "outputs", "benchmark_modelo_segmento_barrio_com", "base_segmento_dia.csv"
)
path_top_scores <- file.path(
  "outputs", "experimento_top20pct_interaccion_exceso_com",
  "top20pct_barrio_dia.csv"
)
path_extremos <- file.path(
  "outputs", "experimento_extremos_exceso_segmento_com",
  "extremos_segmento_dia.csv"
)
path_propension <- file.path(
  "outputs", "experimento_propension_barrio_exceso_com",
  "propensiones_barrio_dia.csv"
)
path_out <- "outputs/predicciones_train_candidatos_segmento_com"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

base_original <- fread(path_base)
base_original[, `:=`(
  dia_objetivo = as.IDate(dia_objetivo),
  segmento = as.character(segmento)
)]
top_scores <- fread(path_top_scores)
top_scores[, dia_objetivo := as.IDate(dia_objetivo)]

aplicar_preparacion <- function(dt, path_prep, variables) {
  prep <- fread(path_prep)
  for (v in variables) {
    p <- prep[variable == v]
    if (nrow(p) != 1L) stop("Preparacion faltante para ", v)
    x <- dt[[v]]
    x[!is.finite(x)] <- p$mediana_train
    dt[, (paste0("z_", v)) := (x - p$media_train) / p$desvio_train]
  }
  dt[]
}

predecir_y_agregar <- function(modelo, dt, escenario) {
  dt[, `:=`(
    barrio = factor(barrio),
    segmento = factor(segmento),
    dia_semana = factor(dia_semana)
  )]
  newdata <- as.data.frame(
    dt[, setdiff(names(dt), "dia_objetivo"), with = FALSE]
  )
  prob <- as.numeric(predict.gam(modelo, newdata = newdata, type = "response"))
  dt[, prob_predicha := prob]
  dt[, .(
    observado = sum(clusters_con_reclamo),
    predicho = sum(n_clusters * prob_predicha)
  ), by = dia_objetivo][, escenario := escenario]
}

# B1: exceso medio del segmento + media top-20 % de scores del barrio.
base_b1 <- copy(base_original)
base_b1[top_scores, on = c("barrio", "dia_objetivo"),
  media_top20pct_barrio := i.media_top20pct_barrio]
base_b1 <- base_b1[
  split_modelo == "entrenamiento" & is.finite(media_top20pct_barrio)
]
base_b1 <- aplicar_preparacion(
  base_b1,
  file.path(
    "outputs", "experimento_top20pct_interaccion_exceso_com",
    "preparacion_variables.csv"
  ),
  c("carga_exceso_media", "media_top20pct_barrio")
)
modelo_b1 <- readRDS(file.path(
  "outputs", "experimento_top20pct_interaccion_exceso_com",
  "modelo_B1_media_top20pct.rds"
))
pred_b1 <- predecir_y_agregar(modelo_b1, base_b1, "B1_media_top20pct")

# E1: extremo local del segmento + media top-20 % de scores del barrio.
base_e1 <- copy(base_original)
extremos <- fread(path_extremos)
extremos[, `:=`(
  dia_objetivo = as.IDate(dia_objetivo),
  segmento = as.character(segmento)
)]
propension <- fread(path_propension)
propension[, dia_objetivo := as.IDate(dia_objetivo)]

base_e1[extremos, on = c("segmento", "dia_objetivo"),
  media_top20pct_exceso_segmento := i.media_top20pct_exceso_segmento]
base_e1[top_scores, on = c("barrio", "dia_objetivo"),
  media_top20pct_barrio := i.media_top20pct_barrio]
base_e1[propension, on = c("barrio", "dia_objetivo"),
  propension_30d := i.propension_30d]
base_e1 <- base_e1[
  split_modelo == "entrenamiento" &
    is.finite(media_top20pct_exceso_segmento) &
    is.finite(media_top20pct_barrio) &
    is.finite(propension_30d)
]
base_e1 <- aplicar_preparacion(
  base_e1,
  file.path(
    "outputs", "experimento_extremos_exceso_segmento_com",
    "preparacion_variables.csv"
  ),
  c("media_top20pct_exceso_segmento", "media_top20pct_barrio")
)
modelo_e1 <- readRDS(file.path(
  "outputs", "experimento_extremos_exceso_segmento_com",
  "modelo_E1_extremo_segmento.rds"
))
pred_e1 <- predecir_y_agregar(modelo_e1, base_e1, "E1_extremo_segmento")

pred <- rbindlist(list(pred_b1, pred_e1), use.names = TRUE)
setcolorder(pred, c("escenario", "dia_objetivo", "observado", "predicho"))
fwrite(pred, file.path(path_out, "predicciones_train.csv"))
print(pred[, .(
  primer_dia = min(dia_objetivo),
  ultimo_dia = max(dia_objetivo),
  dias = .N
), by = escenario])
