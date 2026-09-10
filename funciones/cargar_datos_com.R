cargar_datos_com <- function(modo = c("servidor", "local"),
                         anio_mes,
                         actualizar = F) {
  modo <- match.arg(modo)
  
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
    from prod_limpieza.reclamos_com
    order by anio_mes
  ")$anio_mes
    
    
    ### Veo las columnas que tiene
    cols <- dbGetQuery(conn, "
    DESCRIBE prod_limpieza.reclamos_com
  ")$name
    
    ### Defino las colunas a saca
    cols_exclude <- c("transportista","direccion","gid_contenedor")
    
    ### Columnas a traer
    cols_keep <- setdiff(cols,cols_exclude)
    
    ### Identifica los anios_meses a traer
    anio_mes_ref <- anio_mes[anio_mes %in% meses_disponibles]
    mes_aux <- integer()
    if(actualizar) {
      anio_mes_ref <- meses_disponibles[meses_disponibles >= max(anio_mes)] 
    }
    
    if(length(anio_mes_ref) == 0) stop('No hay meses para actualizar')
    
    query <- paste0(
      "SELECT ", paste(cols_keep, collapse = ", "), "
   FROM prod_limpieza.reclamos_com
   WHERE anio_mes IN (", paste(anio_mes_ref, collapse = ","), ")"
    )
    
    
    datos <- dbGetQuery(conn,query)
    dim(datos)
    
    ## Para ver que memoria tengo disponible en hive
    
    rt <- .jcall("java/lang/Runtime", "Ljava/lang/Runtime;", "getRuntime")
    .jcall(rt, "J", "maxMemory") / 1024^3
    ####################
    dbDisconnect(conn = conn)
    
    
    return(datos)
    
  } else {
    # leer parquet/csv local
    arrow::read_parquet("data/paraprobar/datos_com.parquet")
  }
}
