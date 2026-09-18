library(arrow)
library(data.table)

source("funciones/splits_temporales.R")

path_contrato <- "config/splits_reevaluacion_2026.csv"
path_calendario <- "data/processed/features_compartidas/calendario_dia.parquet"
out_calendario <- paste0(
  "data/processed/features_compartidas/",
  "calendario_splits_reevaluacion_2026.parquet"
)
out_metadata <- paste0(
  "data/processed/features_compartidas/",
  "metadata_splits_reevaluacion_2026.csv"
)

contrato <- leer_contrato_splits(path_contrato)
calendario <- as.data.table(arrow::read_parquet(path_calendario))
calendario[, dia := as.IDate(dia)]
calendario_split <- asignar_split_congelado(calendario, contrato = contrato)

if (anyDuplicated(calendario_split$dia)) stop("Hay dias duplicados")
if (calendario_split[is.na(split), .N]) stop("Hay dias sin split")

arrow::write_parquet(calendario_split, out_calendario, compression = "zstd")

metadata <- calendario_split[, .(
  fecha_desde = min(dia),
  fecha_hasta = max(dia),
  n_dias = .N
), by = .(version_split, split)]
metadata[contrato, on = c("version_split", "split"), `:=`(
  orden = i.orden,
  uso_permitido = i.uso_permitido,
  puede_ajustar = i.puede_ajustar,
  puede_seleccionar = i.puede_seleccionar,
  puede_reportar_metricas_ahora = i.puede_reportar_metricas_ahora,
  estado = i.estado
)]
metadata[, `:=`(
  fecha_congelacion = as.IDate("2026-09-16"),
  contrato_md5 = unname(tools::md5sum(path_contrato))
)]
setorder(metadata, orden)
fwrite(metadata, out_metadata)

print(metadata)
