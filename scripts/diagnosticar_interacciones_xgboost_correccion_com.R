library(data.table)
library(xgboost)

set.seed(20260826)

path_base <- file.path(
  "outputs", "exploracion_carga_atraso_ponderada_propension_com",
  "indicadores_segmento_dia.csv"
)
path_modelo <- file.path(
  "outputs", "prueba_xgboost_correccion_estructural_com",
  "modelo_X2_a0_levante_propension.rds"
)
path_out <- "outputs/prueba_xgboost_correccion_estructural_com"

base <- fread(path_base)
base[, dia_objetivo := as.IDate(dia_objetivo)]
base <- base[split_modelo %in% c("validacion", "test")]
base[, dia_semana := factor(dia_semana)]

features <- c(
  "media_tiempo_levante", "media_periodo", "media_ratio", "media_h",
  "prop_exceso_positivo", "prop_exceso_mayor_1", "media_q", "rms_q",
  "media_w", "rms_w"
)
filas_validas <- base[, Reduce(`&`, lapply(.SD, is.finite)), .SDcols = features]
base <- base[filas_validas]

X <- model.matrix(as.formula(paste(
  "~ dia_semana +", paste(features, collapse = " + "), "- 1"
)), data = base)
modelo <- readRDS(path_modelo)
X <- X[, modelo$feature_names, drop = FALSE]

n_muestra <- min(10000L, nrow(X))
idx <- sort(sample.int(nrow(X), n_muestra))
d <- xgb.DMatrix(X[idx, , drop = FALSE])
inter <- predict(
  modelo, d, predinteraction = TRUE, reshape = TRUE, strict_shape = FALSE
)

# La ultima fila/columna corresponde al sesgo. Se promedia la magnitud absoluta
# de cada interaccion y se conserva una sola orientacion del triangulo.
p <- length(modelo$feature_names)
if (length(dim(inter)) != 3L) stop("Forma inesperada de predinteraction")
if (dim(inter)[2L] != p + 1L || dim(inter)[3L] != p + 1L) {
  stop("Dimensiones de interaccion inesperadas")
}
media_abs <- apply(abs(inter[, seq_len(p), seq_len(p), drop = FALSE]), c(2, 3), mean)
pares <- CJ(i = seq_len(p), j = seq_len(p))[i < j]
pares[, `:=`(
  variable_1 = modelo$feature_names[i],
  variable_2 = modelo$feature_names[j],
  interaccion_abs_media = media_abs[cbind(i, j)]
)]
setorder(pares, -interaccion_abs_media)

familia <- function(x) fcase(
  grepl("media_q|rms_q|media_w|rms_w", x), "propension_carga",
  grepl("tiempo_levante|periodo|ratio|media_h|prop_exceso", x), "levante",
  grepl("dia_semana", x), "calendario",
  default = "otra"
)
pares[, `:=`(
  familia_1 = familia(variable_1),
  familia_2 = familia(variable_2)
)]
pares[, cruce_propension_levante :=
  (familia_1 == "propension_carga" & familia_2 == "levante") |
  (familia_2 == "propension_carga" & familia_1 == "levante")]

fwrite(pares, file.path(path_out, "interacciones_shap_pares.csv"))
print(head(pares, 20L))
print(head(pares[cruce_propension_levante == TRUE], 15L))
