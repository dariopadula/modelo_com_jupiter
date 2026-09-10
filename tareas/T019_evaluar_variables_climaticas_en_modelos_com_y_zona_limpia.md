# T019 - Evaluar variables climaticas en modelos COM y Zona Limpia

Estado: finalizada
Prioridad: media
Area: modelos / clima / zona limpia / COM
Fecha de creacion: 2026-07-13
Fecha de cierre: 2026-07-13

### Contexto

Luego de construir features climaticas se quiere medir su aporte en los objetivos COM y Zona Limpia sin reemplazar los baselines.

### Plan propuesto

1. Agregar soporte opcional de clima a XGBoost COM y ZL.
2. Correr variantes base y base mas clima en salidas separadas.
3. Consolidar metricas, inventarios de features e importancias.
4. Decidir si existe evidencia para promover clima.

### Criterio de finalizacion

Existen comparaciones reproducibles de base frente a clima para COM y ZL.

### Notas

Se agrego soporte mediante `USAR_CLIMA` y el consolidador `scripts/consolidar_experimentos_clima_modelos.R`. En COM el clima no mejora validacion; en ZL mejora el split aleatorio por fila, pero no random por dia ni temporal. No se promueve al baseline.

