#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# 03_build_indicators.R  —  Tabla de indicadores por canton
#
# Une cinco bloques de datos, todos con fuente y fecha registradas:
#   1. Division politico administrativa y geometria  (geoBoundaries / INEC-OCHA)
#   2. Poblacion, pobreza FGT0 y Gini                 (HDX, base INEC)
#   3. Accesibilidad a servicios                      (HeiGIT: OSM + WorldPop)
#   4. Infraestructura de actividad fisica y servicios (OSM via Overpass)
#   5. Kilometros de ciclovia                          (OSM via Overpass, out geom)
#
# IMPORTANTE sobre accesibilidad: en el dataset de HeiGIT, hospitales y atencion
# primaria vienen por TIEMPO (segmentos de 10 a 120 min) mientras que educacion
# viene por DISTANCIA (bandas de 5 a 50 km). No se fuerza una unidad comun: cada
# indicador se publica con la unidad que la fuente realmente mide y se etiqueta
# en consecuencia.
#
# Salida: data/interim/indicadores_canton.csv
#         data/processed/fuentes.csv
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(sf); library(dplyr); library(readr); library(tidyr); library(tibble)
})

args_all <- commandArgs(FALSE)
script_path <- sub("^--file=", "", args_all[grepl("^--file=", args_all)])
source(file.path(dirname(script_path), "00_setup.R"))

GRUPOS_OSM <- c("mov_ciclovia","mov_vereda","mov_peatonal_zona","mov_sendero","mov_escaleras",
                "mov_ruta_bici","mov_ruta_senderismo","ver_parque","ver_jardin","ver_reserva",
                "ver_recreo_suelo","dep_cancha","dep_centro","dep_gimnasio","dep_piscina",
                "dep_pista","dep_estadio","dep_juegos","ser_escuela","ser_universidad",
                "ser_biblioteca","ser_mercado","ser_supermercado","sal_hospital",
                "sal_centro_salud","tra_estacion")

ACCESO <- list(
  list(col = "acc_hospital_30min_pct", archivo = "ECU_hospitals_access_wide.csv",
       categoria = "hospitals", tipo = "TIME", rango_objetivo = 1800,
       unidad = "tiempo", etiqueta = "Población a ≤30 min en auto de un hospital",
       url = "https://data.humdata.org/dataset/ecuador-accessibility-indicators"),
  list(col = "acc_salud_primaria_30min_pct", archivo = "ECU_primary_healthcare_access_wide.csv",
       categoria = "primary_healthcare", tipo = "TIME", rango_objetivo = 1800,
       unidad = "tiempo", etiqueta = "Población a ≤30 min en auto de atención primaria",
       url = "https://data.humdata.org/dataset/ecuador-accessibility-indicators"),
  list(col = "acc_educacion_5km_pct", archivo = "ECU_education_access_wide.csv",
       categoria = "education", tipo = "DISTANCE", rango_objetivo = 5000,
       unidad = "distancia", etiqueta = "Población a ≤5 km en auto de una escuela",
       url = "https://data.humdata.org/dataset/ecuador-accessibility-indicators")
)

# --- 1. Cantones, geometria y area ----------------------------------------
cant_sf <- st_read(P("data","interim","cantons_full.gpkg"), quiet = TRUE)
message(sprintf("[ind] cantones con geometria: %d", nrow(cant_sf)))

# --- 2. Poblacion / pobreza / Gini (DPA) -----------------------------------
dpa <- read_csv(P("data","interim","dpa_cantones.csv"), show_col_types = FALSE, progress = FALSE)
message(sprintf("[ind] filas DPA canton: %d", nrow(dpa)))

# --- 3. Accesibilidad HeiGIT (join por shapeID -> dpa_canton) --------------
xwalk <- read_csv(P("data","interim","xwalk_canton_dpa.csv"), show_col_types = FALSE, progress = FALSE)
mapa_shape <- setNames(xwalk$dpa_canton, as.character(xwalk$shapeID))

leer_acceso <- function(cfg) {
  ruta <- P("data","raw", cfg$archivo)
  if (!file.exists(ruta)) { warning("Falta ", cfg$archivo); return(NULL) }
  d <- read_csv(ruta, show_col_types = FALSE, progress = FALSE)
  d <- d[toupper(as.character(d$admin_level)) == "ADM2", ]
  d <- d[as.character(d$category) == cfg$categoria, ]
  if (!nrow(d)) { warning("Sin filas ADM2/", cfg$categoria, " en ", cfg$archivo); return(NULL) }
  d <- d[as.character(d$range_type) == cfg$tipo, ]
  if (!nrow(d)) {
    warning(sprintf("%s: la categoria %s no trae filas range_type=%s", cfg$archivo, cfg$categoria, cfg$tipo))
    return(NULL)
  }
  disponibles <- sort(unique(d$range))
  elegido <- disponibles[which.min(abs(disponibles - cfg$rango_objetivo))]
  if (elegido != cfg$rango_objetivo)
    message(sprintf("[ind] %s: objetivo %s no disponible; se usa %s (opciones: %s)",
                    cfg$categoria, cfg$rango_objetivo, elegido, paste(disponibles, collapse = ", ")))
  d <- d[d$range == elegido, c("id","population_share")]
  d$dpa_canton <- mapa_shape[as.character(d$id)]
  d <- d[!is.na(d$dpa_canton) & !duplicated(d$dpa_canton), ]
  message(sprintf("[ind] %s: rango %s (%s) -> %d cantones con dato",
                  cfg$categoria, elegido, cfg$tipo, nrow(d)))
  list(vec = setNames(as.numeric(d$population_share), d$dpa_canton), rango = elegido)
}

acceso <- list()
for (cfg in ACCESO) {
  r <- leer_acceso(cfg)
  acceso[[cfg$col]] <- list(cfg = cfg, res = r)
}

# --- 5. Registro de fuentes ------------------------------------------------
fuentes <- tribble(
  ~variable, ~fuente, ~url, ~licencia, ~fecha_descarga, ~unidad_geografica, ~notas,
  "dpa_canton, canton, provincia, geometria", "geoBoundaries gbOpen ADM1/ADM2 (base INEC / OCHA ROLAC)",
    "https://www.geoboundaries.org/api/current/gbOpen/ECU/ADM2/", "CC BY 3.0 IGO",
    FECHA_CORTE, "provincia / canton",
    "223 poligonos ADM2; 221 corresponden a cantones oficiales de la DPA del INEC. El Piedrero y Las Golondrinas se excluyen por no constar como cantones (ver data/interim/cantones_excluidos.csv).",
  "poblacion, pobreza_fgt0, gini", "HDX - Poverty and population data for cantons and parishes in Ecuador (base INEC)",
    "https://data.humdata.org/dataset/poverty-and-population", "CC BY-IGO",
    FECHA_CORTE, "canton (DPA de 4 digitos)",
    "Hoja 'Prueba'; estimaciones de pobreza FGT0 y Gini por canton; 221 cantones.",
  "poblacion provincia (control)", "HDX - Ecuador Subnational Population Statistics (OCHA, base INEC)",
    "https://data.humdata.org/dataset/cod-ps-ecu", "CC BY-IGO", FECHA_CORTE, "provincia",
    "Control de coherencia de poblacion a escala provincial.",
  "conteos de infraestructura (mov_*, ver_*, dep_*, ser_*, sal_*, tra_*)", "OpenStreetMap contributors via Overpass API",
    "https://overpass-api.de/api/interpreter", "ODbL 1.0", FECHA_CORTE, "canton (join espacial)",
    "Elementos OSM cuyo centroide cae dentro del poligono cantonal. Red peatonal y ciclista, deporte, espacios verdes, servicios y transporte.",
  "km_ciclovia", "OpenStreetMap contributors via Overpass API (out geom)",
    "https://overpass-api.de/api/interpreter", "ODbL 1.0", FECHA_CORTE, "canton (interseccion geometrica)",
    "Longitud geodesica de los tramos highway=cycleway recortados al poligono cantonal (565,3 km en el corte actual)."
)

for (col in names(acceso)) {
  a <- acceso[[col]]
  if (is.null(a$res)) {
    fuentes <- add_row(fuentes, variable = col,
      fuente = "HeiGIT / Heidelberg Institute for Geoinformation Technology",
      url = a$cfg$url, licencia = "CC BY 4.0", fecha_descarga = FECHA_CORTE,
      unidad_geografica = "ADM2 (geoBoundaries)",
      notas = sprintf("SIN DATOS para la categoria %s con range_type=%s.", a$cfg$categoria, a$cfg$tipo))
  } else {
    fuentes <- add_row(fuentes, variable = col,
      fuente = "HeiGIT / Heidelberg Institute for Geoinformation Technology",
      url = a$cfg$url, licencia = "CC BY 4.0", fecha_descarga = FECHA_CORTE,
      unidad_geografica = "ADM2 (geoBoundaries)",
      notas = sprintf("%s. Isocronas de tiempo o distancia de viaje en auto sobre OpenStreetMap, poblacion WorldPop 100 m. range_type=%s, range=%s. Campo usado: population_share.",
                      a$cfg$etiqueta, a$cfg$tipo, a$res$rango))
  }
}

# --- 4. Conteos OSM por canton (join espacial) -----------------------------
ruta_pts <- P("data","interim","osm_puntos.csv.gz")
osm_mat <- matrix(NA_integer_, nrow = nrow(cant_sf), ncol = length(GRUPOS_OSM),
                  dimnames = list(cant_sf$dpa_canton, GRUPOS_OSM))
km_ciclovia <- setNames(rep(NA_real_, nrow(cant_sf)), cant_sf$dpa_canton)

if (file.exists(ruta_pts)) {
  pts <- read_csv(ruta_pts, show_col_types = FALSE, progress = FALSE)
  pts <- pts[pts$grupo %in% GRUPOS_OSM, ]
  message(sprintf("[ind] puntos OSM leidos: %d", nrow(pts)))
  pts_sf <- st_as_sf(pts, coords = c("lon","lat"), crs = 4326)
  j <- suppressMessages(st_join(pts_sf, cant_sf[, "dpa_canton"], join = st_intersects))
  j <- j[!is.na(j$dpa_canton), ]
  tab <- j |> st_drop_geometry() |> count(dpa_canton, grupo)
  osm_mat[,] <- 0L                       # si el bloque OSM existe, la ausencia es un 0 real
  for (i in seq_len(nrow(tab))) {
    if (tab$dpa_canton[i] %in% rownames(osm_mat) && tab$grupo[i] %in% colnames(osm_mat))
      osm_mat[tab$dpa_canton[i], tab$grupo[i]] <- tab$n[i]
  }
  message(sprintf("[ind] puntos OSM dentro de un canton: %d de %d (%.1f%%)",
                  sum(tab$n), nrow(pts), 100 * sum(tab$n) / nrow(pts)))
} else {
  warning("No existe data/interim/osm_puntos.csv.gz: los conteos OSM quedaran en NA")
}

ruta_cicl <- P("data","interim","osm_ciclovia.geojson")
if (file.exists(ruta_cicl)) {
  cicl <- st_read(ruta_cicl, quiet = TRUE)
  # Conteo de tramos: centroide del tramo dentro del canton (mismo criterio que
  # el resto de bloques OSM, para que las columnas sean comparables).
  pts_cicl <- st_point_on_surface(st_geometry(cicl))
  hit_cicl <- st_intersects(pts_cicl, cant_sf)
  idx <- vapply(hit_cicl, function(v) if (length(v)) v[1] else NA_integer_, integer(1))
  ok <- !is.na(idx)
  tab_cicl <- table(cant_sf$dpa_canton[idx[ok]])
  osm_mat[, "mov_ciclovia"] <- 0L
  osm_mat[names(tab_cicl), "mov_ciclovia"] <- as.integer(tab_cicl)
  message(sprintf("[ind] tramos de ciclovia contados en %d cantones de %d cantones con ciclovia",
                  length(tab_cicl), nrow(cicl)))

  # Kilometros reales: recorte geometrico del tramo al poligono cantonal.
  inter <- suppressWarnings(st_intersection(st_make_valid(cicl), cant_sf[, "dpa_canton"]))
  inter$km <- as.numeric(st_length(inter)) / 1000
  km_df <- inter |> st_drop_geometry() |> group_by(dpa_canton) |> summarise(km = sum(km, na.rm = TRUE), .groups = "drop")
  km_ciclovia[km_df$dpa_canton] <- km_df$km
  km_ciclovia[is.na(km_ciclovia)] <- 0   # ausencia medida = 0 km, no dato faltante
  message(sprintf("[ind] km de ciclovia: %.1f km en %d cantones", sum(km_df$km), nrow(km_df)))
} else {
  warning("No existe data/interim/osm_ciclovia.geojson: la movilidad ciclista quedara en NA")
  osm_mat[, "mov_ciclovia"] <- NA_integer_
}

# --- 6. Ensamblado ---------------------------------------------------------
ind <- data.frame(
  dpa_canton    = cant_sf$dpa_canton,
  dpa_provincia = cant_sf$dpa_provincia,
  provincia     = cant_sf$provincia,
  canton        = cant_sf$canton,
  area_km2      = as.numeric(st_area(cant_sf)) / 1e6,
  stringsAsFactors = FALSE
)
ind <- merge(ind, dpa[, c("dpa_canton","poblacion","pobreza_fgt0","gini")], by = "dpa_canton", all.x = TRUE)
ind$densidad_hab_km2 <- ifelse(!is.na(ind$poblacion) & ind$area_km2 > 0, ind$poblacion / ind$area_km2, NA_real_)

for (col in names(acceso)) {
  r <- acceso[[col]]$res
  ind[[col]] <- if (is.null(r)) rep(NA_real_, nrow(ind)) else as.numeric(r$vec[ind$dpa_canton])
}
ind <- cbind(ind, as.data.frame(osm_mat[ind$dpa_canton, , drop = FALSE]))
ind$km_ciclovia <- as.numeric(km_ciclovia[ind$dpa_canton])

ind <- ind[order(ind$dpa_canton), ]
write_csv(ind, P("data","interim","indicadores_canton.csv"))
write_csv(fuentes, P("data","processed","fuentes.csv"))

message(sprintf("[ind] OK -> data/interim/indicadores_canton.csv (%d filas, %d columnas)", nrow(ind), ncol(ind)))
cat("\nCobertura por bloque:\n")
for (v in c("poblacion","pobreza_fgt0","gini","acc_hospital_30min_pct",
            "acc_salud_primaria_30min_pct","acc_educacion_5km_pct","km_ciclovia")) {
  cat(sprintf("  %-32s %3d / %d con dato\n", v, sum(!is.na(ind[[v]])), nrow(ind)))
}
cat(sprintf("  %-32s %3d / %d con dato\n", "conteos OSM (mov_ciclovia)",
            sum(!is.na(ind$mov_ciclovia)), nrow(ind)))
cat(sprintf("  suma nacional de elementos OSM      %s\n", format(sum(as.matrix(ind[, GRUPOS_OSM]), na.rm = TRUE), big.mark = ".")))
