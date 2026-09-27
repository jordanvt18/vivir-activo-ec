# Despliegue y publicación

El proyecto tiene **dos entregables ejecutables** con la misma lógica y los mismos datos:

1. **Sitio web estático** (`web/`): Leaflet + JavaScript puro. Se publica en **GitHub Pages**.
   No necesita servidor ni R en producción.
2. **Aplicación Shiny** (`app/`): la misma experiencia en R. Se despliega en **shinyapps.io**
   o en un Shiny Server propio, si se quiere el comportamiento reactivo completo en servidor.

---

## 1. Sitio estático en GitHub Pages (recomendado)

### 1.1 Publicar

```bash
# desde la raíz del repositorio
git add -A
git commit -m "Publicar sitio y datos"
git subtree push --prefix web origin gh-pages
```

o, de forma explícita con un worktree:

```bash
git worktree add -B gh-pages /tmp/vaec-ghpages
cp -r web/* /tmp/vaec-ghpages/
cd /tmp/vaec-ghpages
git add -A && git commit -m "Sitio Vivir Activo EC"
git push origin gh-pages
```

Después, en **Settings → Pages** del repositorio, selecciona la rama `gh-pages` y la carpeta raíz
`/`. La URL queda del tipo:

```
https://<usuario>.github.io/vivir-activo-ec/
```

### 1.2 Requisitos del contenido publicado

El sitio es **estático y sin dependencias remotas de datos**:

| Archivo | Tamaño aproximado | Papel |
|---|---|---|
| `web/index.html` | 9 KB | Estructura y textos |
| `web/styles.css` | 11 KB | Estilo «cartografía cálida de datos» |
| `web/app.js` | 21 KB | Mapa, filtros encadenados, tabla |
| `web/data/indicadores.json` | 190 KB | Catálogo y valores por cantón |
| `web/data/cantones.geojson` | 1,3 MB | Límites cantonales simplificados |
| `web/data/provincias.geojson` | 23 KB | Límites provinciales |
| `web/data/iha_cantones.csv` | 100 KB | Tabla descargable |
| `web/data/iha_provincias.csv` | 12 KB | Agregado provincial descargable |
| `web/data/iha_metodologia.json` | 6 KB | Pesos y fórmulas |
| `web/data/fuentes.csv` | 3 KB | Registro de fuentes |

Únicas dependencias externas: **Leaflet 1.9.4** (unpkg) y los **tiles de CARTO/OpenStreetMap**.
Ambas son CDN públicos y gratuitos. Si necesitas que el sitio funcione **sin internet**, descarga
Leaflet y los tiles a `web/vendor/` y ajusta las rutas en `index.html` y `app.js`.

### 1.3 Comprobar el despliegue

```bash
python -m http.server 8000 --directory web
# abre http://localhost:8000 y prueba: filtro de provincia, filtro de cantón, cambio de indicador
```

---

## 2. Aplicación Shiny

### 2.1 Ejecutar en local

```bash
Rscript -e "shiny::runApp('app')"
```

La app busca los datos en `data/processed/`. Si la ejecutas desde otra carpeta, define la variable
de entorno:

```bash
# Linux / macOS
VAEC_ROOT=/ruta/a/vivir-activo-ec Rscript -e "shiny::runApp('app')"
# Windows (PowerShell)
$env:VAEC_ROOT = "C:\ruta\a\vivir-activo-ec"; Rscript -e "shiny::runApp('app')"
```

### 2.2 Publicar en shinyapps.io

```r
install.packages("rsconnect")
rsconnect::setAccountInfo(name = "<cuenta>",
                          token = "<token>",
                          secret = "<secret>")
rsconnect::deployApp(
  appDir   = "app",
  appName  = "vivir-activo-ec",
  appFiles = c("app.R",
               "../data/processed/iha_cantones.csv",
               "../data/processed/cantons.geojson",
               "../data/processed/provinces.geojson")
)
```

> **Nota:** `deployApp` no copia archivos fuera de `appDir` por defecto. La forma más simple es
> **copiar previamente** `data/processed/` dentro de `app/` con un script de empaquetado:

```bash
mkdir -p app/data && cp data/processed/iha_cantones.csv data/processed/cantons.geojson \
     data/processed/provinces.geojson app/data/
```

y hacer que `app.R` busque también en `./data` (ya lo hace: `raiz_proyecto()` acepta la carpeta
que contenga `data/processed`).

### 2.3 Alternativa sin costo: GitHub + Shiny vía contenedor

Si no quieres shinyapps.io, el sitio estático ya cubre la necesidad de URL pública. La app Shiny
queda como herramienta local de análisis o para despliegue interno.

---

## 3. Regenerar los datos

```bash
Rscript run_all.R              # pipeline completo (incluye descarga de OSM)
Rscript run_all.R --skip-fetch  # solo recálculo, usando la caché de OSM
```

El pipeline es **idempotente y reanudable**: cada bloque de OpenStreetMap se guarda en
`data/raw/osm/grupo_<nombre>.json` y no se vuelve a descargar si ya existe. Si una consulta falla,
basta con volver a ejecutar `R/01_fetch_osm.R`: solo pedirá lo que falte.

`run_all.R` **termina con código distinto de cero** si alguna verificación de `R/06_verify.R` falla.

### Tiempos observados en este entorno

| Paso | Tiempo |
|---|---|
| `01_fetch_osm.R` (26 grupos, primera vez) | ~20-35 min (el endpoint público tiene rate-limit y devuelve 504/429; el script reintenta con espera creciente) |
| `01_fetch_osm.R` (desde caché) | ~40 s |
| `02_build_geography.R` | ~4 min |
| `03_build_indicators.R` | ~2 min |
| `04_build_index.R` | < 10 s |
| `05_strava_adapter.R` | < 5 s |
| `07_build_web.R` | < 10 s |
| `06_verify.R` | ~30 s |

---

## 4. Notas de operación

- **Sé amable con Overpass API.** Es un servicio público y gratuito. El script usa un User-Agent
  identificable, pausa 0,8 s entre grupos y reintenta con espera creciente (5, 15, 30, 60, 90,
  120 s). No aumentes la concurrencia.
- **Si Overpass está saturado** (HTTP 504/429 frecuentes), espera unos minutos y vuelve a ejecutar
  `R/01_fetch_osm.R`: reanuda desde la caché. Existe un `--endpoint` para usar un espejo.
- **Si necesitas datos masivos**, el camino correcto es descargar el extracto OSM de Ecuador
  (Geofabrik) y procesarlo localmente; el proyecto no depende de ese paso.
- **Tamaño del repositorio.** `data/raw/` pesa ~60 MB (límites originales + caché de OSM). Si
  prefieres no versionarlo, añade `data/raw/` a `.gitignore` y documenta cómo regenerarlo:
  `Rscript R/01_fetch_osm.R` más las descargas de §2 de `docs/fuentes_y_licencias.md`.

---

## 5. Actualizar el corte

1. `Rscript R/01_fetch_osm.R --force` para traer OpenStreetMap fresco.
2. Vuelve a descargar los insumos de HDX y HeiGIT si publicaron versiones nuevas.
3. `Rscript run_all.R --skip-fetch`.
4. Revisa `tests/reports/verificacion_datos.txt` (debe dar 14/14 PASS).
5. Actualiza la fecha del corte en `README.md` y `docs/metodologia.md`.
6. Publica de nuevo el sitio estático (§1.1).

---

## 6. Soporte

- Reportes de errores y sugerencias: *issues* del repositorio.
- Problemas de privacidad: se tratan con prioridad (ver `docs/privacidad.md` §6).
- Duda metodológica: revisa primero `docs/metodologia.md`, en particular §7 (sensibilidad) y §6
  (limitaciones).
