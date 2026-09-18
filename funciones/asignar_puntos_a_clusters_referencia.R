asignar_puntos_a_clusters_referencia <- function(puntos_nuevos,
                                                 cluster_members_ref,
                                                 umbral_asignacion_m = 50,
                                                 umbral_revision_m = 100,
                                                 crs = 32721) {
  data.table::setDT(puntos_nuevos)
  data.table::setDT(cluster_members_ref)

  if (!all(c("x", "y") %in% names(puntos_nuevos))) {
    stop("puntos_nuevos debe tener columnas x e y en CRS ", crs)
  }

  if (!all(c("x", "y", "cluster_id", "punto_ref_id", "version_cluster") %in% names(cluster_members_ref))) {
    stop("cluster_members_ref debe tener x, y, cluster_id, punto_ref_id y version_cluster")
  }

  puntos_validos <- puntos_nuevos[!is.na(x) & !is.na(y)]
  if (nrow(puntos_validos) == 0) stop("No hay puntos nuevos con coordenadas validas")

  if (!"punto_nuevo_id" %in% names(puntos_validos)) {
    puntos_validos[, punto_nuevo_id := paste0("N", sprintf("%07d", .I))]
  }

  ref <- cluster_members_ref[!is.na(x) & !is.na(y)]
  if (nrow(ref) == 0) stop("cluster_members_ref no tiene coordenadas validas")

  nn <- vecinos_cercanos(
    data = as.matrix(ref[, .(x, y)]),
    query = as.matrix(puntos_validos[, .(x, y)]),
    k = 1
  )

  idx <- nn$nn.index[, 1]
  dist <- nn$nn.dist[, 1]

  res <- puntos_validos[, .(punto_nuevo_id, x, y)]
  res[, `:=`(
    version_cluster = ref$version_cluster[idx],
    cluster_id_candidato = ref$cluster_id[idx],
    punto_ref_id_mas_cercano = ref$punto_ref_id[idx],
    distancia_m = dist,
    estado_asignacion = data.table::fcase(
      dist <= umbral_asignacion_m, "asignado",
      dist <= umbral_revision_m, "revision",
      default = "pendiente"
    )
  )]

  res[, cluster_id_asignado := data.table::fifelse(
    estado_asignacion %in% c("asignado", "revision"),
    cluster_id_candidato,
    NA_character_
  )]

  res[, `:=`(
    umbral_asignacion_m = umbral_asignacion_m,
    umbral_revision_m = umbral_revision_m,
    crs = crs,
    fecha_asignacion = as.Date(Sys.Date())
  )]

  res[]
}
