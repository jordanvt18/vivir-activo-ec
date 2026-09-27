#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# 01_fetch_osm.R  —  Infraestructura de actividad fisica desde OpenStreetMap
#
# Fuente : OpenStreetMap contributors (ODbL 1.0) via Overpass API.
# Unidad : se descargan ELEMENTOS y el cruce a canton se hace en
#          03_build_indicators.R con un join espacial contra los poligonos
#          de data/interim/cantons_full.gpkg.
#
# Por que por GRUPO y no por canton (medido en este entorno):
#   * filtrar por area de canton obliga a Overpass a resolver el poligono del
#     canton y repetir 26 pruebas espaciales: ~2-4 min por canton;
#   * una consulta nacional por bounding box usa el indice nativo de Overpass
#     y tarda segundos. Los elementos de las esquinas del bbox que caen en
#     Colombia/Peru se descartan solos en el join espacial posterior.
#
# Las ciclovias se piden con geometria (out geom) para poder medir kilometros
# reales; el resto con out center (solo el centroide, mucho mas liviano).
#
# Uso: Rscript R/01_fetch_osm.R [--groups a,b,c] [--endpoint URL] [--force]
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(jsonlite); library(httr2); library(readr); library(dplyr); library(sf)
})

args_all <- commandArgs(FALSE)
script_path <- sub("^--file=", "", args_all[grepl("^--file=", args_all)])
source(file.path(dirname(script_path), "00_setup.R"))

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(f, d = NULL) { i <- match(f, args); if (is.na(i)) return(d); args[[i + 1L]] }
ENDPOINT <- get_arg("--endpoint", "https://overpass-api.de/api/interpreter")
GRUPOS_ARG <- get_arg("--groups", NULL)
FORCE <- "--force" %in% args

UA <- "vivir-activo-ec/0.1 (indice de habitabilidad activa Ecuador; pipeline R; datos ODbL)"

BB_MAINLAND  <- c(-5.05, -81.10,  1.50, -75.10)   # sur, oeste, norte, este
BB_GALAPAGOS <- c(-1.50, -91.70,  0.90, -89.00)

TAG_GROUPS <- c(
  mov_ciclovia        = "highway=cycleway",
  mov_vereda          = "highway=footway",
  mov_peatonal_zona   = "highway=pedestrian",
  mov_sendero         = "highway=path",
  mov_escaleras       = "highway=steps",
  mov_ruta_bici       = "route=bicycle",
  mov_ruta_senderismo = "route=hiking",
  ver_parque          = "leisure=park",
  ver_jardin          = "leisure=garden",
  ver_reserva         = "leisure=nature_reserve",
  ver_recreo_suelo    = "landuse=recreation_ground",
  dep_cancha          = "leisure=pitch",
  dep_centro          = "leisure=sports_centre",
  dep_gimnasio        = "leisure=fitness_centre",
  dep_piscina         = "leisure=swimming_pool",
  dep_pista           = "leisure=track",
  dep_estadio         = "leisure=stadium",
  dep_juegos          = "leisure=playground",
  ser_escuela         = "amenity=school",
  ser_universidad     = "amenity=university",
  ser_biblioteca      = "amenity=library",
  ser_mercado         = "amenity=marketplace",
  ser_supermercado    = "shop=supermarket",
  sal_hospital        = "amenity=hospital",
  sal_centro_salud    = "amenity=clinic",
  tra_estacion        = "public_transport=station"
)
CON_GEOMETRIA <- c("mov_ciclovia")   # se miden kilometros, no solo conteos

osm_filter <- function(kv) { p <- strsplit(kv, "=", fixed = TRUE)[[1]]; sprintf('nwr["%s"="%s"]', p[1], p[2]) }
bb <- function(b) sprintf("(%.5f,%.5f,%.5f,%.5f)", b[1], b[2], b[3], b[4])

build_query <- function(kv, geom = FALSE) {
  out <- if (geom) "out geom;" else "out center;"
  paste0("[out:json][timeout:900];\n(\n  ", osm_filter(kv), bb(BB_MAINLAND), ";\n  ",
         osm_filter(kv), bb(BB_GALAPAGOS), ";\n);\n", out, "\n")
}

# Reintentos largos: el endpoint publico devuelve 504 cuando esta saturado.
overpass <- function(query, tries = 6L) {
  espera <- c(5, 15, 30, 60, 90, 120)
  ultimo <- "desconocido"
  for (k in seq_len(tries)) {
    ans <- tryCatch(
      request(ENDPOINT) |> req_user_agent(UA) |> req_body_form(data = query) |>
        req_timeout(900) |> req_perform(),
      error = function(e) { ultimo <<- conditionMessage(e); NULL })
    if (!is.null(ans)) {
      code <- resp_status(ans)
      if (code == 200L) return(resp_body_string(ans))
      ultimo <- sprintf("HTTP %s", code)
      if (!(code %in% c(429L, 502L, 503L, 504L))) {
        stop(sprintf("Overpass HTTP %s: %s", code, substr(resp_body_string(ans), 1, 300)))
      }
    }
    if (k < tries) {
      message(sprintf("   ... reintento %d/%d en %ds (%s)", k, tries - 1L, espera[k], ultimo))
      Sys.sleep(espera[k])
    }
  }
  stop("Overpass fallo tras ", tries, " intentos. Ultimo: ", ultimo)
}

# --- 1. Lista de cantones OSM (para el cruce por county_code) ---------------
cantons_path <- file.path(DIR_OSM, "_cantons_osm.json")
if (FORCE || !file.exists(cantons_path) || file.info(cantons_path)$size < 100) {
  q <- paste("[out:json][timeout:300];",
             'area["ISO3166-1"="EC"][admin_level=2]->.ec;',
             'rel["boundary"="administrative"]["admin_level"="6"](area.ec);',
             "out tags;", sep = "\n")
  message("[osm] descargando lista de cantones...")
  writeLines(overpass(q), cantons_path, useBytes = TRUE)
}
raw <- fromJSON(cantons_path, simplifyVector = FALSE)
cantons <- do.call(rbind, lapply(raw$elements, function(el) {
  t <- el$tags %||% list()
  cc <- t$county_code %||% NA_character_
  data.frame(osm_id = el$id,
             dpa_canton = if (!is.na(cc)) gsub("[^0-9]", "", cc) else NA_character_,
             nombre_osm = as.character(t$name %||% NA_character_),
             provincia_osm = as.character(t[["is_in:state"]] %||% NA_character_),
             stringsAsFactors = FALSE)
}))
cantons <- cantons[!is.na(cantons$dpa_canton) & nchar(cantons$dpa_canton) == 4, ]
cantons$dpa_provincia <- substr(cantons$dpa_canton, 1, 2)
cantons <- cantons[order(cantons$dpa_canton), ]
cantons <- cantons[!duplicated(cantons$dpa_canton), ]
write_csv(cantons, file.path(DIR_INT, "osm_cantons.csv"))
message(sprintf("[osm] cantones OSM con county_code: %d", nrow(cantons)))

# --- 2. Descarga por grupo -------------------------------------------------
grupos <- TAG_GROUPS
if (!is.null(GRUPOS_ARG)) {
  ped <- trimws(strsplit(GRUPOS_ARG, ",")[[1]])
  faltan <- setdiff(ped, names(TAG_GROUPS)); if (length(faltan)) stop("Grupos desconocidos: ", paste(faltan, collapse = ", "))
  grupos <- TAG_GROUPS[ped]
}

puntos <- list(); ciclovias <- NULL; estado <- list()
t0 <- Sys.time()
for (i in seq_along(grupos)) {
  g <- names(grupos)[i]
  f <- file.path(DIR_OSM, paste0("grupo_", g, ".json"))
  if (!FORCE && file.exists(f) && file.info(f)$size > 20) {
    txt <- paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n"); origen <- "cache"
  } else {
    txt <- overpass(build_query(grupos[[i]], geom = g %in% CON_GEOMETRIA))
    writeLines(txt, f, useBytes = TRUE); origen <- "red"; Sys.sleep(0.8)
  }
  js <- fromJSON(txt, simplifyVector = FALSE)
  ts <- as.character(js$osm3s$timestamp_osm_base %||% NA_character_)
  el <- js$elements

  if (g %in% CON_GEOMETRIA) {
    geoms <- list(); ids <- numeric(0)
    for (e in el) {
      if (is.null(e$geometry) || length(e$geometry) < 2) next
      lon <- vapply(e$geometry, function(p) as.numeric(p$lon), numeric(1))
      lat <- vapply(e$geometry, function(p) as.numeric(p$lat), numeric(1))
      if (length(lon) < 2 || any(is.na(lon)) || any(is.na(lat))) next
      geoms[[length(geoms) + 1L]] <- st_linestring(cbind(lon, lat))
      ids <- c(ids, as.numeric(e$id))
    }
    if (length(geoms)) {
      ciclovias <- st_sf(grupo = g, osm_id = ids, geometry = st_sfc(geoms, crs = 4326))
      ciclovias <- ciclovias[, c("grupo","osm_id","geometry")]
    }
    n <- length(geoms)
  } else {
    lat <- vapply(el, function(e) if (!is.null(e$lat)) as.numeric(e$lat) else if (!is.null(e$center$lat)) as.numeric(e$center$lat) else NA_real_, numeric(1))
    lon <- vapply(el, function(e) if (!is.null(e$lon)) as.numeric(e$lon) else if (!is.null(e$center$lon)) as.numeric(e$center$lon) else NA_real_, numeric(1))
    d <- data.frame(grupo = g,
                    osm_type = vapply(el, function(e) as.character(e$type), character(1)),
                    osm_id = vapply(el, function(e) as.numeric(e$id), numeric(1)),
                    lon = lon, lat = lat, stringsAsFactors = FALSE)
    d <- d[!is.na(d$lon) & !is.na(d$lat), ]
    puntos[[g]] <- d
    n <- nrow(d)
  }
  estado[[g]] <- list(grupo = g, n = n, origen = origen, timestamp_osm = ts, endpoint = ENDPOINT)
  message(sprintf("[osm] %2d/%d %-20s n=%-7d (%s) %.0fs",
                  i, length(grupos), g, n, origen,
                  as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}

if (length(puntos)) {
  pts <- bind_rows(puntos)
  readr::write_csv(pts, file.path(DIR_INT, "osm_puntos.csv.gz"))
  message(sprintf("[osm] puntos con coordenada: %d -> data/interim/osm_puntos.csv.gz", nrow(pts)))
}
if (!is.null(ciclovias)) {
  st_write(ciclovias, file.path(DIR_INT, "osm_ciclovia.geojson"), delete_dsn = TRUE, quiet = TRUE)
  message(sprintf("[osm] ciclovias: %d tramos -> data/interim/osm_ciclovia.geojson", nrow(ciclovias)))
}
escribir_json(estado, file.path(DIR_INT, "osm_estado.json"))

resumen <- bind_rows(lapply(estado, as.data.frame))
write_csv(resumen, file.path(DIR_INT, "osm_resumen_grupos.csv"))
print(as.data.frame(resumen)[, c("grupo","n","origen")], row.names = FALSE)
message(sprintf("[osm] OK: %d grupos procesados", nrow(resumen)))
