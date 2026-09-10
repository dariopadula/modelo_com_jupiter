# T013 - Diagnosticar cobertura territorial y fuente faltante de Zona Limpia

Estado: pendiente

Prioridad: alta

Area: zona limpia / calidad de datos / territorio

Fecha de creacion: 2026-07-03

### Contexto

El analisis preliminar por municipio, CCZ y barrio muestra
diferencias fuertes de cobertura territorial de Zona Limpia. En
particular, Municipio B aparece muy subrepresentado en la fuente actual,
pero esto se debe a que sus registros de Zona Limpia estan en otra tabla
aun no integrada.

Esto implica que la baja cobertura observada para Municipio B no debe
interpretarse como baja prioridad operativa real ni como ausencia de
visitas. Es un faltante de fuente.

### Plan propuesto

- Documentar explicitamente que Municipio B tiene cobertura incompleta en la fuente actual.

- Conseguir e integrar la tabla adicional con registros Zona Limpia de Municipio B.

- Recalcular la base ampliada o crear un anexo de Zona Limpia que unifique ambas fuentes.

- Rehacer diagnosticos de cobertura por municipio, CCZ y barrio.

- Reentrenar o reevaluar el modelo Zona Limpia observado si cambia sustancialmente la distribucion territorial.

### Criterio de finalizacion

La cobertura territorial de Zona Limpia queda auditada con todas las
fuentes disponibles, y Municipio B deja de aparecer como subrepresentado
por un faltante de datos.

### Notas

Hasta integrar la fuente adicional, las comparaciones territoriales y
modelos Zona Limpia deben marcar Municipio B como cobertura
incompleta.

// add bootstrap table styles to pandoc tables
function bootstrapStylePandocTables() {
  $('tr.odd').parent('tbody').parent('table').addClass('table table-condensed');
}
$(document).ready(function () {
  bootstrapStylePandocTables();
});

$(document).ready(function () {
  window.buildTabsets("TOC");
});

$(document).ready(function () {
  $('.tabset-dropdown > .nav-tabs > li').click(function () {
    $(this).parent().toggleClass('nav-tabs-open');
  });
});

  (function () {
    var script = document.createElement("script");
    script.type = "text/javascript";
    script.src  = "https://mathjax.rstudio.com/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML";
    document.getElementsByTagName("head")[0].appendChild(script);
  })();

