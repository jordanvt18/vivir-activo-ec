# Fuentes, licencias y trazabilidad

Todas las fuentes usadas son **abiertas**. Este documento es la versión legible del registro
máquina-legible `data/processed/fuentes.csv`, que acompaña a cada corte publicado.

**Fecha de descarga de todos los insumos: 2026-09-27.**
**Fecha base de OpenStreetMap: 2026-09-27** (guardada por bloque en `data/interim/osm_estado.json`).

---

## 1. Registro de fuentes

| Variable | Fuente | URL | Licencia | Unidad geográfica |
|---|---|---|---|---|
| `dpa_canton`, `canton`, `provincia`, geometría | geoBoundaries gbOpen ADM1/ADM2 (base INEC / OCHA ROLAC) | https://www.geoboundaries.org/api/current/gbOpen/ECU/ADM2/ | **CC BY 3.0 IGO** | provincia / cantón |
| `poblacion`, `pobreza_fgt0`, `gini` | HDX — *Poverty and population data for cantons and parishes in Ecuador* (base INEC) | https://data.humdata.org/dataset/poverty-and-population | **CC BY-IGO** | cantón (DPA de 4 dígitos) |
| Población provincial (control) | HDX — *Ecuador Subnational Population Statistics* (OCHA, base INEC) | https://data.humdata.org/dataset/cod-ps-ecu | **CC BY-IGO** | provincia |
| `acc_hospital_30min_pct` | HeiGIT / Heidelberg Institute for Geoinformation Technology | https://data.humdata.org/dataset/ecuador-accessibility-indicators | **CC BY 4.0** | ADM2 (geoBoundaries) |
| `acc_salud_primaria_30min_pct` | HeiGIT (categoría `primary_healthcare`) | https://data.humdata.org/dataset/ecuador-accessibility-indicators | **CC BY 4.0** | ADM2 |
| `acc_educacion_5km_pct` | HeiGIT (categoría `education`) | https://data.humdata.org/dataset/ecuador-accessibility-indicators | **CC BY 4.0** | ADM2 |
| Conteos de infraestructura (26 columnas `mov_*`, `ver_*`, `dep_*`, `ser_*`, `sal_*`, `tra_*`) | OpenStreetMap contributors vía Overpass API | https://overpass-api.de/api/interpreter | **ODbL 1.0** | cantón (join espacial) |
| `km_ciclovia` | OpenStreetMap contributors vía Overpass API (`out geom`) | https://overpass-api.de/api/interpreter | **ODbL 1.0** | cantón (intersección geométrica) |

Archivos crudos descargados (sin modificar) en `data/raw/`; caché de la API de Overpass en
`data/raw/osm/`.

---

## 2. Qué exige cada licencia

### OpenStreetMap — ODbL 1.0 (Open Database License)
- **Atribución obligatoria:** «© OpenStreetMap contributors».
- **Compartir igual:** si redistribuyes una base de datos derivada, debe quedar bajo ODbL.
- **Uso:** libre, incluido comercial.
- Este proyecto **produce una base derivada** (`iha_cantones.csv`, `cantons.geojson`), por lo que se
  publica bajo ODbL en lo que respecta a la parte derivada de OpenStreetMap.
- Más información: https://www.openstreetmap.org/copyright

### geoBoundaries — CC BY 3.0 IGO
- Atribución obligatoria a geoBoundaries / INEC / OCHA ROLAC.
- Uso libre, incluido comercial, con atribución.
- El original proviene de INEC y OCHA ROLAC.

### HeiGIT — CC BY 4.0
- Atribución obligatoria a HeiGIT / Heidelberg Institute for Geoinformation Technology.
- Uso libre, incluido comercial, con atribución.
- El dataset combina isócronas de `openrouteservice` sobre OpenStreetMap con población WorldPop
  (100 m).

### HDX / INEC (pobreza y población) — CC BY-IGO
- Atribución obligatoria a HDX y a la fuente original (INEC).
- Uso libre con atribución.

---

## 3. Cómo citar

**El proyecto:**

> Vivir Activo EC (2026). *Índice de Habitabilidad Activa (IHA v1.0) por cantón — Ecuador.*
> Corte 2026-09-27. https://github.com/jordanvt18/vivir-activo-ec

**Los datos, según su fuente:**

> OpenStreetMap contributors (2026). *OpenStreetMap* [base de datos]. https://www.openstreetmap.org
> (licencia ODbL 1.0)

> geoBoundaries (2023). *geoBoundaries gbOpen — Ecuador ADM1/ADM2*, base INEC / OCHA ROLAC.
> https://www.geoboundaries.org (licencia CC BY 3.0 IGO)

> HeiGIT (2025). *Ecuador — Accessibility indicators*. HDX.
> https://data.humdata.org/dataset/ecuador-accessibility-indicators (licencia CC BY 4.0)

> HDX / INEC. *Poverty and population data for cantons and parishes in Ecuador* y
> *Ecuador Subnational Population Statistics* (licencia CC BY-IGO)

**Si utilizas el índice:**

> Vivir Activo EC (2026). *Índice de Habitabilidad Activa v1.0*, metodología en
> `docs/metodologia.md`. Pesos: D1 0,22 · D2 0,18 · D3 0,15 · D4 0,20 · D5 0,15 · D6 0,10.

---

## 4. Cómo se mantiene la trazabilidad

1. **Cada columna de indicador tiene al menos una fila** en `data/processed/fuentes.csv` con
   `fuente`, `url`, `licencia`, `fecha_descarga` y `unidad_geografica` no vacíos. Lo comprueba la
   verificación nº 8 de `R/06_verify.R`; si falta alguna, el pipeline falla.
2. **Cada bloque de OpenStreetMap guarda su `timestamp_osm_base`** en
   `data/interim/osm_estado.json` y `data/interim/osm_resumen_grupos.csv`.
3. **Las respuestas crudas de la API quedan cacheadas** en `data/raw/osm/grupo_<nombre>.json`, de
   modo que cualquier cifra puede auditarse contra su origen.
4. **El cruce geográfico es auditable**: `data/interim/xwalk_canton_dpa.csv` indica, para cada
   polígono, con qué método se emparejó y si quedó excluido; `data/interim/cantones_excluidos.csv`
   documenta los dos casos que no son cantones oficiales.
5. **El índice es máquina-legible**: `data/processed/iha_metodologia.json` publica pesos, fórmulas,
   umbrales, tasas nacionales y decisiones de diseño, para que otra persona pueda recalcularlo sin
   leer código R.

---

## 5. Análisis y publicaciones consultadas sobre datos de actividad física

Referencias consultadas el 2026-09-27 para fundamentar **qué se puede y qué no se puede** concluir
de los datos de actividad de plataformas como Strava. Se listan como material de contexto
metodológico; **no son fuentes de datos del índice**.

| Referencia | Aporte | Enlace |
|---|---|---|
| Nelson, J. K. (2020). *User-centered Design and Evaluation of a Bicycle Trip Data Platform*. Cartographic Perspectives. | Describe Strava Metro como producto que agrega y anonimiza actividad ciclista antes de publicarla; base para tratar el dato como agregado. | https://cartographicperspectives.org/ |
| Texas A&M Transportation Institute. *Improving the Amount and Availability of Pedestrian and Bicycle Count Data.* | Encuentra que los conteos peatonales de Strava Metro son una medida **pequeña e inconsistente** frente a conteos reales; evidencia del sesgo de cobertura. | https://static.tti.tamu.edu/ |
| Metropolitan Area Planning Council (MARC). *Regional Bicycle Data Collection Program Memo* (2026). | Señala que estos datasets «pueden estar sesgados y funcionan mejor calibrados con conteos locales». | https://www.marc.org/ |
| Sun, Y. (2017). *Exploiting crowdsourced geographic information and GIS*. | El volumen ciclista de Strava es **razonablemente proporcional** al volumen real en vías principales: sostiene su utilidad relativa, no absoluta. | https://www.sciencedirect.com/ |
| Oksanen, J. et al. (2015). *Methods for deriving and calibrating privacy-preserving heat maps*. | Métodos para derivar mapas de calor que preserven privacidad y corrijan sesgo de participación. | https://www.sciencedirect.com/ |
| TET Coalition. *TDM Validation Activity: Bicycle and Pedestrian Data* (2026). | Documenta el uso de Strava Metro por agencias como dataset agregado. | https://tetcoalition.org/ |
| *Evaluating the effects of Data Sparsity on the Link-level Bicycling Volume* (arXiv). | Evalúa el efecto de la baja densidad de datos de Strava Metro en 15.933 segmentos de Melbourne. | https://arxiv.org/ |
| SAGE (2026). *The role of local sports communities as data agents in urban planning*. | Analiza cómo comunidades deportivas locales median el uso de datos tipo Strava Metro en planificación municipal. | https://journals.sagepub.com/ |
| *Urban Forestry & Urban Greening* (2025). Verificación del potencial del Strava Heatmap para estudios de running. | Discute que el potencial de fuentes semiabiertas como el heatmap **rara vez está verificado**. | https://www.researchgate.net/ |
| OECD. *Big Data and Transport.* | Marco sobre protección de privacidad en datos de localización. | https://www.oecd.org/ |

**Cómo se usaron:** para justificar (a) que Strava Metro es un dato **agregado y licenciado**, no
abierto; (b) que su sesgo de representatividad impide usarlo sin calibración local para ordenar
cantones de todo un país; y (c) que la vía defendible con datos abiertos es medir **infraestructura
y acceso**, no uso.

---

## 6. Nota sobre el fixture de Strava incluido en el repositorio

`tests/fixtures/strava_metro_sintetico.csv` **no contiene datos reales de Strava**. Se genera con
`set.seed(20260927)` a partir de la población cantonal y lleva la marca
`SINTETICO_NO_SON_DATOS_REALES` en su propia columna `marca`. Sirve únicamente para probar el
adaptador. Ver también `tests/fixtures/LEEME.txt`.
