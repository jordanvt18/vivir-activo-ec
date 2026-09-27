# ---------------------------------------------------------------------------
# lib_strava.R  —  Logica reutilizable del adaptador de Strava Metro
#
# La usan 05_strava_adapter.R (calculo oficial) y tests/test_strava_adapter.R
# (pruebas), de modo que lo que se prueba es exactamente lo que se publica.
#
# REGLAS DE PRIVACIDAD (no negociables):
#   - Solo agregados por unidad geografica. Nunca registros individuales.
#   - Si un archivo trae cualquier campo que pueda identificar a una persona
#     (id de atleta, correo, coordenadas puntuales, id de dispositivo), se
#     RECHAZA completo y se registra el motivo.
# ---------------------------------------------------------------------------

COLUMNAS_REQUERIDAS <- c("dpa_canton", "actividad_total", "ciclistas", "peatones", "periodo", "marca")
MARCA_SINTETICA <- "SINTETICO_NO_SON_DATOS_REALES"

COLUMNAS_PROHIBIDAS <- c("athlete_id", "atleta_id", "usuario", "user_id", "email", "correo",
                         "lat", "lon", "latitude", "longitude", "gps", "device_id",
                         "nombre", "telefono", "cedula")

# Lee y valida todos los CSV de un directorio. Devuelve una lista con
#   $datos    data.frame combinado (o NULL si no hay nada valido)
#   $rechazos data.frame con archivo y motivo
leer_strava_dir <- function(dir) {
  rechazos <- data.frame(archivo = character(0), motivo = character(0), stringsAsFactors = FALSE)
  if (!dir.exists(dir)) return(list(datos = NULL, rechazos = rechazos, archivos = 0))
  archivos <- list.files(dir, pattern = "\\.csv$", full.names = TRUE)
  if (!length(archivos)) return(list(datos = NULL, rechazos = rechazos, archivos = 0))
  partes <- list()
  for (a in archivos) {
    d <- tryCatch(readr::read_csv(a, show_col_types = FALSE, progress = FALSE),
                  error = function(e) NULL)
    if (is.null(d) || !ncol(d)) {
      rechazos <- rbind(rechazos, data.frame(archivo = basename(a),
                                             motivo = "no se pudo leer como CSV", stringsAsFactors = FALSE))
      next
    }
    nombres <- tolower(names(d))
    viola <- intersect(nombres, COLUMNAS_PROHIBIDAS)
    if (length(viola)) {
      rechazos <- rbind(rechazos, data.frame(archivo = basename(a),
                        motivo = paste("posibles campos personales:", paste(viola, collapse = ", ")),
                        stringsAsFactors = FALSE))
      next
    }
    faltan <- setdiff(COLUMNAS_REQUERIDAS, nombres)
    if (length(faltan)) {
      rechazos <- rbind(rechazos, data.frame(archivo = basename(a),
                        motivo = paste("faltan columnas:", paste(faltan, collapse = ", ")),
                        stringsAsFactors = FALSE))
      next
    }
    names(d) <- nombres
    d$dpa_canton <- gsub("[^0-9]", "", as.character(d$dpa_canton))
    d <- d[nchar(d$dpa_canton) == 4, ]
    partes[[basename(a)]] <- d
  }
  datos <- if (length(partes)) dplyr::bind_rows(partes) else NULL
  list(datos = datos, rechazos = rechazos, archivos = length(archivos))
}

# Agrega por canton y calcula intensidad relativa y percentil.
agregar_strava <- function(strava, poblacion_df) {
  agg <- strava |>
    dplyr::group_by(dpa_canton) |>
    dplyr::summarise(strava_actividad_total = sum(actividad_total, na.rm = TRUE),
                     strava_ciclistas = sum(ciclistas, na.rm = TRUE),
                     strava_peatones = sum(peatones, na.rm = TRUE),
                     strava_periodos = paste(sort(unique(periodo)), collapse = "; "),
                     .groups = "drop")
  agg <- dplyr::left_join(agg, poblacion_df[, c("dpa_canton", "poblacion")], by = "dpa_canton")
  agg$strava_actividad_por_1000 <- with(agg, round(1000 * strava_actividad_total / poblacion, 2))
  x <- agg$strava_actividad_por_1000
  ok <- !is.na(x)
  agg$strava_percentil <- NA_real_
  if (sum(ok) >= 2) agg$strava_percentil[ok] <- round(rank(x[ok], ties.method = "average") / (sum(ok) + 1) * 100, 2)
  agg
}
