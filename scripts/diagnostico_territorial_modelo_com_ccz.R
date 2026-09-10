library(arrow)
library(data.table)

source("funciones/modelos_utils.R")

################################
### Parametros
path_features <- Sys.getenv(
  "PATH_FEATURES_COM",
  unset = "data/processed/modelo_cluster_dia/features_cluster_dia"
)
path_modelo <- Sys.getenv(
  "PATH_MODELO_COM",
  unset = paste0(
    "data/processed/modelos/",
    "logistico_cluster_dia_reducido_reclamos_d2/modelo_logistico_reducido.rds"
  )
)
path_territorio <- Sys.getenv(
  "PATH_TERRITORIO_CLUSTER",
  unset = "data/processed/cluster_territorial/cluster_admin_territorial"
)
out_base <- Sys.getenv(
  "OUT_DIAGNOSTICO_TERRITORIAL_COM",
  unset = "outputs/diagnostico_territorial_modelo_com_ccz"
)
bootstrap_reps <- as.integer(Sys.getenv("BOOTSTRAP_REPS", unset = "1000"))
cortes_top <- c(0.05, 0.10, 0.20)
min_positivos_alerta <- 30L
set.seed(20260716)

if (!file.exists(path_modelo)) {
  stop("No existe el modelo: ", path_modelo)
}
if (is.na(bootstrap_reps) || bootstrap_reps < 0L) {
  stop("BOOTSTRAP_REPS debe ser un entero mayor o igual a cero")
}

modelo <- readRDS(path_modelo)
campos_modelo <- c(
  "coeficientes_prediccion", "features_modelo", "prep",
  "meses_validacion", "meses_test", "fecha_min_modelo",
  "rezago_reclamos_dias", "version_cluster"
)
faltantes_modelo <- setdiff(campos_modelo, names(modelo))
if (length(faltantes_modelo) > 0L) {
  stop("Faltan campos en el modelo: ", paste(faltantes_modelo, collapse = ", "))
}

version_cluster <- modelo$version_cluster
target_col <- "tuvo_reclamo"

################################
### Funciones del diagnostico
brier_binario <- function(y, p) {
  mean((as.integer(y) - p)^2)
}

metricas_binarias <- function(y, p) {
  y <- as.integer(y)
  data.table(
    n = length(y),
    positivos = sum(y == 1L),
    prevalencia = mean(y == 1L),
    pred_media = mean(p),
    diferencia_pred_obs = mean(p) - mean(y == 1L),
    razon_observado_esperado = fifelse(sum(p) > 0, sum(y == 1L) / sum(p), NA_real_),
    auc = auc_binaria(y, p),
    logloss = logloss_binaria(y, p),
    brier = brier_binario(y, p)
  )
}

agregar_metricas_grupo <- function(dt, grupos) {
  dt[, metricas_binarias(target, pred_prob), by = grupos]
}

asignar_top_diario <- function(dt, corte, grupos_ranking) {
  x <- copy(dt)
  setorderv(x, c(grupos_ranking, "pred_prob"), c(rep(1L, length(grupos_ranking)), -1L))
  x[, orden_riesgo := seq_len(.N), by = grupos_ranking]
  x[, n_grupo := .N, by = grupos_ranking]
  x[, seleccionado := orden_riesgo <= pmax(1L, floor(n_grupo * corte))]
  x[, `:=`(orden_riesgo = NULL, n_grupo = NULL)]
  x
}

resumir_ranking <- function(dt_marcado, corte, tipo_ranking) {
  totales_split <- dt_marcado[
    ,
    .(
      total_top_split = sum(seleccionado),
      total_universo_split = .N
    ),
    by = split
  ]
  salida <- dt_marcado[
    ,
    .(
      n = .N,
      positivos = sum(target == 1L),
      seleccionados = sum(seleccionado),
      positivos_seleccionados = sum(target == 1L & seleccionado),
      prevalencia = mean(target == 1L),
      precision = fifelse(sum(seleccionado) > 0, mean(target[seleccionado] == 1L), NA_real_),
      capture_rate = fifelse(
        sum(target == 1L) > 0,
        sum(target == 1L & seleccionado) / sum(target == 1L),
        NA_real_
      ),
      tasa_seleccion = mean(seleccionado),
      lift_vs_ccz = fifelse(
        mean(target == 1L) > 0 & sum(seleccionado) > 0,
        mean(target[seleccionado] == 1L) / mean(target == 1L),
        NA_real_
      ),
      seleccionados_tmp = sum(seleccionado)
    ),
    by = .(split, ccz)
  ]
  salida <- totales_split[salida, on = "split"]
  salida[
    ,
    `:=`(
      top_pct = corte,
      tipo_ranking = tipo_ranking,
      participacion_top = fifelse(
        total_top_split > 0,
        seleccionados_tmp / total_top_split,
        NA_real_
      ),
      participacion_universo = n / total_universo_split,
      razon_representacion = fifelse(
        n / total_universo_split > 0,
        (seleccionados_tmp / total_top_split) / (n / total_universo_split),
        NA_real_
      )
    )
  ]
  salida[, c("total_top_split", "total_universo_split", "seleccionados_tmp") := NULL]
  salida
}

bootstrap_ccz <- function(metricas_diarias, reps) {
  if (reps == 0L) return(data.table())

  claves <- unique(metricas_diarias[, .(split, ccz)])
  rbindlist(lapply(seq_len(nrow(claves)), function(ii) {
    g <- metricas_diarias[
      split == claves$split[ii] & ccz == claves$ccz[ii]
    ]
    if (nrow(g) < 2L) return(NULL)

    estimaciones <- rbindlist(lapply(seq_len(reps), function(rep_i) {
      muestra <- g[sample.int(.N, .N, replace = TRUE)]
      data.table(
        rep = rep_i,
        auc = mean(muestra$auc, na.rm = TRUE),
        brier = mean(muestra$brier, na.rm = TRUE),
        diferencia_pred_obs = mean(muestra$diferencia_pred_obs, na.rm = TRUE),
        razon_observado_esperado = mean(
          muestra$razon_observado_esperado,
          na.rm = TRUE
        )
      )
    }))

    metricas_ci <- c("auc", "brier", "diferencia_pred_obs", "razon_observado_esperado")
    salida <- rbindlist(lapply(metricas_ci, function(metrica) {
      valores <- estimaciones[[metrica]]
      data.table(
        metrica = metrica,
        estimacion_bootstrap = mean(valores, na.rm = TRUE),
        ci_025 = as.numeric(quantile(valores, 0.025, na.rm = TRUE)),
        ci_975 = as.numeric(quantile(valores, 0.975, na.rm = TRUE)),
        reps_validas = sum(is.finite(valores)),
        estimando = "media_diaria"
      )
    }))
    salida[, `:=`(split = g$split[1], ccz = g$ccz[1])]
    salida
  }), use.names = TRUE, fill = TRUE)
}

################################
### Reconstruyo predicciones sin reentrenar
datos <- as.data.table(open_dataset(path_features, format = "parquet"))
datos <- datos[version_cluster == modelo$version_cluster]

features_derivadas <- c(
  "historia_observada_7_29",
  "historia_observada_30_89",
  "historia_observada_90_179",
  "historia_observada_180_mas",
  "dias_desde_ultimo_reclamo_o_inicio_trunc_90",
  "exceso_mean_tiempo_periodo_pred_pos",
  "exceso_mean_tiempo_periodo_pred_trunc_7"
)
cols_req <- unique(c(
  "version_cluster", "cluster_id", "dia", "anio_mes", target_col,
  "n_reclamos", setdiff(modelo$features_modelo, features_derivadas),
  "dias_historia_observada_cluster", "dias_desde_ultimo_reclamo_o_inicio"
))
faltantes_datos <- setdiff(cols_req, names(datos))
if (length(faltantes_datos) > 0L) {
  stop("Faltan columnas en features: ", paste(faltantes_datos, collapse = ", "))
}

datos <- datos[dia >= as.IDate(modelo$fecha_min_modelo)]
if (modelo$rezago_reclamos_dias != 1L) {
  datos <- aplicar_rezago_historia_reclamos(
    datos,
    rezago_reclamos_dias = modelo$rezago_reclamos_dias
  )
}
datos <- agregar_features_logistico_reducido(datos)
if (isTRUE(modelo$usar_exceso_levante)) {
  datos <- agregar_features_exceso_levante_periodo(datos)
}

datos[, split := fcase(
  anio_mes %in% modelo$meses_validacion, "validacion",
  anio_mes %in% modelo$meses_test, "test",
  default = NA_character_
)]
evaluacion <- datos[!is.na(split)]
if (nrow(evaluacion) == 0L) stop("No hay filas de validacion o test")

matriz <- preparar_matriz(
  evaluacion,
  modelo$features_modelo,
  prep = modelo$prep
)$x
x <- cbind(intercept = 1, matriz)
if (!identical(colnames(x), names(modelo$coeficientes_prediccion))) {
  stop("Las columnas reconstruidas no coinciden con los coeficientes del modelo")
}

evaluacion[, pred_prob := as.numeric(plogis(x %*% modelo$coeficientes_prediccion))]
predicciones <- evaluacion[, .(
  version_cluster,
  cluster_id,
  dia,
  anio_mes,
  split,
  target = as.integer(get(target_col)),
  n_reclamos,
  pred_prob
)]

################################
### Cruce territorial y controles
territorio <- as.data.table(open_dataset(path_territorio, format = "parquet"))
territorio <- territorio[version_cluster == modelo$version_cluster, .(
  version_cluster,
  cluster_id,
  municipio,
  ccz
)]

duplicados_territorio <- territorio[, .N, by = .(version_cluster, cluster_id)][N > 1L]
if (nrow(duplicados_territorio) > 0L) {
  stop("La tabla territorial duplica version_cluster/cluster_id")
}

pred_territorio <- territorio[
  predicciones,
  on = .(version_cluster, cluster_id)
]

control_cobertura <- pred_territorio[
  ,
  .(
    filas = .N,
    clusters = uniqueN(cluster_id),
    dias = uniqueN(dia),
    positivos = sum(target == 1L),
    filas_sin_ccz = sum(is.na(ccz)),
    clusters_sin_ccz = uniqueN(cluster_id[is.na(ccz)]),
    ccz = uniqueN(ccz, na.rm = TRUE)
  ),
  by = split
]
if (anyNA(pred_territorio$ccz)) {
  stop("Hay predicciones sin CCZ; revisar control_cobertura.csv")
}

################################
### Metricas
metricas_globales <- agregar_metricas_grupo(pred_territorio, "split")
metricas_ccz <- agregar_metricas_grupo(pred_territorio, c("split", "ccz"))
volumen_ccz <- pred_territorio[
  ,
  .(
    clusters = uniqueN(cluster_id),
    dias = uniqueN(dia),
    meses = uniqueN(anio_mes)
  ),
  by = .(split, ccz)
]
metricas_ccz <- volumen_ccz[metricas_ccz, on = .(split, ccz)]
metricas_ccz[, alerta_pocos_positivos := positivos < min_positivos_alerta]

metricas_mensuales_ccz <- agregar_metricas_grupo(
  pred_territorio,
  c("split", "anio_mes", "ccz")
)
metricas_diarias_ccz <- agregar_metricas_grupo(
  pred_territorio,
  c("split", "dia", "ccz")
)

pred_territorio[, banda_score_global := pmin(
  5L,
  ceiling(frank(pred_prob, ties.method = "average") / .N * 5)
), by = split]
calibracion_ccz_bandas <- pred_territorio[
  ,
  .(
    n = .N,
    positivos = sum(target == 1L),
    pred_media = mean(pred_prob),
    obs_rate = mean(target == 1L),
    diferencia_pred_obs = mean(pred_prob) - mean(target == 1L)
  ),
  by = .(split, ccz, banda_score_global)
]

ranking_base <- copy(pred_territorio)
ranking_base[, `:=`(
  orden_global = frank(-pred_prob, ties.method = "first"),
  n_global = .N
), by = .(split, dia)]
ranking_base[, `:=`(
  orden_local = frank(-pred_prob, ties.method = "first"),
  n_local = .N
), by = .(split, dia, ccz)]

rankings <- rbindlist(lapply(cortes_top, function(corte) {
  ranking_base[, seleccionado := orden_global <= pmax(1L, floor(n_global * corte))]
  resumen_global <- resumir_ranking(ranking_base, corte, "global_ciudad")

  ranking_base[, seleccionado := orden_local <= pmax(1L, floor(n_local * corte))]
  resumen_local <- resumir_ranking(ranking_base, corte, "local_ccz")

  rbindlist(list(resumen_global, resumen_local), use.names = TRUE)
}), use.names = TRUE)

intervalos_bootstrap <- bootstrap_ccz(metricas_diarias_ccz, bootstrap_reps)

################################
### Guardo salidas
dir.create(out_base, recursive = TRUE, showWarnings = FALSE)

salidas <- list(
  control_cobertura = control_cobertura,
  metricas_globales = metricas_globales,
  metricas_ccz = metricas_ccz,
  metricas_diarias_ccz = metricas_diarias_ccz,
  metricas_mensuales_ccz = metricas_mensuales_ccz,
  calibracion_ccz_bandas = calibracion_ccz_bandas,
  ranking_ccz = rankings,
  intervalos_bootstrap_ccz = intervalos_bootstrap
)

for (nombre in names(salidas)) {
  fwrite(salidas[[nombre]], file.path(out_base, paste0(nombre, ".csv")))
}

metadata <- data.table(
  version_cluster = version_cluster,
  path_modelo = path_modelo,
  rezago_reclamos_dias = modelo$rezago_reclamos_dias,
  meses_validacion = paste(modelo$meses_validacion, collapse = ","),
  meses_test = paste(modelo$meses_test, collapse = ","),
  bootstrap_reps = bootstrap_reps,
  cortes_top = paste(cortes_top, collapse = ",")
)
fwrite(metadata, file.path(out_base, "metadata.csv"))

print(control_cobertura)
print(metricas_globales)
print(metricas_ccz[order(split, auc)])
