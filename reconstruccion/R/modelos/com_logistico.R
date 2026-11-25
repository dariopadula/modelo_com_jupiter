# Adaptador COM fijo; sin acceso a datos.

# Aplica el bundle COM fijo y ordena el bloque preparado.  Entradas: historia, bundle,
# dia y universo. Salida: scores, ranking y flags top.

# Aplica el bundle COM fijo y ordena el bloque preparado.  Entradas: historia, bundle,
# dia y universo. Salida: scores, ranking y flags top.
rf_score_com <- function(history, model, day, universe_n) {
  stopifnot(is.data.frame(history), length(day) == 1L, !is.na(day))
  history <- as.data.frame(history)
  if (model$rezago_reclamos_dias != 2L)
    stop("Bundle COM no es D-2")
  if (any(history$version_cluster != model$version_cluster))
    stop("Version espacial incompatible")
  if (anyDuplicated(history[c("cluster_id", "dia")]))
    stop("Historia duplicada")
  prepared <- agregar_features_logistico_reducido(aplicar_rezago_historia_reclamos(data.table::as.data.table(history),
    model$rezago_reclamos_dias))
  scored <- prepared[dia == data.table::as.IDate(day)]
  if (!nrow(scored))
    stop("Sin features para el dia")
  if (universe_n < nrow(scored))
    stop("Universo menor que muestra")
  mat <- preparar_matriz(scored, model$features_modelo, prep = model$prep)$x
  x <- cbind(intercept = 1, mat)
  if (ncol(x) != length(model$coeficientes_prediccion))
    stop("Matriz incompatible")
  pred <- data.frame(cluster_id = scored$cluster_id, dia_objetivo = as.Date(scored$dia),
    modelo_id = "com_reclamo", version_modelo = "logistico_reducido_d2", version_cluster = model$version_cluster,
    pred_prob = as.numeric(stats::plogis(x %*% model$coeficientes_prediccion)), target_app = "reclamo_com",
    n_contenedores_activos = scored$n_contenedores_activos)
  pred <- pred[order(-pred$pred_prob, pred$cluster_id), ]
  pred$ranking_dia <- seq_len(nrow(pred))
  pred$percentil_riesgo <- pred$ranking_dia/universe_n
  for (pct in c(1, 5, 10, 20)) pred[[paste0("top_", pct)]] <- pred$percentil_riesgo <=
    pct/100
  rownames(pred) <- NULL
  pred
}
