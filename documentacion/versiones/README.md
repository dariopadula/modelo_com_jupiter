# Versiones Y Registros De Cambio

Esta carpeta guarda registros puntuales de cambios relevantes del proyecto. No reemplaza Git, pero funciona como memoria humana mientras el proyecto se ordena y permite retomar decisiones sin depender de conversaciones previas.

## Cuando Crear Una Version

Crear un archivo nuevo cuando haya:

- cambios relevantes en modelos;
- cambios en reglas de datos o scoring operativo;
- cambios importantes en la app;
- decisiones conceptuales que afecten resultados;
- reorganizaciones de documentacion o estructura.

Los cambios menores pueden registrarse solo en `documentacion/HITOS.md` o `TAREAS.md`.

## Convencion De Nombre

Usar:

```text
YYYY-MM-DD_tema_del_cambio.md
```

Ejemplo:

```text
2026-06-30_memoria_proyecto.md
```

## Plantilla Sugerida

```markdown
# Cambio: titulo breve

Fecha:
Area:

## Contexto

## Cambios realizados

## Decisiones tomadas

## Validaciones

## Riesgos o pendientes
```

