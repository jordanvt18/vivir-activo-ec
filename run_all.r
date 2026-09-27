#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# run_all.R  —  Punto de entrada unico del pipeline "Vivir Activo EC"
#
#   Rscript run_all.R                 # pipeline completo
#   Rscript run_all.R --skip-fetch    # usa la cache de OSM ya descargada
#
# Orden de ejecucion:
#   01_fetch_osm.R        descarga de OpenStreetMap (cacheada en data/raw/osm)
#   02_build_geography.R  limites, cruce DPA, simplificacion
#   03_build_indicators.R union de los cinco bloques de datos
#   04_build_index.R      calculo del IHA v1.0
#   05_strava_adapter.R   adaptador opcional de Strava Metro
#   07_build_web.R        datos del sitio web
#   06_verify.R           verificaciones (falla con codigo 1 si algo no cuadra)
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
SKIP_FETCH <- "--skip-fetch" %in% args

raiz <- Sys.getenv("VAEC_ROOT", "")
if (!nzchar(raiz) || !dir.exists(file.path(raiz, "R"))) {
  a <- commandArgs(FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  raiz <- if (length(f)) dirname(normalizePath(f)) else getwd()
}
raiz <- normalizePath(raiz)
Sys.setenv(VAEC_ROOT = raiz)
setwd(raiz)

RSCRIPT <- file.path(R.home("bin"), "Rscript")
if (!file.exists(RSCRIPT)) RSCRIPT <- "Rscript"

pasos <- c("R/01_fetch_osm.R", "R/02_build_geography.R", "R/03_build_indicators.R",
           "R/04_build_index.R", "R/05_strava_adapter.R", "R/07_build_web.R", "R/06_verify.R")
if (SKIP_FETCH) pasos <- setdiff(pasos, "R/01_fetch_osm.R")

cat("==============================================================\n")
cat(" Vivir Activo EC - pipeline completo\n")
cat(sprintf(" Raiz  : %s\n", raiz))
cat(sprintf(" R     : %s\n", R.version.string))
cat(sprintf(" Pasos : %d%s\n", length(pasos), if (SKIP_FETCH) " (sin descarga OSM)" else ""))
cat("==============================================================\n\n")

t0 <- Sys.time()
for (p in pasos) {
  cat(sprintf("\n### %s  (%s)\n", p, format(Sys.time(), "%H:%M:%S")))
  st <- system2(RSCRIPT, shQuote(p), env = c(VAEC_ROOT = raiz), stdout = "", stderr = "")
  if (st != 0) {
    cat(sprintf("\nFALLO en %s (codigo %d). Pipeline detenido.\n", p, st))
    quit(status = st)
  }
}
el <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
cat("\n==============================================================\n")
cat(sprintf(" Pipeline completado en %.1f minutos\n", el))
cat("==============================================================\n")
