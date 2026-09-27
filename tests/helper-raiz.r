# ---------------------------------------------------------------------------
# helper-raiz.R — Detección robusta de la raíz del proyecto para las pruebas
#
# testthat carga automáticamente los archivos helper*.R de tests/ antes de
# ejecutar las pruebas. Así, `Rscript -e "testthat::test_dir('tests')"` funciona
# desde la raíz del proyecto, desde tests/ o con VAEC_ROOT definido.
#
# Orden de búsqueda:
#   1. la variable de entorno VAEC_ROOT, si apunta a un proyecto válido
#   2. el directorio de trabajo actual y sus ancestros
#   3. el directorio del propio script (cuando se ejecuta con Rscript archivo.R)
#   4. el repositorio al que pertenece este mismo archivo
# ---------------------------------------------------------------------------

raiz_vaec <- function() {
  es_proyecto <- function(d) {
    !is.null(d) && nzchar(d) && dir.exists(d) &&
      file.exists(file.path(d, "R", "lib_iha.R")) &&
      dir.exists(file.path(d, "data", "processed"))
  }

  # 1. variable de entorno
  r <- Sys.getenv("VAEC_ROOT", "")
  if (es_proyecto(r)) return(normalizePath(r))

  # 2. directorio de trabajo y ancestros
  d <- tryCatch(normalizePath(getwd()), error = function(e) "")
  for (i in 1:8) {
    if (es_proyecto(d)) return(d)
    nd <- dirname(d); if (identical(nd, d)) break; d <- nd
  }

  # 3. ruta del script en ejecución
  a <- commandArgs(FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f) == 1L && nzchar(f)) {
    d <- tryCatch(dirname(normalizePath(f, mustWork = FALSE)), error = function(e) "")
    for (i in 1:8) {
      if (es_proyecto(d)) return(d)
      nd <- dirname(d); if (identical(nd, d)) break; d <- nd
    }
  }

  # 4. ancestros del directorio de este archivo helper
  d <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile %||% ".", mustWork = FALSE)),
                error = function(e) "")
  for (i in 1:8) {
    if (es_proyecto(d)) return(d)
    nd <- dirname(d); if (identical(nd, d)) break; d <- nd
  }

  stop("No se pudo localizar la raíz del proyecto Vivir Activo EC. ",
       "Ejecuta las pruebas desde la raíz del repositorio o define VAEC_ROOT.")
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
