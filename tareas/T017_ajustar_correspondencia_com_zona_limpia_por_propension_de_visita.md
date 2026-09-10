# T017 - Ajustar correspondencia COM-Zona Limpia por propension de visita

Estado: finalizada
Prioridad: alta
Area: zona limpia / sesgo de seleccion / inferencia
Fecha de creacion: 2026-07-03
Fecha de cierre: 2026-07-03

### Contexto

La correspondencia cruda no puede generalizarse directamente porque los lugares visitados por Zona Limpia no son una muestra aleatoria.

### Plan propuesto

1. Entrenar un modelo exploratorio de propension de visita.
2. Corregir probabilidades por prevalencia real.
3. Construir pesos IPW estabilizados.
4. Recalcular correspondencia COM-ZL global y territorial.
5. Documentar supuestos y diagnostico de pesos.

### Criterio de finalizacion

Existen metricas del modelo de propension, diagnostico de pesos y comparaciones crudas frente a ajustadas.

### Notas

Se creo `zona_limpia/12_modelo_propension_visita_zl_y_ajuste_correspondencia.R`. El modelo obtuvo AUC de validacion 0,706. El ratio global problemas ZL/COM paso de 5,44 crudo a 5,65 ajustado; el ajuste no elimina la hipotesis de subreclamo y depende de que las features observadas expliquen suficientemente la seleccion.

