# ---------------------------------------------------------------------------
# test_indice_sin_datos.R  —  Pruebas del nucleo del IHA
#
# Demuestran, con datos controlados, el comportamiento que la aplicacion
# promete en pantalla:
#   1. un canton SIN datos suficientes queda en estado "sin_datos" con IHA = NA
#      (nunca 0, porque 0 significaria "oportunidad medida y mala");
#   2. los umbrales de cobertura funcionan (ok / parcial / sin_datos);
#   3. el suavizado de credibilidad evita que un canton minusculo lidere el ranking;
#   4. el umbral de masa critica cambia el orden de los cantones pequenos.
#
# Ejecutar:  Rscript -e "testthat::test_dir('tests')"
# ---------------------------------------------------------------------------

library(testthat)

raiz <- Sys.getenv("VAEC_ROOT", "")
if (!nzchar(raiz)) {
  a <- commandArgs(FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  raiz <- if (length(f)) dirname(dirname(normalizePath(f))) else getwd()
}
source(file.path(raiz, "R", "lib_iha.R"))

# Tabla sintetica: 8 cantones "normales" + 1 sin datos + 1 parcial
tabla_base <- function() {
  set.seed(42)
  n <- 8
  d <- data.frame(
    dpa_canton = sprintf("99%02d", 1:(n + 2)),
    poblacion  = c(25000, rep(120000, n - 1), 40000, 90000),
    acc_hospital_30min_pct = c(rep(70, n), NA, 60),
    acc_salud_primaria_30min_pct = c(rep(65, n), NA, 55),
    acc_educacion_5km_pct = c(rep(80, n), NA, 70),
    pobreza_fgt0 = c(rep(0.30, n), 0.45, 0.35),
    gini = c(rep(0.40, n), 0.42, 0.41),
    stringsAsFactors = FALSE
  )
  bloques <- c(mov_ciclovia = 40, mov_vereda = 900, mov_peatonal_zona = 30, mov_sendero = 300,
               mov_escaleras = 20, mov_ruta_bici = 0, mov_ruta_senderismo = 0,
               ver_parque = 90, ver_jardin = 15, ver_reserva = 2, ver_recreo_suelo = 5,
               dep_cancha = 120, dep_centro = 12, dep_gimnasio = 6, dep_piscina = 20,
               dep_pista = 3, dep_estadio = 5, dep_juegos = 14,
               ser_escuela = 150, ser_universidad = 5, ser_biblioteca = 3,
               ser_mercado = 6, ser_supermercado = 30, sal_hospital = 12,
               sal_centro_salud = 12, tra_estacion = 4)
  for (b in names(bloques)) d[[b]] <- round(bloques[[b]] * runif(n + 2, 0.6, 1.4))
  # Canton 9 (fila n+1): TODOS los conteos OSM ausentes
  d[n + 1, names(bloques)] <- NA_integer_
  d <- preparar_conteos(d)
  d
}

test_that("un canton sin datos queda como 'sin_datos' con IHA NA y JAMAS 0", {
  res <- calcular_iha(tabla_base())
  d <- res$datos
  fila <- d[d$dpa_canton == "9909", ]
  expect_equal(fila$estado_datos, "sin_datos")
  expect_true(is.na(fila$IHA))
  expect_false(identical(fila$IHA, 0))
  expect_lt(fila$cobertura_peso, 0.30)
})

test_that("los umbrales de cobertura discriminan ok, parcial y sin_datos", {
  d <- tabla_base()
  # Canton 10: se le quitan solo los bloques de conteo OSM (quedan D4 y D6)
  d[10, c("n_movilidad_ciclista","n_red_peatonal","n_senderos",
          "n_deporte","n_naturaleza","n_servicios")] <- NA_integer_
  res <- calcular_iha(d)
  fila <- res$datos[res$datos$dpa_canton == "9910", ]
  expect_equal(fila$estado_datos, "parcial")
  expect_true(abs(fila$cobertura_peso - (0.20 + 0.10)) < 1e-9)
  expect_false(is.na(fila$IHA))
  expect_true(all(res$datos$estado_datos[1:8] == "ok"))
})

test_that("el suavizado evita que un canton minusculo lidere el ranking", {
  d <- data.frame(
    poblacion = c(6000, 500000, 300000),
    acc_hospital_30min_pct = c(50, 50, 50),
    acc_salud_primaria_30min_pct = c(50, 50, 50),
    acc_educacion_5km_pct = c(50, 50, 50),
    pobreza_fgt0 = c(0.4, 0.4, 0.4), gini = c(0.4, 0.4, 0.4),
    stringsAsFactors = FALSE)
  for (b in c("mov_ciclovia","mov_vereda","mov_peatonal_zona","mov_sendero","mov_escaleras",
              "mov_ruta_bici","mov_ruta_senderismo","ver_parque","ver_jardin","ver_reserva",
              "ver_recreo_suelo","dep_cancha","dep_centro","dep_gimnasio","dep_piscina",
              "dep_pista","dep_estadio","dep_juegos","ser_escuela","ser_universidad",
              "ser_biblioteca","ser_mercado","ser_supermercado","sal_hospital",
              "sal_centro_salud","tra_estacion")) d[[b]] <- 0L
  d$dep_cancha <- c(2L, 40L, 24L)              # el diminuto tiene 2 canchas y nada mas
  d <- preparar_conteos(d)
  res <- calcular_iha(d)
  expect_gt(res$datos$tasa_n_deporte[1], 0)    # su tasa suavizada no es 0
  expect_lt(res$datos$pct_tasa_n_deporte[1], 100)  # pero no esta en el tope
  expect_gt(res$datos$pct_tasa_n_deporte[2], res$datos$pct_tasa_n_deporte[1])
})

test_that("el umbral de masa critica cambia las tasas de los cantones pequenos", {
  d <- tabla_base()
  con_umbral <- calcular_iha(d, umbral = 50000)$datos
  sin_umbral <- calcular_iha(d, umbral = 0)$datos
  # El canton de 25.000 habitantes tiene denominador real la mitad del denominador
  # con umbral, asi que su tasa cambia mucho mas que la de un canton grande
  # (los cantones grandes solo se mueven por el cambio de la tasa nacional).
  expect_lt(con_umbral$tasa_n_deporte[1], sin_umbral$tasa_n_deporte[1])
  delta1 <- abs(con_umbral$tasa_n_deporte[1] - sin_umbral$tasa_n_deporte[1]) / sin_umbral$tasa_n_deporte[1]
  delta2 <- abs(con_umbral$tasa_n_deporte[2] - sin_umbral$tasa_n_deporte[2]) / sin_umbral$tasa_n_deporte[2]
  expect_gt(delta1, delta2)   # el canton pequeno es el que se mueve
  # La cobertura de datos no depende del umbral: solo la escala del indicador.
  expect_equal(con_umbral$cobertura_peso, sin_umbral$cobertura_peso)
})

test_that("los pesos del indice suman exactamente 1", {
  expect_equal(sum(PESOS_IHA), 1, tolerance = 1e-12)
  expect_true(all(PESOS_IHA > 0))
})
