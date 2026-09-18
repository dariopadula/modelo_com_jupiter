library(data.table)
library(arrow)

##############################
## funciones
fun <- dir("funciones/", pattern = ".R", ignore.case = TRUE)
for (ii in fun) source(paste0("funciones/", ii))

path_com <- "data/parquet/com"
path_levante <- "data/parquet/levante"

datos_com <- as.data.table(arrow::open_dataset(path_com))
datos_levante <- as.data.table(arrow::open_dataset(path_levante))

chequeo <- chequear_espacial_com_levante(
  datos_com = datos_com,
  datos_levante = datos_levante,
  sample_n = 5000,
  crs = 32721
)

print(chequeo$bbox)
print(chequeo$resumen_distancias)
