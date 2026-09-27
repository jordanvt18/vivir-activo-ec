#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# 07_build_web.R  —  Genera los datos del sitio web estatico (GitHub Pages)
#
# El sitio vive en web/ (index.html, styles.css, app.js). Este script solo
# escribe web/data/, es decir el paquete de datos que consume la aplicacion:
#   web/data/indicadores.json    catalogo de indicadores + valores por canton
#   web/data/cantones.geojson    limites cantonales simplificados
#   web/data/provincias.geojson  limites provinciales
#   web/data/iha_cantones.csv    tabla completa descargable
#   web/data/iha_provincias.csv  agregado provincial descargable
#   web/data/iha_metodologia.json
#   web/data/fuentes.csv
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({ library(readr); library(jsonlite); library(dplyr); library(sf) })

args_all <- commandArgs(FALSE)
script_path <- sub("^--file=", "", args_all[grepl("^--file=", args_all)])
source(file.path(dirname(script_path), "00_setup.R"))

WEB <- P("web"); DIR_WEB_DATA <- file.path(WEB, "data")
dir.create(DIR_WEB_DATA, recursive = TRUE, showWarnings = FALSE)

cant <- read_csv(P("data","processed","iha_cantones.csv"), show_col_types = FALSE, progress = FALSE)
prov <- read_csv(P("data","processed","iha_provincias.csv"), show_col_types = FALSE, progress = FALSE)
fuentes <- read_csv(P("data","processed","fuentes.csv"), show_col_types = FALSE, progress = FALSE)
meta_iha <- fromJSON(P("data","processed","iha_metodologia.json"), simplifyVector = FALSE)

EXPLICA <- list(
  IHA = "Resume en una nota de 0 a 100 cuánta oportunidad tiene el cantón para una vida cotidiana activa: moverse caminando o en bici, hacer deporte, estar cerca de espacios verdes y de servicios, y vivir en un entorno con menos pobreza. Es un promedio ponderado de seis dimensiones, pensado para comparar cantones entre sí y no como una nota absoluta.",
  D1_movilidad_activa = "Infraestructura para moverse sin auto por habitante: tramos de ciclovía, red peatonal (veredas, calles peatonales, escaleras) y senderos o rutas de senderismo y bicicleta. Más alto = más fácil moverse a pie o en bici.",
  D2_deporte_recreacion = "Espacios deportivos y recreativos por habitante: canchas, centros deportivos, gimnasios, piscinas, pistas, estadios y juegos infantiles. Más alto = más oferta para hacer ejercicio.",
  D3_naturaleza_areas_verdes = "Parques, jardines, reservas naturales y áreas de recreo por habitante. Más alto = más contacto cotidiano con verde.",
  D4_acceso_salud_educacion = "Porcentaje de la población del cantón que llega en auto en 30 minutos o menos a un hospital, a atención primaria y a una escuela. Más alto = servicios esenciales más cerca.",
  D5_servicios_vida_cotidiana = "Escuelas, universidades, bibliotecas, mercados, supermercados y estaciones de transporte por habitante. Más alto = más servicios a mano para la vida diaria.",
  D6_contexto_socioeconomico = "Combina pobreza por ingresos y desigualdad (Gini). Más alto = mejor situación socioeconómica relativa del cantón.",
  poblacion = "Población estimada del cantón. Es la base para calcular las tasas por 100.000 habitantes.",
  densidad_hab_km2 = "Habitantes por kilómetro cuadrado del cantón. Los valores altos suelen corresponder a cantones urbanos y pequeños en superficie.",
  pobreza_fgt0 = "Incidencia de pobreza por ingresos (FGT0): proporción de la población bajo la línea de pobreza. Más oscuro = más pobreza.",
  gini = "Coeficiente de Gini de la desigualdad del ingreso. Más oscuro = más desigualdad.",
  km_ciclovia = "Kilómetros de tramos de ciclovía mapeados en OpenStreetMap dentro del cantón.",
  acc_hospital_30min_pct = "Porcentaje de la población del cantón que alcanza un hospital en 30 minutos o menos viajando en auto (isócronas sobre la red vial de OpenStreetMap).",
  acc_salud_primaria_30min_pct = "Porcentaje de la población que alcanza atención primaria de salud en 30 minutos o menos en auto.",
  acc_educacion_5km_pct = "Porcentaje de la población del cantón que alcanza una escuela viajando en auto 5 km o menos. Es una medida de distancia y no de tiempo: el dataset de origen publica la educación por bandas de distancia, no por isócronas de tiempo.",
  tasa_n_movilidad_ciclista = "Tramos de ciclovía (más la mitad de las rutas ciclísticas) por 100.000 habitantes, suavizado por credibilidad. Las tasas se suavizan para que los cantones muy pequeños no dominen el ranking.",
  tasa_n_red_peatonal = "Tramos de red peatonal por 100.000 habitantes, suavizado por credibilidad.",
  tasa_n_senderos = "Senderos y rutas de senderismo por 100.000 habitantes, suavizado por credibilidad.",
  tasa_n_deporte = "Equipamientos deportivos por 100.000 habitantes, suavizado por credibilidad.",
  tasa_n_naturaleza = "Parques, jardines, reservas y áreas de recreo por 100.000 habitantes, suavizado por credibilidad.",
  tasa_n_servicios = "Servicios cotidianos (escuela, universidad, biblioteca, mercado, supermercado, estación de transporte) por 100.000 habitantes, suavizado por credibilidad.",
  cobertura_peso = "Porcentaje del peso del índice que el cantón pudo aportar con datos reales. Bajo 30 % el cantón se marca como sin datos; entre 30 % y 60 %, como datos parciales."
)

INDICADORES <- list(
  list(id = "IHA", label = "Índice de Habitabilidad Activa", grupo = "Índice general",
       formato = "indice", decimales = 1, direccion = "alto_mejor"),
  list(id = "D1_movilidad_activa", label = "Movilidad activa", grupo = "Dimensiones del índice",
       formato = "indice", decimales = 1, direccion = "alto_mejor"),
  list(id = "D2_deporte_recreacion", label = "Deporte y recreación", grupo = "Dimensiones del índice",
       formato = "indice", decimales = 1, direccion = "alto_mejor"),
  list(id = "D3_naturaleza_areas_verdes", label = "Naturaleza y áreas verdes", grupo = "Dimensiones del índice",
       formato = "indice", decimales = 1, direccion = "alto_mejor"),
  list(id = "D4_acceso_salud_educacion", label = "Acceso a salud y educación", grupo = "Dimensiones del índice",
       formato = "indice", decimales = 1, direccion = "alto_mejor"),
  list(id = "D5_servicios_vida_cotidiana", label = "Servicios y vida cotidiana", grupo = "Dimensiones del índice",
       formato = "indice", decimales = 1, direccion = "alto_mejor"),
  list(id = "D6_contexto_socioeconomico", label = "Contexto socioeconómico", grupo = "Dimensiones del índice",
       formato = "indice", decimales = 1, direccion = "alto_mejor"),
  list(id = "poblacion", label = "Población (habitantes)", grupo = "Contexto y entorno",
       formato = "entero", decimales = 0, direccion = "neutro"),
  list(id = "densidad_hab_km2", label = "Densidad (hab/km²)", grupo = "Contexto y entorno",
       formato = "hab_km2", decimales = 0, direccion = "neutro"),
  list(id = "pobreza_fgt0", label = "Pobreza por ingresos (FGT0)", grupo = "Contexto y entorno",
       formato = "porcentaje", decimales = 1, direccion = "bajo_mejor"),
  list(id = "gini", label = "Desigualdad (Gini)", grupo = "Contexto y entorno",
       formato = "numero", decimales = 2, direccion = "bajo_mejor"),
  list(id = "cobertura_peso", label = "Cobertura de datos del índice", grupo = "Contexto y entorno",
       formato = "porcentaje", decimales = 0, direccion = "alto_mejor"),
  list(id = "acc_hospital_30min_pct", label = "Población a ≤30 min de un hospital", grupo = "Acceso a servicios",
       formato = "porcentaje", decimales = 1, direccion = "alto_mejor"),
  list(id = "acc_salud_primaria_30min_pct", label = "Población a ≤30 min de atención primaria", grupo = "Acceso a servicios",
       formato = "porcentaje", decimales = 1, direccion = "alto_mejor"),
  list(id = "acc_educacion_5km_pct", label = "Población a ≤5 km de una escuela", grupo = "Acceso a servicios",
       formato = "porcentaje", decimales = 1, direccion = "alto_mejor"),
  list(id = "tasa_n_movilidad_ciclista", label = "Ciclovías y rutas por 100.000 hab", grupo = "Indicadores por habitante",
       formato = "numero", decimales = 1, direccion = "alto_mejor"),
  list(id = "tasa_n_red_peatonal", label = "Red peatonal por 100.000 hab", grupo = "Indicadores por habitante",
       formato = "numero", decimales = 1, direccion = "alto_mejor"),
  list(id = "tasa_n_senderos", label = "Senderos y rutas de senderismo por 100.000 hab", grupo = "Indicadores por habitante",
       formato = "numero", decimales = 1, direccion = "alto_mejor"),
  list(id = "tasa_n_deporte", label = "Equipamientos deportivos por 100.000 hab", grupo = "Indicadores por habitante",
       formato = "numero", decimales = 1, direccion = "alto_mejor"),
  list(id = "tasa_n_naturaleza", label = "Parques y áreas verdes por 100.000 hab", grupo = "Indicadores por habitante",
       formato = "numero", decimales = 1, direccion = "alto_mejor"),
  list(id = "tasa_n_servicios", label = "Servicios cotidianos por 100.000 hab", grupo = "Indicadores por habitante",
       formato = "numero", decimales = 1, direccion = "alto_mejor"),
  list(id = "km_ciclovia", label = "Kilómetros de ciclovía", grupo = "Indicadores por habitante",
       formato = "km", decimales = 1, direccion = "alto_mejor")
)
for (i in seq_along(INDICADORES)) {
  id <- INDICADORES[[i]]$id
  INDICADORES[[i]]$explica <- EXPLICA[[id]] %||% paste("Indicador", id, "del análisis por cantón.")
}

# --- Valores por canton ----------------------------------------------------
campos <- vapply(INDICADORES, function(x) x$id, character(1))
falta <- setdiff(campos, names(cant))
if (length(falta)) stop("Faltan columnas en iha_cantones.csv: ", paste(falta, collapse = ", "))

num_o_na <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  ifelse(is.na(x) | !is.finite(x), NA, round(x, 4))
}

cantones <- lapply(seq_len(nrow(cant)), function(i) {
  v <- as.list(setNames(lapply(campos, function(campo) num_o_na(cant[[campo]][i])), campos))
  names(v) <- campos
  list(
    dpa = cant$dpa_canton[i],
    nombre = cant$canton[i],
    prov = cant$dpa_provincia[i],
    prov_nombre = cant$provincia[i],
    estado = cant$estado_datos[i],
    rank = if (is.na(cant$rank_nacional[i])) NA else as.integer(cant$rank_nacional[i]),
    fortalezas = cant$principales_fortalezas[i],
    brechas = cant$principales_brechas[i],
    v = v
  )
})

provincias <- lapply(seq_len(nrow(prov)), function(i) list(
  dpa = prov$dpa_provincia[i], nombre = prov$provincia[i],
  IHA = round(prov$IHA[i], 2)
))

fuentes_json <- lapply(seq_len(nrow(fuentes)), function(i) list(
  variable = fuentes$variable[i], fuente = fuentes$fuente[i],
  licencia = fuentes$licencia[i], fecha = as.character(fuentes$fecha_descarga[i]),
  unidad = fuentes$unidad_geografica[i]
))

payload <- list(
  generado = TIMESTAMP_EJECUCION,
  version_iha = meta_iha$version %||% "IHA v1.0",
  fecha_corte_osm = as.character(cant$timestamp_osm_base[1] %||% NA_character_),
  indicadores = INDICADORES,
  provincias = provincias,
  cantones = cantones,
  fuentes = fuentes_json,
  repo = Sys.getenv("VAEC_REPO", "https://github.com/jordanvt18/vivir-activo-ec"),
  licencias = list(codigo = "MIT", datos = "segun fuente: ODbL 1.0 (OSM), CC BY 3.0 IGO (geoBoundaries), CC BY 4.0 (HeiGIT), CC BY-IGO (HDX/INEC)")
)

# Anadir la fecha base de OSM si esta disponible en los puntos
ruta_estado <- P("data","interim","osm_estado.json")
if (file.exists(ruta_estado)) {
  st <- fromJSON(ruta_estado, simplifyVector = FALSE)
  ts <- unlist(lapply(st, function(x) x$timestamp_osm))
  ts <- ts[!is.na(ts)]
  if (length(ts)) payload$fecha_corte_osm <- names(sort(table(ts), decreasing = TRUE))[1]
}

escribir_json(payload, file.path(DIR_WEB_DATA, "indicadores.json"), pretty = FALSE)

file.copy(P("data","processed","cantons.geojson"),   file.path(DIR_WEB_DATA, "cantones.geojson"),   overwrite = TRUE)
file.copy(P("data","processed","provinces.geojson"), file.path(DIR_WEB_DATA, "provincias.geojson"), overwrite = TRUE)
file.copy(P("data","processed","iha_cantones.csv"),  file.path(DIR_WEB_DATA, "iha_cantones.csv"),  overwrite = TRUE)
file.copy(P("data","processed","iha_provincias.csv"),file.path(DIR_WEB_DATA, "iha_provincias.csv"),overwrite = TRUE)
file.copy(P("data","processed","iha_metodologia.json"), file.path(DIR_WEB_DATA, "iha_metodologia.json"), overwrite = TRUE)
file.copy(P("data","processed","fuentes.csv"),       file.path(DIR_WEB_DATA, "fuentes.csv"),        overwrite = TRUE)
# Copia descargable del geojson de cantones con el nombre que usa la app
file.copy(P("data","processed","cantons.geojson"),   file.path(DIR_WEB_DATA, "cantones.geojson"),   overwrite = TRUE)

message(sprintf("[web] indicadores.json: %.2f MB", file.info(file.path(DIR_WEB_DATA,"indicadores.json"))$size/1024^2))
message(sprintf("[web] cantones.geojson:  %.2f MB", file.info(file.path(DIR_WEB_DATA,"cantones.geojson"))$size/1024^2))
message(sprintf("[web] OK -> %s (%d indicadores, %d cantones)", DIR_WEB_DATA, length(INDICADORES), length(cantones)))
