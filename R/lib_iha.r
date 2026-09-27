# ---------------------------------------------------------------------------
# lib_iha.R  —  Logica reutilizable del Indice de Habitabilidad Activa (IHA v1.0)
#
# Este archivo NO escribe nada: solo define constantes y funciones. Lo usan
# 04_build_index.R (calculo oficial) y tests/test_indice_sin_datos.R (pruebas),
# de modo que lo que se prueba es exactamente lo que se publica.
# ---------------------------------------------------------------------------

PESOS_IHA <- c(D1_movilidad_activa = 0.22,
               D2_deporte_recreacion = 0.18,
               D3_naturaleza_areas_verdes = 0.15,
               D4_acceso_salud_educacion = 0.20,
               D5_servicios_vida_cotidiana = 0.15,
               D6_contexto_socioeconomico = 0.10)

M_SUAVIZADO <- 1.0        # unidades de 100 000 habitantes del previo
UMBRAL_MASA <- 50000      # umbral de masa critica del denominador

CONTEOS_IHA <- c("n_movilidad_ciclista","n_red_peatonal","n_senderos",
                 "n_deporte","n_naturaleza","n_servicios")

SUBS_IHA <- c("tasa_n_movilidad_ciclista","tasa_n_red_peatonal","tasa_n_senderos",
              "tasa_n_deporte","tasa_n_naturaleza","tasa_n_servicios",
              "tasa_acc_hospital","tasa_acc_salud","tasa_acc_educacion",
              "tasa_no_pobreza","tasa_igualdad")

ETIQUETAS_DIM <- c(D1_movilidad_activa = "Movilidad activa",
                   D2_deporte_recreacion = "Deporte y recreación",
                   D3_naturaleza_areas_verdes = "Naturaleza y áreas verdes",
                   D4_acceso_salud_educacion = "Acceso a salud y educación",
                   D5_servicios_vida_cotidiana = "Servicios y vida cotidiana",
                   D6_contexto_socioeconomico = "Contexto socioeconómico")

# Agrupa los conteos crudos de OSM en los seis bloques del indice.
preparar_conteos <- function(d) {
  d$n_movilidad_ciclista <- d$mov_ciclovia + 0.5 * d$mov_ruta_bici
  d$n_red_peatonal       <- d$mov_vereda + d$mov_peatonal_zona + d$mov_escaleras
  d$n_senderos           <- d$mov_sendero + d$mov_ruta_senderismo
  d$n_deporte            <- d$dep_cancha + d$dep_centro + d$dep_gimnasio + d$dep_piscina +
                            d$dep_pista + d$dep_estadio + d$dep_juegos
  d$n_naturaleza         <- d$ver_parque + d$ver_jardin + d$ver_reserva + d$ver_recreo_suelo
  d$n_servicios          <- d$ser_escuela + d$ser_universidad + d$ser_biblioteca +
                            d$ser_mercado + d$ser_supermercado + d$tra_estacion
  d
}

# Suavizado por credibilidad con denominador con umbral de masa critica.
tasa_suavizada <- function(conteo, poblacion, m = M_SUAVIZADO, umbral = UMBRAL_MASA) {
  ok <- !is.na(conteo) & !is.na(poblacion) & poblacion > 0
  denom <- pmax(poblacion, umbral) / 1e5
  out <- rep(NA_real_, length(conteo))
  nacional <- NA_real_
  if (!any(ok)) return(list(tasa = out, nacional = nacional, denominador = denom))
  nacional <- sum(conteo[ok]) / sum(denom[ok])
  out[ok] <- (conteo[ok] + m * nacional) / (denom[ok] + m)
  list(tasa = out, nacional = nacional, denominador = denom)
}

# Rango percentil 0-100 entre los valores no faltantes.
percentil <- function(x) {
  ok <- !is.na(x); out <- rep(NA_real_, length(x))
  if (sum(ok) < 2) return(out)
  out[ok] <- rank(x[ok], ties.method = "average") / (sum(ok) + 1) * 100
  out
}

# Media de las columnas disponibles (ignora NA; NA si no hay ninguna).
media_disponible <- function(...) {
  m <- cbind(...)
  p <- rowSums(!is.na(m))
  out <- rowSums(m, na.rm = TRUE) / ifelse(p == 0, NA, p)
  out[p == 0] <- NA_real_
  out
}

# Calcula dimensiones, IHA, cobertura y estado. Devuelve la tabla con columnas
# nuevas mas los diagnosticos necesarios para documentar el resultado.
calcular_iha <- function(d, umbral = UMBRAL_MASA, m = M_SUAVIZADO, prefijo = "") {
  dd <- d
  tasas_nacionales <- list()
  for (v in CONTEOS_IHA) {
    r <- tasa_suavizada(dd[[v]], dd$poblacion, m = m, umbral = umbral)
    dd[[paste0(prefijo, "tasa_", v)]] <- r$tasa
    tasas_nacionales[[v]] <- r$nacional
  }
  dd[[paste0(prefijo, "tasa_acc_hospital")]]   <- dd$acc_hospital_30min_pct
  dd[[paste0(prefijo, "tasa_acc_salud")]]      <- dd$acc_salud_primaria_30min_pct
  dd[[paste0(prefijo, "tasa_acc_educacion")]]  <- dd$acc_educacion_5km_pct
  dd[[paste0(prefijo, "tasa_no_pobreza")]]     <- 1 - dd$pobreza_fgt0
  dd[[paste0(prefijo, "tasa_igualdad")]]       <- 1 - dd$gini

  subs <- paste0(prefijo, SUBS_IHA)
  for (s in subs) dd[[paste0("pct_", s)]] <- percentil(dd[[s]])

  dd$D1_movilidad_activa <- media_disponible(dd[[paste0("pct_", prefijo, "tasa_n_movilidad_ciclista")]],
                                             dd[[paste0("pct_", prefijo, "tasa_n_red_peatonal")]],
                                             dd[[paste0("pct_", prefijo, "tasa_n_senderos")]])
  dd$D2_deporte_recreacion <- dd[[paste0("pct_", prefijo, "tasa_n_deporte")]]
  dd$D3_naturaleza_areas_verdes <- dd[[paste0("pct_", prefijo, "tasa_n_naturaleza")]]
  dd$D4_acceso_salud_educacion <- media_disponible(dd[[paste0("pct_", prefijo, "tasa_acc_hospital")]],
                                                   dd[[paste0("pct_", prefijo, "tasa_acc_salud")]],
                                                   dd[[paste0("pct_", prefijo, "tasa_acc_educacion")]])
  dd$D5_servicios_vida_cotidiana <- dd[[paste0("pct_", prefijo, "tasa_n_servicios")]]
  dd$D6_contexto_socioeconomico <- media_disponible(0.7 * dd[[paste0("pct_", prefijo, "tasa_no_pobreza")]],
                                                    0.3 * dd[[paste0("pct_", prefijo, "tasa_igualdad")]])

  dim_cols <- names(PESOS_IHA)
  M <- as.matrix(dd[, dim_cols])
  w <- matrix(PESOS_IHA, nrow = nrow(M), ncol = length(PESOS_IHA), byrow = TRUE)
  w[is.na(M)] <- NA_real_
  cob <- rowSums(w, na.rm = TRUE)
  iha <- ifelse(cob > 0, rowSums(M * w, na.rm = TRUE) / cob, NA_real_)

  dd$cobertura_peso <- cob
  dd$IHA <- iha
  dd$estado_datos <- ifelse(is.na(dd$poblacion) | cob < 0.30, "sin_datos",
                     ifelse(cob < 0.60, "parcial", "ok"))
  # Invariante del proyecto: un canton sin datos NUNCA vale 0, vale NA.
  dd$IHA[dd$estado_datos == "sin_datos"] <- NA_real_

  list(datos = dd, tasas_nacionales = tasas_nacionales,
       dimensiones = dim_cols, umbral = umbral, m = m)
}
