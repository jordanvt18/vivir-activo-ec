#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# 05_strava_adapter.R  —  Adaptador (opcional) para datos agregados de Strava
#
# POR QUE ESTE ARCHIVO EXISTE Y POR QUE NO HAY DATOS DE STRAVA
# -----------------------------------------------------------
# Los analisis que inspiran este proyecto trabajan con Strava Metro, el producto
# de datos agregados de Strava para planificacion. Metro NO es de acceso abierto:
# exige un acuerdo de uso con Strava y suele limitarse a ciudades concretas.
# Tampoco es licito reconstruirlo raspando el heatmap global de Strava.
#
# Decision de diseno: en lugar de inventar un indicador "Strava", el proyecto
#   (a) mide la INFRAESTRUCTURA que hace posible la actividad fisica (OSM),
#   (b) mide el ACCESO a servicios que la sostiene (HeiGIT),
#   (c) deja implementado y PROBADO este adaptador para que, si el proyecto
#       consigue licencia de Strava Metro, el indicador de actividad real se
#       incorpore sin reescribir nada.
#
# ESQUEMA ESPERADO (un CSV por periodo en data/external/strava_metro/):
#   dpa_canton,actividad_total,ciclistas,peatones,periodo
#   0101,152340,88990,63350,2025-Q4
#
# Salidas:
#   data/processed/strava_cantones.csv   (si hay datos licenciados)
#   data/processed/strava_estado.json    (siempre: estado explicito)
#   tests/fixtures/strava_metro_sintetico.csv (fixture marcado como SINTETICO)
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({ library(readr); library(dplyr); library(jsonlite) })

args_all <- commandArgs(FALSE)
script_path <- sub("^--file=", "", args_all[grepl("^--file=", args_all)])
source(file.path(dirname(script_path), "00_setup.R"))
source(file.path(dirname(script_path), "lib_strava.R"))

DIR_STRAVA <- P("data", "external", "strava_metro")
dir.create(DIR_STRAVA, recursive = TRUE, showWarnings = FALSE)
dir.create(P("tests", "fixtures"), recursive = TRUE, showWarnings = FALSE)

crear_fixture_sintetico <- function() {
  ruta <- P("tests", "fixtures", "strava_metro_sintetico.csv")
  if (file.exists(ruta)) return(invisible(ruta))
  set.seed(20260927)
  d <- read_csv(P("data","processed","iha_cantones.csv"), show_col_types = FALSE, progress = FALSE)
  d <- d[!is.na(d$poblacion), c("dpa_canton","poblacion")]
  d$actividad_total <- round(d$poblacion * runif(nrow(d), 0.004, 0.05))
  d$ciclistas <- round(d$actividad_total * runif(nrow(d), 0.15, 0.6))
  d$peatones  <- d$actividad_total - d$ciclistas
  d$periodo   <- "2025-Q4"
  d$marca     <- MARCA_SINTETICA
  d <- d[, COLUMNAS_REQUERIDAS]
  write_csv(d, ruta)
  writeLines(c("ARCHIVO SINTETICO: strava_metro_sintetico.csv",
               "NO SON DATOS REALES DE STRAVA. Sirven unicamente para probar el adaptador.",
               "Generado con set.seed(20260927) a partir de la poblacion cantonal.",
               "El propio CSV lleva la columna 'marca' con el valor SINTETICO_NO_SON_DATOS_REALES."),
             P("tests", "fixtures", "LEEME.txt"), useBytes = TRUE)
  message("[strava] fixture sintetico creado en ", ruta)
  invisible(ruta)
}

estado <- list(
  estado = "no_disponible_sin_licencia",
  motivo = paste("Strava Metro (datos agregados de actividad) requiere un acuerdo de uso con Strava;",
                 "no es un conjunto de datos abiertos. El heatmap global no puede usarse ni reconstruirse",
                 "porque sus terminos lo prohiben."),
  que_hace_el_proyecto = paste("El proyecto mide la infraestructura de movilidad activa (OpenStreetMap),",
                               "el acceso a servicios (HeiGIT) y el contexto socioeconomico, y mantiene este",
                               "adaptador probado para incorporar Strava Metro cuando exista licencia."),
  esquema_esperado = paste(COLUMNAS_REQUERIDAS, collapse = ", "),
  columnas_prohibidas = paste(COLUMNAS_PROHIBIDAS, collapse = ", "),
  directorio = "data/external/strava_metro/",
  datos_integrados = FALSE,
  pruebas = "tests/test_strava_adapter.R"
)

lectura <- leer_strava_dir(DIR_STRAVA)
if (!is.null(lectura$datos) && nrow(lectura$datos)) {
  ind <- read_csv(P("data","processed","iha_cantones.csv"), show_col_types = FALSE, progress = FALSE)
  agg <- agregar_strava(lectura$datos, ind)
  write_csv(agg, P("data","processed","strava_cantones.csv"))
  estado$estado <- "integrado"
  estado$motivo <- "Se encontraron CSV en data/external/strava_metro/ y se integraron como indicadores informativos."
  estado$datos_integrados <- TRUE
  estado$n_cantones_con_dato <- sum(!is.na(agg$strava_actividad_por_1000))
  estado$columnas_generadas <- names(agg)
  estado$nota <- paste("Estos indicadores NO modifican los pesos del IHA v1.0: son columnas aparte,",
                       "para que la comparacion con la metodologia publicada siga siendo valida.")
  message(sprintf("[strava] integrado en %d cantones", estado$n_cantones_con_dato))
}
if (nrow(lectura$rechazos)) {
  estado$archivos_rechazados <- lectura$rechazos
  warning(sprintf("%d archivo(s) rechazado(s) del directorio de Strava", nrow(lectura$rechazos)))
}

escribir_json(estado, P("data","processed","strava_estado.json"))
crear_fixture_sintetico()
message(sprintf("[strava] estado: %s -> data/processed/strava_estado.json", estado$estado))
