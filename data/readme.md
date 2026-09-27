# Carpeta de datos

## Qué se versiona y qué no

| Carpeta | ¿En git? | Por qué |
|---|---|---|
| `data/processed/` | **Sí** | Son los productos publicables: índice, indicadores, metodología y registro de fuentes |
| `data/raw/` | No (~80 MB) | Insumos originales y caché de la API de Overpass; regenerables |
| `data/interim/` | No (~18 MB) | Intermedios y cruces; regenerables |
| `data/external/strava_metro/` | No | Reservado para datos licenciados de Strava Metro, si algún día existen |

## Cómo regenerar lo que no se versiona

```bash
Rscript run_all.R          # descarga OpenStreetMap, reconstruye todo y verifica
```

Solo la infraestructura de OpenStreetMap se descarga por API (`R/01_fetch_osm.R`, con caché
reanudable). Los demás insumos son descargas directas con URL fija, listadas en
[`../docs/fuentes_y_licencias.md`](../docs/fuentes_y_licencias.md#1-registro-de-fuentes):

| Archivo esperado en `data/raw/` | Origen |
|---|---|
| `geoBoundaries-ECU-ADM1.geojson` | geoBoundaries gbOpen ECU ADM1 |
| `geoBoundaries-ECU-ADM2.geojson` | geoBoundaries gbOpen ECU ADM2 |
| `poverty_population_cantons_parishes.xlsx` | HDX — *Poverty and population data for cantons and parishes in Ecuador* |
| `ecu_admpop_adm1_2020.csv` | HDX — *Ecuador Subnational Population Statistics* |
| `ECU_hospitals_access_wide.csv` | HeiGIT — accesibilidad (hospitales) |
| `ECU_primary_healthcare_access_wide.csv` | HeiGIT — accesibilidad (atención primaria) |
| `ECU_education_access_wide.csv` | HeiGIT — accesibilidad (educación) |

## Trazabilidad

Aunque los crudos no se versionen, la procedencia **no se pierde**:

- `data/processed/fuentes.csv` registra, por variable, la fuente, la URL, la licencia, la fecha de
  descarga y la unidad geográfica. La verificación nº 8 del pipeline falla si falta alguna.
- `data/interim/osm_estado.json` guarda, por bloque de OpenStreetMap, la fecha base de la base de
  datos (`timestamp_osm_base`) y el endpoint usado.
- `data/interim/xwalk_canton_dpa.csv` y `data/interim/cantones_excluidos.csv` documentan cada
  decisión de emparejamiento geográfico.
