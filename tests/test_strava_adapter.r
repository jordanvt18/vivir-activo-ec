# ---------------------------------------------------------------------------
# test_strava_adapter.R  —  Pruebas del adaptador de Strava Metro
#
#   1. el fixture SINTETICO se lee y agrega correctamente,
#   2. esta marcado como sintetico en el propio archivo,
#   3. un archivo con posibles campos personales se RECHAZA,
#   4. sin datos licenciados el estado publicado es explicito.
#
# Ejecutar:  Rscript -e "testthat::test_dir('tests')"
# ---------------------------------------------------------------------------

library(testthat)

raiz <- raiz_vaec()
Sys.setenv(VAEC_ROOT = raiz)
source(file.path(raiz, "R", "lib_strava.R"))

fixture <- file.path(raiz, "tests", "fixtures", "strava_metro_sintetico.csv")

test_that("el fixture sintetico se lee y cumple el esquema", {
  expect_true(file.exists(fixture))
  d <- readr::read_csv(fixture, show_col_types = FALSE)
  expect_true(all(COLUMNAS_REQUERIDAS %in% names(d)))
  expect_gt(nrow(d), 200)
  expect_true(all(nchar(d$dpa_canton) == 4))
  expect_true(all(d$actividad_total >= 0))
  expect_equal(d$ciclistas + d$peatones, d$actividad_total)
})

test_that("el fixture esta marcado como sintetico en el propio archivo", {
  d <- readr::read_csv(fixture, show_col_types = FALSE)
  expect_true("marca" %in% names(d))
  expect_true(all(d$marca == MARCA_SINTETICA))
  leeme <- file.path(dirname(fixture), "LEEME.txt")
  expect_true(file.exists(leeme))
  expect_true(any(grepl("NO SON DATOS REALES", readLines(leeme, warn = FALSE))))
})

test_that("el lector acepta un directorio valido y agrega por canton", {
  dir_ok <- file.path(tempdir(), "strava_ok")
  unlink(dir_ok, recursive = TRUE)
  dir.create(dir_ok, recursive = TRUE, showWarnings = FALSE)
  file.copy(fixture, file.path(dir_ok, "periodo.csv"), overwrite = TRUE)
  r <- leer_strava_dir(dir_ok)
  expect_equal(nrow(r$rechazos), 0)
  expect_true(!is.null(r$datos))
  expect_gt(nrow(r$datos), 200)

  pob <- readr::read_csv(file.path(raiz, "data", "processed", "iha_cantones.csv"),
                         show_col_types = FALSE, progress = FALSE)[, c("dpa_canton", "poblacion")]
  agg <- agregar_strava(r$datos, pob)
  expect_true(all(c("strava_actividad_total", "strava_actividad_por_1000", "strava_percentil") %in% names(agg)))
  expect_gt(nrow(agg), 150)
  expect_true(all(agg$strava_percentil <= 100, na.rm = TRUE))
})

test_that("se RECHAZA un archivo con posibles campos personales", {
  dir_malo <- file.path(tempdir(), "strava_malo")
  unlink(dir_malo, recursive = TRUE)
  dir.create(dir_malo, recursive = TRUE, showWarnings = FALSE)
  writeLines(c("dpa_canton,actividad_total,ciclistas,peatones,periodo,athlete_id",
               "0101,100,50,50,2025-Q4,atleta-12345"),
             file.path(dir_malo, "malo.csv"))
  r <- leer_strava_dir(dir_malo)
  expect_null(r$datos)
  expect_equal(nrow(r$rechazos), 1)
  expect_true(grepl("athlete_id", r$rechazos$motivo[1], fixed = TRUE))
})

test_that("se RECHAZA un archivo al que le faltan columnas del esquema", {
  dir_inc <- file.path(tempdir(), "strava_incompleto")
  unlink(dir_inc, recursive = TRUE)
  dir.create(dir_inc, recursive = TRUE, showWarnings = FALSE)
  writeLines(c("dpa_canton,actividad_total", "0101,100"), file.path(dir_inc, "corto.csv"))
  r <- leer_strava_dir(dir_inc)
  expect_null(r$datos)
  expect_equal(nrow(r$rechazos), 1)
  expect_true(grepl("faltan columnas", r$rechazos$motivo[1]))
})

test_that("el estado publicado es explicito y coherente", {
  ruta <- file.path(raiz, "data", "processed", "strava_estado.json")
  skip_if_not(file.exists(ruta))
  estado <- jsonlite::fromJSON(ruta, simplifyVector = FALSE)
  expect_true(estado$estado %in% c("no_disponible_sin_licencia", "integrado"))
  expect_true(nzchar(estado$motivo))
  if (estado$estado == "no_disponible_sin_licencia") expect_false(isTRUE(estado$datos_integrados))
})
