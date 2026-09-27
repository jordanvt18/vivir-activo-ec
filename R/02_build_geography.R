#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# 02_build_geography.R  —  Limites administrativos, cruce DPA y auditoria
#
# Fuentes:
#   - geoBoundaries gbOpen ECU ADM1/ADM2 (base INEC / OCHA ROLAC), CC BY 3.0 IGO
#   - Hoja "Prueba" de poverty_population_cantons_parishes.xlsx (HDX): codigo
#     DPA oficial de 4 digitos por canton, poblacion, pobreza FGT0 y Gini.
#   - Tabla canonica de provincias del INEC (codigo de 2 digitos).
#
# Notas de calidad documentadas:
#   * geoBoundaries ADM2 trae 223 poligonos; la DPA oficial tiene 221 cantones.
#     2 poligonos NO son cantones oficiales (El Piedrero, Las Golondrinas) y
#     quedan excluidos explicitamente (ver data/interim/cantones_excluidos.csv).
#   * Los nombres de la DPA desambiguan con parentesis ("Bolívar (De Carchi)")
#     y usan toponimos alternativos ("Urbina Jado" = Salitre, "Pablo VI" =
#     Pablo Sexto, "General Antonio Elizalde" = Gnral. Antonio Elizalde).
#     Se resuelven con nombre_base (sin parentesis) + tabla de alias explicita.
#
# Salidas:
#   data/processed/cantons.geojson        (simplificado, para web)
#   data/processed/provinces.geojson
#   data/interim/cantons_full.gpkg        (geometria completa, para joins)
#   data/interim/xwalk_canton_dpa.csv     (auditoria del cruce)
#   data/interim/cantones_excluidos.csv
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(sf); library(dplyr); library(readr); library(readxl); library(stringi)
})

args_all <- commandArgs(FALSE)
script_path <- sub("^--file=", "", args_all[grepl("^--file=", args_all)])
source(file.path(dirname(script_path), "00_setup.R"))

args <- commandArgs(trailingOnly = TRUE)
TOL <- suppressWarnings(as.numeric(sub("^--tol=", "", grep("^--tol=", args, value = TRUE))))
if (!length(TOL) || is.na(TOL)) TOL <- 0.006

# --- Division Politico Administrativa: 24 provincias ------------------------
PROV_CANONICA <- data.frame(
  dpa_provincia = sprintf("%02d", 1:24),
  provincia = c("Azuay","Bolívar","Cañar","Carchi","Cotopaxi","Chimborazo","El Oro",
                "Esmeraldas","Guayas","Imbabura","Loja","Los Ríos","Manabí",
                "Morona Santiago","Napo","Pastaza","Pichincha","Tungurahua",
                "Zamora Chinchipe","Galápagos","Sucumbíos","Orellana",
                "Santo Domingo de los Tsáchilas","Santa Elena"),
  stringsAsFactors = FALSE)
PROV_CANONICA$provincia_norm <- normalizar_provincia(PROV_CANONICA$provincia)
write_csv(PROV_CANONICA, P("data","interim","provincias_canonicas.csv"))

# Variantes de nombre entre geoBoundaries ADM2 y la DPA (ambos normalizados)
ALIAS_ADM2 <- data.frame(
  dpa_provincia = c("09", "09", "14", "09"),
  nombre_adm2   = c("EMPALME", "GNRL ANTONIO ELIZALDE", "PABLO SEXTO", "SALITRE"),
  nombre_dpa    = c("EL EMPALME", "GENERAL ANTONIO ELIZALDE", "PABLO VI", "URBINA JADO"),
  stringsAsFactors = FALSE)

# Poligonos ADM2 que no corresponden a cantones oficiales de la DPA
EXCLUIDOS <- data.frame(
  nombre_adm2 = c("EL PIEDRERO", "LAS GOLONDRINAS"),
  motivo = c(paste("Zona en disputa Guayas/Cañar: no consta como canton en la DPA del INEC"),
             paste("Zona en disputa Imbabura/Carchi: no consta como canton en la DPA del INEC")),
  stringsAsFactors = FALSE)

nombre_base <- function(x) {
  x <- gsub("\\([^)]*\\)", " ", x)
  normalizar_nombre(x)
}

message("[geo] leyendo limites ADM1 / ADM2 ...")
adm1 <- st_make_valid(st_read(P("data","raw","geoBoundaries-ECU-ADM1.geojson"), quiet = TRUE))
adm2 <- st_make_valid(st_read(P("data","raw","geoBoundaries-ECU-ADM2.geojson"), quiet = TRUE))
message(sprintf("[geo] ADM1: %d filas | ADM2: %d filas", nrow(adm1), nrow(adm2)))

# --- 1. Codigo DPA de provincia para cada ADM1 -----------------------------
adm1$provincia_norm <- normalizar_provincia(adm1$shapeName)
adm1$dpa_provincia  <- PROV_CANONICA$dpa_provincia[match(adm1$provincia_norm, PROV_CANONICA$provincia_norm)]
sin <- is.na(adm1$dpa_provincia)
if (any(sin)) for (i in which(sin)) {
  d <- utils::adist(adm1$provincia_norm[i], PROV_CANONICA$provincia_norm)[1, ]
  if (min(d) <= 2) adm1$dpa_provincia[i] <- PROV_CANONICA$dpa_provincia[which.min(d)]
}
stopifnot(length(unique(na.omit(adm1$dpa_provincia))) == 24)

# --- 2. Provincia de cada ADM2 por MAYOR AREA DE INTERSECCION ---------------
# (el punto en superficie puede caer del lado equivocado en limites complejos,
#  p.ej. el canton Empalme quedaba asignado a Manabi en vez de Guayas)
inter <- st_intersects(adm2, adm1)
sel <- vapply(seq_len(nrow(adm2)), function(i) {
  v <- inter[[i]]
  if (!length(v)) return(NA_integer_)
  if (length(v) == 1L) return(v[1])
  a <- vapply(v, function(j) {
    g <- tryCatch(suppressWarnings(st_intersection(st_geometry(adm2)[i], st_geometry(adm1)[j])),
                  error = function(e) NULL)
    if (is.null(g)) 0 else as.numeric(sum(st_area(g)))
  }, numeric(1))
  v[which.max(a)]
}, integer(1))
na_sel <- is.na(sel)
if (any(na_sel)) sel[na_sel] <- st_nearest_feature(st_geometry(adm2)[na_sel], st_geometry(adm1))
adm2$provincia     <- adm1$shapeName[sel]
adm2$dpa_provincia <- adm1$dpa_provincia[sel]
message(sprintf("[geo] provincia asignada por area de interseccion a %d poligonos", nrow(adm2)))

# --- 3. Tabla DPA cantonal -------------------------------------------------
dpa_raw <- suppressMessages(read_excel(P("data","raw","poverty_population_cantons_parishes.xlsx"),
                                       sheet = "Prueba", skip = 2, col_names = FALSE))
names(dpa_raw) <- paste0("V", seq_len(ncol(dpa_raw)))
dpa <- data.frame(
  nivel        = as.character(dpa_raw$V4),
  cod_dpa      = as.character(dpa_raw$V6),
  nombre_txt   = as.character(dpa_raw$V7),
  provincia_txt= as.character(dpa_raw$V2),
  poblacion    = suppressWarnings(as.numeric(dpa_raw$V9)),
  pobreza_fgt0 = suppressWarnings(as.numeric(dpa_raw$V15)),
  gini         = suppressWarnings(as.numeric(dpa_raw$V24)),
  stringsAsFactors = FALSE)
dpa <- dpa[!is.na(dpa$nivel) & !is.na(dpa$cod_dpa), ]

cant_dpa <- dpa[dpa$nivel == "Canton", ]
cant_dpa$dpa_canton    <- gsub("[^0-9]", "", cant_dpa$cod_dpa)
cant_dpa <- cant_dpa[nchar(cant_dpa$dpa_canton) == 4, ]
cant_dpa$dpa_provincia <- substr(cant_dpa$dpa_canton, 1, 2)
cant_dpa$canton_base   <- nombre_base(cant_dpa$nombre_txt)
cant_dpa <- cant_dpa[!duplicated(cant_dpa$dpa_canton), ]
message(sprintf("[geo] cantones en la tabla DPA: %d", nrow(cant_dpa)))

prov_dpa <- dpa[dpa$nivel == "Provincia", ]
prov_dpa$dpa_provincia <- gsub("[^0-9]", "", prov_dpa$cod_dpa)
prov_dpa <- prov_dpa[nchar(prov_dpa$dpa_provincia) == 2, ]
message(sprintf("[geo] provincias en la tabla DPA: %d", nrow(prov_dpa)))

write_csv(cant_dpa[, c("dpa_canton","dpa_provincia","provincia_txt","nombre_txt","canton_base",
                       "poblacion","pobreza_fgt0","gini")],
          P("data","interim","dpa_cantones.csv"))
write_csv(prov_dpa[, c("dpa_provincia","provincia_txt","nombre_txt","poblacion")],
          P("data","interim","dpa_provincias.csv"))

# --- 4. Cruce ADM2 <-> DPA -------------------------------------------------
adm2$canton_norm <- normalizar_nombre(adm2$shapeName)
adm2$canton_base <- nombre_base(adm2$shapeName)
adm2$dpa_canton  <- NA_character_
adm2$metodo_cruce <- NA_character_

cant_dpa$clave_base <- paste(cant_dpa$dpa_provincia, cant_dpa$canton_base, sep = "|")
adm2$clave_base     <- paste(adm2$dpa_provincia,  adm2$canton_base,  sep = "|")

# 4a. provincia + nombre base (sin parentesis)
m <- match(adm2$clave_base, cant_dpa$clave_base)
adm2$dpa_canton[!is.na(m)] <- cant_dpa$dpa_canton[m[!is.na(m)]]
adm2$metodo_cruce[!is.na(m)] <- "provincia+nombre_base"
message(sprintf("[geo] 4a provincia+nombre_base: %d", sum(!is.na(m))))

# 4b. alias explicitos
for (i in seq_len(nrow(ALIAS_ADM2))) {
  fila <- ALIAS_ADM2[i, ]
  objetivo <- cant_dpa$dpa_canton[cant_dpa$dpa_provincia == fila$dpa_provincia &
                                     cant_dpa$canton_base == fila$nombre_dpa]
  if (!length(objetivo)) { warning("Alias sin destino: ", fila$nombre_adm2); next }
  idx <- which(is.na(adm2$dpa_canton) & adm2$dpa_provincia == fila$dpa_provincia &
                 adm2$canton_norm == fila$nombre_adm2)
  if (length(idx)) {
    adm2$dpa_canton[idx] <- objetivo[1]
    adm2$metodo_cruce[idx] <- "alias_explicito"
  }
}
message(sprintf("[geo] tras alias: %d emparejados", sum(!is.na(adm2$dpa_canton))))

# 4c. nombre de canton unico en el pais (con o sin tildes)
dup <- duplicated(cant_dpa$canton_base) | duplicated(cant_dpa$canton_base, fromLast = TRUE)
mapa_unico <- setNames(cant_dpa$dpa_canton[!dup], cant_dpa$canton_base[!dup])
sin <- is.na(adm2$dpa_canton)
hit <- mapa_unico[adm2$canton_base[sin]]
adm2$dpa_canton[sin][!is.na(hit)] <- hit[!is.na(hit)]
adm2$metodo_cruce[sin][!is.na(hit)] <- "nombre_unico_nacional"
message(sprintf("[geo] 4c nombre unico nacional: %d", sum(!is.na(hit))))

# 4d. distancia de edicion <= 2 dentro de la misma provincia
sin <- is.na(adm2$dpa_canton)
for (i in which(sin)) {
  cand <- cant_dpa[cant_dpa$dpa_provincia == adm2$dpa_provincia[i], ]
  if (!nrow(cand)) next
  d <- utils::adist(adm2$canton_base[i], cand$canton_base)[1, ]
  j <- which.min(d)
  if (d[j] <= 2) {
    adm2$dpa_canton[i]  <- cand$dpa_canton[j]
    adm2$metodo_cruce[i] <- sprintf("edicion<=2 (%s)", cand$nombre_txt[j])
  }
}
message(sprintf("[geo] ADM2 emparejados: %d / %d", sum(!is.na(adm2$dpa_canton)), nrow(adm2)))

# 4e. exclusion explicita de poligonos que no son cantones oficiales
exc_idx <- which(is.na(adm2$dpa_canton) & adm2$canton_norm %in% EXCLUIDOS$nombre_adm2)
if (length(exc_idx)) {
  adm2$metodo_cruce[exc_idx] <- "excluido_no_es_canton_oficial"
}
write_csv(EXCLUIDOS, P("data","interim","cantones_excluidos.csv"))

xwalk <- as.data.frame(adm2)[, c("shapeID","shapeName","provincia","dpa_provincia",
                                 "canton_norm","canton_base","dpa_canton","metodo_cruce")]
xwalk$emparejado <- ifelse(is.na(xwalk$dpa_canton), "NO", "SI")
write_csv(xwalk, P("data","interim","xwalk_canton_dpa.csv"))

no_emp <- xwalk[xwalk$emparejado == "NO", ]
if (nrow(no_emp)) {
  message("[geo] ADM2 SIN codigo DPA:")
  print(no_emp[, c("shapeName","provincia","dpa_provincia")], row.names = FALSE)
}
faltan_pol <- setdiff(cant_dpa$dpa_canton, na.omit(adm2$dpa_canton))
if (length(faltan_pol)) message(sprintf("[geo] ATENCION: DPA sin poligono ADM2: %s", paste(faltan_pol, collapse=", ")))

# --- 5. Salidas geograficas ------------------------------------------------
cantones <- adm2[!is.na(adm2$dpa_canton) & !duplicated(adm2$dpa_canton), ]
cantones <- cantones[, c("dpa_canton","dpa_provincia","shapeName","provincia","geometry")]
names(cantones)[names(cantones) == "shapeName"] <- "canton"
cantones <- st_transform(cantones, 4326)
cantones$area_km2 <- as.numeric(st_area(cantones)) / 1e6   # area geodesica (sf/s2)

provincias <- adm1[, c("dpa_provincia","shapeName","geometry")]
names(provincias)[names(provincias) == "shapeName"] <- "provincia"
provincias <- st_transform(provincias, 4326)
provincias$area_km2 <- as.numeric(st_area(provincias)) / 1e6

# Geometria completa para joins espaciales (OSM) y edicion
st_write(cantones,             P("data","interim","cantons_full.gpkg"),   delete_dsn = TRUE, quiet = TRUE)
st_write(provincias,           P("data","interim","provinces_full.gpkg"), delete_dsn = TRUE, quiet = TRUE)

# Geometria simplificada para la web y los mapas
# OJO: st_simplify NO reduce de forma efectiva en coordenadas lon/lat, porque
# el algoritmo siempre preserva topologia en coordenadas elipsoidales. Por eso
# se prefiere rmapshaper (algoritmo mapshaper) y, en su defecto, se proyecta a
# una Albers equal-area de Ecuador y se simplifica en metros.
ALBERS_EC <- "+proj=aea +lat_1=-5 +lat_2=1.5 +lat_0=-2 +lon_0=-79 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs"
simp <- function(x, keep = 0.05, tol_m = 500) {
  if (requireNamespace("rmapshaper", quietly = TRUE)) {
    message(sprintf("[geo] simplificando con rmapshaper::ms_simplify(keep=%.2f)", keep))
    return(st_make_valid(rmapshaper::ms_simplify(x, keep = keep, keep_shapes = TRUE)))
  }
  message(sprintf("[geo] rmapshaper no disponible: Albers + st_simplify(%.0f m)", tol_m))
  xp <- st_transform(x, ALBERS_EC)
  xp <- st_make_valid(st_simplify(xp, dTolerance = tol_m))
  st_make_valid(st_transform(xp, 4326))
}
cantones_s   <- st_set_precision(simp(cantones),   1e4)
provincias_s <- st_set_precision(simp(provincias), 1e4)
st_write(cantones_s,   P("data","processed","cantons.geojson"),   delete_dsn = TRUE, quiet = TRUE)
st_write(provincias_s, P("data","processed","provinces.geojson"), delete_dsn = TRUE, quiet = TRUE)

message(sprintf("[geo] cantons.geojson:   %.2f MB", file.info(P("data","processed","cantons.geojson"))$size/1024^2))
message(sprintf("[geo] provinces.geojson: %.2f MB", file.info(P("data","processed","provinces.geojson"))$size/1024^2))
message(sprintf("[geo] OK: %d cantones, %d provincias", nrow(cantones_s), nrow(provincias_s)))
