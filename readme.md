# Vivir Activo EC

**¿Dónde es más fácil vivir una vida cotidiana activa en Ecuador?** Un índice por cantón
construido con datos abiertos, un mapa interactivo y toda la metodología auditable.

[![Verificación](https://img.shields.io/badge/verificaciones-14%2F14%20PASS-7d8f69)](#verificación)
[![Cobertura](https://img.shields.io/badge/cobertura-221%20cantones%20%2F%2024%20provincias-1e3a5f)](#qué-contiene)
[![Datos personales](https://img.shields.io/badge/datos%20personales-ninguno-c99a63)](#privacidad)

---

## En línea

**Aplicación web (mapa dinámico, filtros encadenados de provincia y cantón):**

> ### → https://jordanvt18.github.io/vivir-activo-ec/

Servida con **GitHub Pages** desde la rama `gh-pages` de este repositorio. Es un sitio estático:
no necesita servidor ni R en producción. Aplicación equivalente en R (Shiny) en `app/`.

---

## Qué es esto

La idea de partida es la de los análisis que usan datos de actividad física (Strava y similares)
para entender cómo se mueve la gente y qué hace habitable un lugar. Este proyecto traslada esa
lógica a **Ecuador**, a escala de **cantón**, y la convierte en una herramienta para quien está
pensando dónde mudarse.

El resultado es el **Índice de Habitabilidad Activa (IHA v1.0)**: un número de 0 a 100 por cantón
que combina seis dimensiones medibles con datos abiertos.

| Dimensión | Peso | Qué mide |
|---|---:|---|
| D1 · Movilidad activa | 22 % | Ciclovías, red peatonal y senderos por habitante |
| D2 · Deporte y recreación | 18 % | Canchas, centros deportivos, gimnasios, piscinas, pistas, estadios |
| D3 · Naturaleza y áreas verdes | 15 % | Parques, jardines, reservas y áreas de recreo |
| D4 · Acceso a salud y educación | 20 % | Población a ≤30 min de hospital y atención primaria; ≤5 km de escuela |
| D5 · Servicios y vida cotidiana | 15 % | Escuelas, universidades, bibliotecas, mercados, supermercados, transporte |
| D6 · Contexto socioeconómico | 10 % | Pobreza por ingresos (FGT0) y desigualdad (Gini) |

## Sobre Strava: qué hicimos y qué no

**No usamos datos de Strava.** Strava Metro —el producto agregado que usan los estudios de
planificación— exige un **acuerdo de uso comercial** y no es un conjunto de datos abiertos.
El heatmap global no puede usarse ni reconstruirse porque sus términos lo prohíben.

En lugar de inventar un indicador "Strava" o de presentar un proxy como si fuera actividad real,
el proyecto hace tres cosas:

1. **Mide lo que sí es abierto** y sostiene la actividad física: la infraestructura
   (OpenStreetMap) y el acceso a servicios (HeiGIT).
2. **Documenta el sesgo** de los datos de actividad voluntaria (Strava sobra-representa a
   hombres, adultos y residentes urbanos de renta alta).
3. **Deja el conector implementado y probado**: `R/05_strava_adapter.R` + `R/lib_strava.R`
   leen un esquema agregado por cantón y lo incorporan como columnas informativas, sin tocar los
   pesos del IHA. Si el proyecto consigue licencia, se integra sin reescribir nada.
   Ver [`docs/metodologia.md`](docs/metodologia.md#por-qué-no-hay-un-indicador-strava-directo).

## Qué contiene

```
vivir-activo-ec/
├── app/                      Aplicación Shiny (mapa dinámico + filtros encadenados)
├── web/                      Sitio estático publicado (Leaflet, sin servidor)
│   ├── index.html  app.js  styles.css
│   └── data/                 Paquete de datos que consume la web
├── R/                        Pipeline reproducible
│   ├── 00_setup.R            Rutas, paquetes, utilidades
│   ├── 01_fetch_osm.R        Descarga OpenStreetMap (Overpass, con caché)
│   ├── 02_build_geography.R  Límites, cruce DPA, simplificación
│   ├── 03_build_indicators.R Unión de los cinco bloques de datos
│   ├── 04_build_index.R      Cálculo del IHA
│   ├── 05_strava_adapter.R   Adaptador Strava Metro (opcional)
│   ├── 06_verify.R           14 verificaciones automáticas
│   ├── 07_build_web.R        Genera los datos del sitio
│   ├── lib_iha.R             Núcleo del índice (usado también por las pruebas)
│   └── lib_strava.R          Lógica del adaptador (usado también por las pruebas)
├── data/
│   ├── raw/                  Insumos originales con su fuente
│   ├── interim/              Intermedios y cruces auditables
│   └── processed/            Publicables: índice, metodología, fuentes
├── docs/                     Metodología, guía de uso, fuentes, privacidad, despliegue
├── tests/                    Pruebas unitarias y reporte de verificación
└── run_all.R                 Punto de entrada único del pipeline
```

## Ejecutar

Requisitos: **R 4.4+** y conexión a internet para la descarga de OpenStreetMap.

```r
# pipeline completo (descarga + cálculo + verificación)
Rscript run_all.R

# si ya tienes la caché de OSM descargada
Rscript run_all.R --skip-fetch

# pruebas unitarias
Rscript -e "testthat::test_dir('tests')"

# aplicación Shiny
Rscript -e "shiny::runApp('app')"
```

`run_all.R` termina con **código de salida distinto de cero** si alguna verificación falla, para
que el pipeline no declare éxito en falso.

## Resultados del corte actual (2026-09-27)

| Indicador | Valor |
|---|---|
| Cantones analizados | **221** (24 provincias, cobertura completa de la DPA del INEC) |
| IHA: mínimo / mediana / máximo | 11,7 / 47,2 / 86,2 |
| Elementos de OpenStreetMap procesados | 117.721 descargados, **105.189** (89,4 %) asignados a un cantón |
| Ciclovías | 1.022 tramos, **565,3 km**, presentes en 46 cantones |
| Cobertura de accesibilidad (HeiGIT) | hospital 217 · atención primaria 202 · escuela 216 cantones |
| Cantones marcados «sin datos» | 0 (ninguno quedó por debajo del umbral de cobertura) |

**Diez primeros cantones:** Cuenca (86,2), Ibarra (85,1), Mejía (79,7), Latacunga (79,6),
Quito (79,0), Portoviejo (78,1), Loja (78,0), Zamora (77,8), Gualaceo (76,3), Samborondón (76,0).

**Provincias mejor situadas:** Pichincha (77,4), Azuay (76,8), Imbabura (75,3), Tungurahua (68,8),
Galápagos (68,4).

## Verificación

`R/06_verify.R` produce [`tests/reports/verificacion_datos.txt`](tests/reports/verificacion_datos.txt)
con **14 verificaciones**, todas en PASS en el corte publicado:

| # | Verificación | Resultado |
|---|---|---|
| 1 | 24 provincias y 221 cantones oficiales presentes | PASS |
| 2 | Clave cantonal única | PASS |
| 3 | Rangos válidos (IHA 0-100; pobreza y Gini 0-1) | PASS |
| 4 | Ningún cantón «sin datos» con IHA = 0 | PASS |
| 5 | Suma cantonal de conteos OSM = suma provincial | PASS |
| 6 | Emparejamiento geográfico auditado | PASS |
| 7 | Contraste de población + sensibilidad del ranking | PASS |
| 8 | Trazabilidad de fuentes (URL, licencia, fecha) | PASS |
| 9 | Filtros encadenados provincia → cantón | PASS |
| 10 | Pipeline completo y reproducible | PASS |
| 11 | Privacidad: sin campos personales | PASS |
| 12 | Coherencia del índice entre escalas | PASS |
| 13 | Mecanismo «sin datos» probado funcionalmente | PASS |
| 14 | Sensibilidad al umbral de masa crítica | PASS |

Más **41 aserciones unitarias** en `tests/` (`testthat`).

## Privacidad

No hay datos personales, ni rastreo, ni niveles inferiores al cantón. Todos los insumos son
agregados geográficos. Detalle en [`docs/privacidad.md`](docs/privacidad.md).

## Licencias

- **Código:** MIT (`LICENSE`).
- **Datos:** según su fuente — OpenStreetMap **ODbL 1.0**, geoBoundaries **CC BY 3.0 IGO**,
  HeiGIT **CC BY 4.0**, HDX / INEC **CC BY-IGO**. Detalle en
  [`docs/fuentes_y_licencias.md`](docs/fuentes_y_licencias.md).

## Límites, en una frase

Mide **oportunidad de vida activa y acceso**, no calidad de vida completa: no evalúa vivienda,
empleo, seguridad ni calidad real de los servicios, y OpenStreetMap refleja lo que está **mapeado**,
no necesariamente lo que existe. Es una herramienta de exploración de datos abiertos, **no una
asesoría inmobiliaria, legal ni financiera**.

---

*Datos de OpenStreetMap © colaboradores de OpenStreetMap (ODbL 1.0) · Límites: geoBoundaries
(CC BY 3.0 IGO) · Población y pobreza: HDX / INEC · Accesibilidad: HeiGIT (CC BY 4.0).*
