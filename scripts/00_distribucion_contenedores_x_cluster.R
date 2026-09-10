library(arrow)
library(dplyr)
library(ggplot2)


dat <- open_dataset(sources = 'data/reference/clusters/cluster_members_ref/version_cluster=v2026_05_25/', 
                    format = 'parquet') %>% collect()


dim(dat)
head(dat)


dat_agg <- dat %>% group_by(cluster_id) %>% count() %>% 
  ungroup() %>% 
  mutate(n_cut = factor(if_else(n >= 5, 5, n), 
                           levels = c(1:5), 
                           labels = as.character(c(1:4,'5 o más')))
         )

dim(dat_agg)
head(dat_agg)

dd <- as.data.frame(table(dat_agg$n_cut)) %>% 
  mutate(porc = round(100*Freq/sum(Freq),1),
         etiq = paste0(porc,'%'))

ggplot(dd, aes(x = Var1, y = Freq)) +
  theme_minimal() + 
  geom_col(fill = 'red', alpha = 0.4) + 
  geom_text(aes(label = etiq), vjust = 1) + 
  xlab('Contenedores en clusters') + 
  ylab('Total clusters')
