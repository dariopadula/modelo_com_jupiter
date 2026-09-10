library(data.table)

dir.create("outputs/experimentos_clima", showWarnings = FALSE, recursive = TRUE)

com_base <- fread("outputs/experimentos_clima/xgboost_com_base_metricas.csv")
com_clima <- fread("outputs/experimentos_clima/xgboost_com_base_clima_metricas.csv")
com_base[, variante := "base"]
com_clima[, variante := "base_clima"]
com <- rbindlist(list(com_base, com_clima), fill = TRUE)
fwrite(com, "outputs/experimentos_clima/comparacion_metricas_com_xgboost_clima.csv")

com_w <- dcast(com, split ~ variante, value.var = c("auc", "logloss"))
com_w[, delta_auc_clima_vs_base := auc_base_clima - auc_base]
com_w[, delta_logloss_clima_vs_base := logloss_base_clima - logloss_base]
fwrite(com_w, "outputs/experimentos_clima/comparacion_metricas_com_xgboost_clima_delta.csv")

zl_base <- fread("zona_limpia/outputs/experimentos_clima/zl_base/modelo_zl_observado_metricas.csv")
zl_clima <- fread("zona_limpia/outputs/experimentos_clima/zl_clima/modelo_zl_observado_metricas.csv")
zl_base[, variante := "base"]
zl_clima[, variante := "base_clima"]
zl <- rbindlist(list(zl_base, zl_clima), fill = TRUE)
fwrite(zl, "zona_limpia/outputs/experimentos_clima/comparacion_metricas_zl_xgboost_clima.csv")

zl_w <- dcast(zl, escenario + split ~ variante, value.var = c("auc", "logloss"))
zl_w[, delta_auc_clima_vs_base := auc_base_clima - auc_base]
zl_w[, delta_logloss_clima_vs_base := logloss_base_clima - logloss_base]
fwrite(zl_w, "zona_limpia/outputs/experimentos_clima/comparacion_metricas_zl_xgboost_clima_delta.csv")

com_imp <- fread("outputs/experimentos_clima/xgboost_com_base_clima_features_importancia.csv")
com_imp[, `:=`(modelo = "com_xgboost", escenario = "unico")]
zl_imp <- fread("zona_limpia/outputs/experimentos_clima/zl_clima/modelo_zl_observado_features_importancia.csv")
zl_imp[, modelo := "zl_xgboost"]

imp <- rbindlist(list(com_imp, zl_imp), fill = TRUE)
fwrite(imp[order(modelo, escenario, variante, -Gain)], "outputs/experimentos_clima/features_importancia_com_y_zl.csv")
imp_clima <- imp[familia == "clima"][order(modelo, escenario, -Gain)]
fwrite(imp_clima, "outputs/experimentos_clima/features_clima_importancia_com_y_zl.csv")

print(com_w)
print(zl_w)
print(imp_clima[, head(.SD, 10), by = .(modelo, escenario)])
