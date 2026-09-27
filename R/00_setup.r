# ---------------------------------------------------------------------------
# 00_setup.R  —  Proyecto "Vivir Activo EC"
# Rutas, paquetes y utilidades compartidas por todos los scripts.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(jsonlite)
  library(sf)
  library(stringi)
  library(tidyr)
  library(tibble)
  library(httr2)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || all(is.na(a))) b else a

find_root <- function() {
  r <- Sys.getenv("VAEC_ROOT", "")
  if (nzchar(r) && dir.exists(file.path(r, "R"))) return(normalizePath(r))
  a <- commandArgs(FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f) == 1L && nzchar(f)) {
    d <- dirname(normalizePath(f, mustWork = FALSE))
    for (i in 1:6) {
      if (dir.exists(file.path(d, "R")) && dir.exists(file.path(d, "data"))) return(normalizePath(d))
      nd <- dirname(d); if (identical(nd, d)) break; d <- nd
    }
  }
  wd <- getwd()
  if (dir.exists(file.path(wd, "R")) && dir.exists(file.path(wd, "data"))) return(normalizePath(wd))
  stop("No se pudo localizar la raiz del proyecto (define VAEC_ROOT o ejecuta desde la raiz).")
}

ROOT     <- find_root()
P        <- function(...) file.path(ROOT, ...)
DIR_RAW  <- P("data", "raw")
DIR_OSM  <- P("data", "raw", "osm")
DIR_INT  <- P("data", "interim")
DIR_PROC <- P("data", "processed")
DIR_REP  <- P("tests", "reports")

for (d in c(DIR_RAW, DIR_OSM, DIR_INT, DIR_PROC, DIR_REP)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

# Fecha de referencia de este corte de datos (se registra en fuentes.csv).
FECHA_CORTE <- as.character(Sys.Date())
TIMESTAMP_EJECUCION <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

# --- Normalizacion de nombres geograficos --------------------------------
# Se usa para emparejar toponimos entre geoBoundaries (ADM2) y la tabla DPA.
normalizar_nombre <- function(x) {
  x <- as.character(x)
  x <- stringi::stri_trans_general(x, "Latin-ASCII")
  x <- toupper(x)
  x <- gsub("^CANTON[ ]+", "", x)
  x <- gsub("[^A-Z0-9 ]", " ", x)
  x <- gsub("[ ]+", " ", x)
  trimws(x)
}

# Para provincias (la tabla DPA usa MAYUSCULAS y SHOUTY_CASE sin tildes)
normalizar_provincia <- function(x) {
  x <- stringi::stri_trans_general(as.character(x), "Latin-ASCII")
  x <- toupper(x)
  x <- gsub("[^A-Z0-9 ]", " ", x)
  x <- gsub("[ ]+", " ", x)
  trimws(x)
}

# --- Escribir JSON UTF-8 sin BOM -----------------------------------------
escribir_json <- function(x, path, pretty = TRUE) {
  txt <- jsonlite::toJSON(x, auto_unbox = TRUE, pretty = pretty, null = "null")
  writeLines(txt, path, useBytes = TRUE)
  invisible(path)
}

message(sprintf("[setup] raiz del proyecto: %s", ROOT))
