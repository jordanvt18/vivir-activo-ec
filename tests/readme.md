# Pruebas

Dos suites con `testthat`:

| Archivo | Qué prueba |
|---|---|
| `test_indice_sin_datos.R` | Núcleo del IHA: estado «sin datos», umbrales de cobertura, suavizado por credibilidad, umbral de masa crítica y pesos |
| `test_strava_adapter.R` | Adaptador de Strava Metro: esquema, marca de sintético, rechazo de campos personales, ausencia de datos |

`helper-raiz.R` localiza la raíz del proyecto automáticamente, así que las pruebas
funcionan desde la raíz del repositorio, desde `tests/` o con `VAEC_ROOT` definido.

## Ejecutar

```bash
Rscript -e "testthat::test_dir('tests')"
```

## Fixtures

`fixtures/strava_metro_sintetico.csv` contiene **datos sintéticos**, no datos reales de
Strava. Se genera con `set.seed(20260927)` a partir de la población cantonal y lleva la
marca `SINTETICO_NO_SON_DATOS_REALES` en su propia columna `marca`. Ver `fixtures/LEEME.txt`.

## Reportes

`reports/verificacion_datos.txt` lo genera `R/06_verify.R` (14 verificaciones del dataset
publicado, independientes de estas pruebas unitarias).
