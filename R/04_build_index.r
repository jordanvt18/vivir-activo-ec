#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# 04_build_index.R  —  Indice de Habitabilidad Activa (IHA v1.0)
#
# El nucleo del calculo vive en R/lib_iha.R para que 04 (calculo oficial) y
# tests/test_indice_sin_datos.R (pruebas) ejecuten EXACTAMENTE la misma logica.
# Ver docs/metodologia.md para la justificacion de cada decision.
#
# Salidas:
#   data/processed/iha_cantones.csv
#   data/processed/iha_provincias.csv
#   data/processed/iha_metodologia.json
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({ library(dplyr); library(readr); library(tidyr); library(tibble); library(jsonlite) })

args_all <- commandArgs(FALSE)
script_path <- sub("^--file=", "", args_all[grepl("^--file=", args_all)])
source(file.path(dirname(script_path), "00_setup.R"))
source(file.path(dirname(script_path), "lib_iha.R"))

ind <- read_csv(P("data","interim","indicadores_canton.csv"), show_col_types = FALSE, progress = FALSE)
n <- nrow(ind)
ind <- preparar_conteos(ind)

# --- IHA principal (con umbral de masa critica) ----------------------------
res <- calcular_iha(ind, umbral = UMBRAL_MASA)
ind <- res$datos

# --- Variante de sensibilidad (sin umbral) ---------------------------------
res_su <- calcular_iha(ind, umbral = 0)
ind$IHA_sin_umbral <- res_su$datos$IHA
ind$IHA <- round(ind$IHA, 2)
ind$IHA_sin_umbral <- round(ind$IHA_sin_umbral, 2)
ind$cobertura_peso <- round(ind$cobertura_peso, 3)

con_iha <- !is.na(ind$IHA)
ind$rank_nacional <- NA_integer_
ind$rank_nacional[con_iha] <- rank(-ind$IHA[con_iha], ties.method = "min")
con_su <- !is.na(ind$IHA_sin_umbral)
ind$rank_sin_umbral <- NA_integer_
ind$rank_sin_umbral[con_su] <- rank(-ind$IHA_sin_umbral[con_su], ties.method = "min")

# --- Fortalezas y brechas ---------------------------------------------------
dim_cols <- names(PESOS_IHA)
fort <- character(n); brech <- character(n)
for (i in seq_len(n)) {
  v <- unlist(ind[i, dim_cols])
  if (all(is.na(v))) { fort[i] <- NA_character_; brech[i] <- NA_character_; next }
  o <- order(-v, na.last = NA)
  fort[i]  <- paste(ETIQUETAS_DIM[dim_cols[head(o, 2)]], collapse = "; ")
  brech[i] <- paste(ETIQUETAS_DIM[dim_cols[tail(o, 2)]], collapse = "; ")
}
ind$principales_fortalezas <- fort
ind$principales_brechas    <- brech

sens <- suppressWarnings(cor(ind$rank_nacional, ind$rank_sin_umbral,
                             method = "spearman", use = "complete.obs"))

# --- Agregacion provincial --------------------------------------------------
cant_ok <- ind[!is.na(ind$IHA), ]
prov_prom <- cant_ok |> group_by(dpa_provincia, provincia) |>
  summarise(IHA_promedio_cantonal_ponderado =
              sum(IHA * poblacion, na.rm = TRUE) / sum(poblacion[!is.na(IHA)], na.rm = TRUE),
            n_cantones_con_indice = n(), .groups = "drop")

conteos_raw <- c("mov_ciclovia","mov_vereda","mov_peatonal_zona","mov_sendero","mov_escaleras",
                 "mov_ruta_bici","mov_ruta_senderismo","ver_parque","ver_jardin","ver_reserva",
                 "ver_recreo_suelo","dep_cancha","dep_centro","dep_gimnasio","dep_piscina",
                 "dep_pista","dep_estadio","dep_juegos","ser_escuela","ser_universidad",
                 "ser_biblioteca","ser_mercado","ser_supermercado","sal_hospital",
                 "sal_centro_salud","tra_estacion")
prov_agg <- ind |> group_by(dpa_provincia, provincia) |>
  summarise(across(all_of(c("poblacion", conteos_raw, "km_ciclovia")), ~ sum(.x, na.rm = TRUE)),
            n_cantones = n(), .groups = "drop")
prov_extra <- ind |> group_by(dpa_provincia) |>
  summarise(n_movilidad_ciclista = sum(mov_ciclovia + 0.5 * mov_ruta_bici, na.rm = TRUE),
            n_red_peatonal = sum(mov_vereda + mov_peatonal_zona + mov_escaleras, na.rm = TRUE),
            n_senderos = sum(mov_sendero + mov_ruta_senderismo, na.rm = TRUE),
            n_deporte = sum(dep_cancha + dep_centro + dep_gimnasio + dep_piscina + dep_pista + dep_estadio + dep_juegos, na.rm = TRUE),
            n_naturaleza = sum(ver_parque + ver_jardin + ver_reserva + ver_recreo_suelo, na.rm = TRUE),
            n_servicios = sum(ser_escuela + ser_universidad + ser_biblioteca + ser_mercado + ser_supermercado + tra_estacion, na.rm = TRUE),
            .groups = "drop")
prov_agg <- left_join(prov_agg, prov_extra, by = "dpa_provincia")
prov_agg$acc_hospital_30min_pct       <- ind |> group_by(dpa_provincia) |> summarise(x = mean(acc_hospital_30min_pct, na.rm = TRUE)) |> pull(x)
prov_agg$acc_salud_primaria_30min_pct <- ind |> group_by(dpa_provincia) |> summarise(x = mean(acc_salud_primaria_30min_pct, na.rm = TRUE)) |> pull(x)
prov_agg$acc_educacion_5km_pct        <- ind |> group_by(dpa_provincia) |> summarise(x = mean(acc_educacion_5km_pct, na.rm = TRUE)) |> pull(x)
prov_agg$pobreza_fgt0                 <- ind |> group_by(dpa_provincia) |> summarise(x = weighted.mean(pobreza_fgt0, poblacion, na.rm = TRUE)) |> pull(x)
prov_agg$gini                         <- ind |> group_by(dpa_provincia) |> summarise(x = weighted.mean(gini, poblacion, na.rm = TRUE)) |> pull(x)
prov_agg <- preparar_conteos(prov_agg)
res_prov <- calcular_iha(prov_agg, umbral = UMBRAL_MASA)
prov_agg <- res_prov$datos
prov_agg$IHA_recalculado_provincial <- round(prov_agg$IHA, 2)

provincias <- prov_prom |> left_join(prov_agg, by = c("dpa_provincia","provincia"))
provincias$IHA_promedio_cantonal_ponderado <- round(provincias$IHA_promedio_cantonal_ponderado, 2)
provincias$IHA <- provincias$IHA_promedio_cantonal_ponderado
provincias$rank_nacional <- rank(-provincias$IHA, ties.method = "min")
provincias <- provincias |> relocate(dpa_provincia, provincia, IHA, rank_nacional)

# --- Salidas ----------------------------------------------------------------
salida_cant <- ind[, c("dpa_canton","dpa_provincia","provincia","canton",
                       "poblacion","area_km2","densidad_hab_km2","pobreza_fgt0","gini",
                       "km_ciclovia", conteos_raw,
                       "acc_hospital_30min_pct","acc_salud_primaria_30min_pct","acc_educacion_5km_pct",
                       paste0("tasa_", c(CONTEOS_IHA, "acc_hospital","acc_salud","acc_educacion","no_pobreza","igualdad")),
                       paste0("pct_", SUBS_IHA), dim_cols,
                       "cobertura_peso","IHA","IHA_sin_umbral","estado_datos",
                       "rank_nacional","rank_sin_umbral",
                       "principales_fortalezas","principales_brechas")]
write_csv(salida_cant, P("data","processed","iha_cantones.csv"))
write_csv(provincias, P("data","processed","iha_provincias.csv"))

n_sd <- sum(salida_cant$estado_datos == "sin_datos")
metodologia <- list(
  version = "IHA v1.0",
  fecha_calculo = TIMESTAMP_EJECUCION,
  unidad_analisis = "canton (221 cantones oficiales de la DPA del INEC)",
  escala = "0-100, mayor es mejor",
  pesos = as.list(PESOS_IHA),
  denominador = list(
    umbral_masa_critica_habitantes = UMBRAL_MASA,
    formula = "denominador = max(poblacion, 50000) / 100000",
    justificacion = paste("Sin umbral, un canton rural de pocos miles de habitantes con dos canchas y un parque",
                          "obtiene una tasa altisima y desplaza a ciudades reales en el ranking. Ese orden es un",
                          "artefacto aritmetico del denominador, no una diferencia de oportunidad. El umbral fija",
                          "la oferta de un canton pequeno contra una masa minima de poblacion.")
  ),
  suavizado = list(
    formula = "tasa_suav = (conteo + m * tasa_nacional) / (denominador + m)",
    m = M_SUAVIZADO,
    tasa_nacional = "sum(conteos) / sum(denominadores)",
    justificacion = "Estimador de credibilidad: evita que un canton con un solo equipamiento salte al primer puesto."
  ),
  tasas_nacionales_por_100k = res$tasas_nacionales,
  sub_indicadores = list(
    D1 = c("n_movilidad_ciclista (mov_ciclovia + 0.5*mov_ruta_bici)",
           "n_red_peatonal (mov_vereda + mov_peatonal_zona + mov_escaleras)",
           "n_senderos (mov_sendero + mov_ruta_senderismo)"),
    D2 = "n_deporte (pitch + sports_centre + fitness_centre + swimming_pool + track + stadium + playground)",
    D3 = "n_naturaleza (park + garden + nature_reserve + recreation_ground)",
    D4 = c("acc_hospital_30min_pct (poblacion a <=30 min en auto de un hospital)",
           "acc_salud_primaria_30min_pct (atencion primaria <=30 min)",
           "acc_educacion_5km_pct (escuela a <=5 km en auto)"),
    D5 = "n_servicios (school + university + library + marketplace + supermarket + station)",
    D6 = c("0.7 * tasa_no_pobreza (1 - FGT0)", "0.3 * tasa_igualdad (1 - Gini)")
  ),
  normalizacion = "rango percentil entre cantones con dato: rank(ties.method='average')/(n+1)*100",
  agregacion = "IHA = sum(peso_d * D_d) / sum(peso_d disponible); los pesos se renormalizan sobre las dimensiones disponibles",
  umbrales_estado_datos = list(ok = "cobertura_peso >= 0.60",
                               parcial = "0.30 <= cobertura_peso < 0.60",
                               sin_datos = "cobertura_peso < 0.30 o poblacion NA"),
  sin_datos_en_este_corte = n_sd,
  sensibilidad = list(
    variante = "IHA_sin_umbral: mismos datos y pesos, pero denominador = poblacion real (sin umbral de masa critica)",
    correlacion_spearman_de_rankings = round(sens, 4),
    lectura = paste("Los cambios se concentran en los cantones por debajo del umbral. Ambas columnas se publican",
                    "para poder auditar caso por caso; la variante principal es la que aplica el umbral.")
  ),
  agregacion_provincial = paste("IHA de provincia = promedio de los IHA cantonales ponderado por poblacion.",
                                "Se publica ademas IHA_recalculado_provincial, que recalcula tasas y percentiles a escala provincial.",
                                "No son identicos por construccion: el percentil depende del conjunto de unidades comparadas."),
  limitaciones = c(
    "OpenStreetMap mide infraestructura mapeada, no uso real: un canton con buena infraestructura no mapeada se subestima.",
    "No se usa el heatmap ni datos individuales de Strava: Strava Metro exige acuerdo de uso. El adaptador esta implementado y probado, pero sin datos licenciados el indicador Strava queda no disponible.",
    "La accesibilidad HeiGIT usa tiempos y distancias de viaje en auto estimados sobre OSM, no trafico real. Educacion viene por distancia, no por tiempo.",
    "Pobreza y Gini son estimaciones por canton, no conteos censales exactos.",
    "El IHA ordena oportunidades de vida activa y acceso; no mide calidad de vivienda, empleo ni seguridad.",
    "El umbral de masa critica es una decision de diseno explicita y verificable (ver 'sensibilidad')."
  ),
  fuentes = "data/processed/fuentes.csv",
  datos_personales = "Ninguno. Todos los insumos son agregados por unidad geografica."
)
escribir_json(metodologia, P("data","processed","iha_metodologia.json"))

cat("\n=== Resumen IHA ===\n")
print(table(salida_cant$estado_datos))
cat(sprintf("IHA: min=%.1f  mediana=%.1f  max=%.1f  (n=%d)\n",
            min(salida_cant$IHA, na.rm=TRUE), median(salida_cant$IHA, na.rm=TRUE),
            max(salida_cant$IHA, na.rm=TRUE), sum(!is.na(salida_cant$IHA))))
cat(sprintf("Sensibilidad (Spearman con/sin umbral): %.3f\n", sens))
cat("\nTOP 8\n")
print(as.data.frame(salida_cant |> filter(!is.na(rank_nacional)) |> arrange(rank_nacional) |> slice_head(n=8) |>
  select(rank_nacional, canton, provincia, IHA, poblacion)), row.names = FALSE)
cat("\nULTIMOS 5\n")
print(as.data.frame(salida_cant |> filter(!is.na(rank_nacional)) |> arrange(desc(rank_nacional)) |> slice_head(n=5) |>
  select(rank_nacional, canton, provincia, IHA, poblacion)), row.names = FALSE)
message("[iha] OK -> data/processed/iha_cantones.csv, iha_provincias.csv, iha_metodologia.json")
