cargar_datos_levante <- function(modo = c("servidor", "local"),
                         anio_mes,
                         actualizar = F,
                         anio_mes_contexto = integer()) {
  modo <- match.arg(modo)
  anio_mes_ref <- sort(unique(c(anio_mes_contexto, anio_mes)))
  
  if (modo == "servidor") {
    # consulta Hive / Impala
    options(java.parameters = "-Xmx8g")
    config_impala <- leer_configuracion_impala()
    drv <- JDBC(
      "com.cloudera.impala.jdbc.Driver",
      config_impala$jdbc_jar,
      identifier.quote = "´"
    )

    conn <- dbConnect(
      drv,
      config_impala$jdbc_url,
      config_impala$usuario,
      config_impala$password
    )
    
    
    ### Me fijo qué meses están disponibles
    
    meses_disponibles <- dbGetQuery(conn, "
      select distinct anio_mes
      from prod_limpieza.v_analitica_levante_de_contenedores
      order by anio_mes
    ")$anio_mes
    
    
    anio_mes_ref <- anio_mes_ref[anio_mes_ref %in% meses_disponibles]
    
    if(length(anio_mes_ref) == 0) stop('No hay meses para actualizar')
    
    query <- paste0("select levante_contenedor_id,
    levante_fecha_levante,
    levante_circuito,
    levante_posicion_en_circuito,
    levante_activo,
    levante_motivo_no_levante_id,
    levante_motivo_no_levante_descripcion,
    levante_fact,
    levante_porcentaje_llenado,
    levante_periodo,
    levante_longitud,
    levante_latitud,
    anio,
    anio_mes from prod_limpieza.v_analitica_levante_de_contenedores
  where anio_mes in (", paste(anio_mes_ref, collapse = ","), ")"
    )
    
    
    datos <- dbGetQuery(conn,query)

    ## Para ver que memoria tengo disponible en hive
    
    rt <- .jcall("java/lang/Runtime", "Ljava/lang/Runtime;", "getRuntime")
    .jcall(rt, "J", "maxMemory") / 1024^3
    ####################
    dbDisconnect(conn = conn)
    
    return(datos)
    
  } else {
    # leer parquet/csv local
    datos <- arrow::read_parquet("data/paraprobar/datos_levante.parquet")
    if ("anio_mes" %in% names(datos)) {
      datos <- datos[datos$anio_mes %in% anio_mes_ref, ]
    }
    datos
  }
}
