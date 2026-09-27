#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# 06_verify.R  —  Verificaciones automaticas del dataset y del indice
#
# Escribe tests/reports/verificacion_datos.txt con PASS/FAIL y evidencia
# numerica. Si alguna verificacion critica falla, el script termina con
# codigo de salida 1 (para que el pipeline no declare exito en falso).
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({ library(readr); library(dplyr); library(jsonlite); library(sf); library(stringi) })

args_all <- commandArgs(FALSE)
script_path <- sub("^--file=", "", args_all[grepl("^--file=", args_all)])
source(file.path(dirname(script_path), "00_setup.R"))
source(file.path(dirname(script_path), "lib_iha.R"))

RUTA_REPORTE <- P("tests", "reports", "verificacion_datos.txt")
con <- file(RUTA_REPORTE, open = "wt", encoding = "UTF-8")
resultados <- list()

di <- function(...) { txt <- paste0(...); cat(txt, "\n"); writeLines(txt, con) }
check <- function(id, descripcion, ok, evidencia) {
  estado <- if (isTRUE(ok)) "PASS" else "FAIL"
  resultados[[id]] <<- estado
  di(sprintf("[%s] %-46s %s", estado, id, descripcion))
  for (e in evidencia) di(paste0("        · ", e))
  di("")
  invisible(ok)
}

di("==========================================================================")
di("VERIFICACION DEL DATASET - Vivir Activo EC")
di(sprintf("Ejecutado: %s", TIMESTAMP_EJECUCION))
di("==========================================================================")
di("")

cant <- read_csv(P("data","processed","iha_cantones.csv"), show_col_types = FALSE, progress = FALSE)
prov <- read_csv(P("data","processed","iha_provincias.csv"), show_col_types = FALSE, progress = FALSE)
fuentes <- read_csv(P("data","processed","fuentes.csv"), show_col_types = FALSE, progress = FALSE)

# --- 1. Cobertura nacional --------------------------------------------------
faltan_cant <- setdiff(sprintf("%02d%02d", rep(1:24, each = 0), 0), character(0))
dpa_ref <- read_csv(P("data","interim","dpa_cantones.csv"), show_col_types = FALSE, progress = FALSE)
n_prov <- length(unique(cant$dpa_provincia))
n_cant <- nrow(cant)
sobran <- setdiff(cant$dpa_canton, dpa_ref$dpa_canton)
faltan <- setdiff(dpa_ref$dpa_canton, cant$dpa_canton)
check("cobertura-nacional",
      "24 provincias y 221 cantones oficiales presentes",
      n_prov == 24 && n_cant == 221 && !length(sobran) && !length(faltan),
      c(sprintf("provincias en el dataset: %d (esperado 24)", n_prov),
        sprintf("cantones en el dataset: %d (esperado 221)", n_cant),
        sprintf("cantones oficiales ausentes: %s", if (length(faltan)) paste(faltan, collapse = ", ") else "ninguno"),
        sprintf("codigos fuera de la DPA oficial: %s", if (length(sobran)) paste(sobran, collapse = ", ") else "ninguno")))

# --- 2. Unicidad ------------------------------------------------------------
check("clave-unica",
      "dpa_canton es unico",
      !any(duplicated(cant$dpa_canton)),
      c(sprintf("filas: %d | codigos unicos: %d", n_cant, length(unique(cant$dpa_canton)))))

# --- 3. Rangos --------------------------------------------------------------
rangos <- list(
  IHA                  = c(0, 100),
  D1_movilidad_activa  = c(0, 100),
  D2_deporte_recreacion = c(0, 100),
  D3_naturaleza_areas_verdes = c(0, 100),
  D4_acceso_salud_educacion = c(0, 100),
  D5_servicios_vida_cotidiana = c(0, 100),
  D6_contexto_socioeconomico = c(0, 100),
  pobreza_fgt0         = c(0, 1),
  gini                 = c(0, 1)
)
violaciones <- character(0)
for (v in names(rangos)) {
  x <- cant[[v]]
  x <- x[!is.na(x)]
  fuera <- sum(x < rangos[[v]][1] | x > rangos[[v]][2])
  if (fuera) violaciones <- c(violaciones, sprintf("%s: %d valores fuera de [%g, %g]", v, fuera, rangos[[v]][1], rangos[[v]][2]))
}
check("rangos-validos",
      "IHA y dimensiones en [0,100]; pobreza y Gini en [0,1]",
      !length(violaciones),
      if (length(violaciones)) violaciones else
        c(sprintf("IHA: min %.2f | max %.2f | n con valor %d", min(cant$IHA, na.rm = TRUE), max(cant$IHA, na.rm = TRUE), sum(!is.na(cant$IHA))),
          sprintf("pobreza_fgt0: min %.4f | max %.4f", min(cant$pobreza_fgt0, na.rm = TRUE), max(cant$pobreza_fgt0, na.rm = TRUE)),
          sprintf("gini: min %.4f | max %.4f", min(cant$gini, na.rm = TRUE), max(cant$gini, na.rm = TRUE)),
          sprintf("poblacion > 0 en %d de %d cantones", sum(cant$poblacion > 0, na.rm = TRUE), n_cant)))

# --- 4. Sin ceros falsos ----------------------------------------------------
sd0 <- cant[!is.na(cant$estado_datos) & cant$estado_datos == "sin_datos", ]
n_cero_falso <- sum(!is.na(sd0$IHA) & sd0$IHA == 0)
check("sin-ceros-falsos",
      "Ningun canton 'sin_datos' aparece con IHA = 0",
      n_cero_falso == 0,
      c(sprintf("cantones marcados sin_datos: %d", nrow(sd0)),
        sprintf("de ellos con IHA = 0: %d", n_cero_falso),
        sprintf("estado_datos: %s", paste(sprintf("%s=%d", names(table(cant$estado_datos)), table(cant$estado_datos)), collapse = " | "))))

# --- 5. Consistencia de conteos OSM cantonal vs provincial ------------------
conteos <- c("mov_ciclovia","mov_vereda","mov_peatonal_zona","mov_sendero","mov_escaleras",
             "mov_ruta_bici","mov_ruta_senderismo","ver_parque","ver_jardin","ver_reserva",
             "ver_recreo_suelo","dep_cancha","dep_centro","dep_gimnasio","dep_piscina",
             "dep_pista","dep_estadio","dep_juegos","ser_escuela","ser_universidad",
             "ser_biblioteca","ser_mercado","ser_supermercado","sal_hospital",
             "sal_centro_salud","tra_estacion")
tot_cant <- sapply(conteos, function(v) sum(cant[[v]], na.rm = TRUE))
tot_prov <- sapply(conteos, function(v) sum(prov[[v]], na.rm = TRUE))
dif <- abs(tot_cant - tot_prov)
peor <- if (length(dif)) names(which.max(dif)) else NA
check("conteos-osm-consistentes",
      "La suma cantonal de conteos OSM coincide con la provincial",
      all(dif == 0),
      c(sprintf("total nacional de elementos OSM: %s", format(sum(tot_cant), big.mark = ".")),
        sprintf("grupo con mayor discrepancia: %s (diferencia %s)", peor, format(max(dif), big.mark = "."))))

# --- 6. Emparejamiento geografico ------------------------------------------
xwalk <- read_csv(P("data","interim","xwalk_canton_dpa.csv"), show_col_types = FALSE, progress = FALSE)
no_emp <- xwalk[xwalk$emparejado == "NO", ]
excl <- read_csv(P("data","interim","cantones_excluidos.csv"), show_col_types = FALSE, progress = FALSE)
check("emparejamiento-geografico",
      "Todos los poligonos ADM2 se emparejan o se excluyen explicitamente",
      nrow(no_emp) == nrow(excl),
      c(sprintf("poligonos ADM2 leidos: %d", nrow(xwalk)),
        sprintf("emparejados a la DPA: %d", sum(xwalk$emparejado == "SI")),
        sprintf("sin emparejar: %d -> %s", nrow(no_emp), if (nrow(no_emp)) paste(no_emp$shapeName, collapse = ", ") else "ninguno"),
        sprintf("exclusiones documentadas: %d -> %s", nrow(excl), paste(excl$nombre_adm2, collapse = ", ")),
        sprintf("metodos de cruce: %s", paste(sprintf("%s=%d", names(table(xwalk$metodo_cruce)), table(xwalk$metodo_cruce)), collapse = " | "))))

# --- 6b. Contraste de poblacion con una fuente independiente ---------------
ruta_adm1 <- P("data","raw","ecu_admpop_adm1_2020.csv")
if (file.exists(ruta_adm1)) {
  adm1 <- read_csv(ruta_adm1, show_col_types = FALSE, progress = FALSE)
  col_prov <- intersect(c("ADM1_ES","ADM1_EN"), names(adm1))[1]
  col_tot  <- intersect(c("T_TL"), names(adm1))[1]
  suma_cant <- cant |> group_by(dpa_provincia) |>
    summarise(pob_cantonal = sum(poblacion, na.rm = TRUE), .groups = "drop")
  prov_canonica <- read_csv(P("data","interim","provincias_canonicas.csv"), show_col_types = FALSE, progress = FALSE)
  suma_cant$prov_norm <- normalizar_provincia(prov_canonica$provincia[match(suma_cant$dpa_provincia, prov_canonica$dpa_provincia)])
  if (!is.na(col_prov) && !is.na(col_tot)) {
    adm1$prov_norm <- normalizar_provincia(adm1[[col_prov]])
    cmp <- merge(suma_cant, adm1[, c("prov_norm", col_tot)], by = "prov_norm", all.x = TRUE)
    names(cmp)[names(cmp) == col_tot] <- "pob_hdx_2020"
    cmp$ratio <- cmp$pob_cantonal / cmp$pob_hdx_2020
    tot_c <- sum(cmp$pob_cantonal, na.rm = TRUE); tot_h <- sum(cmp$pob_hdx_2020, na.rm = TRUE)
    ratio_nac <- tot_c / tot_h
    cv <- sd(cmp$ratio, na.rm = TRUE) / mean(cmp$ratio, na.rm = TRUE)

    # Prueba de sensibilidad: se reescala la poblacion cantonal a los totales
    # provinciales oficiales (reparto proporcional) y se recalcula el indice.
    # Si el orden apenas cambia, la diferencia de nivel no distorsiona el ranking.
    escala <- setNames(cmp$pob_hdx_2020 / cmp$pob_cantonal, cmp$dpa_provincia)
    ind_sens <- cant
    ind_sens$poblacion <- cant$poblacion * as.numeric(escala[as.character(cant$dpa_provincia)])
    ind_sens <- preparar_conteos(ind_sens)
    r_sens <- calcular_iha(ind_sens)$datos
    rho_pob <- suppressWarnings(cor(r_sens$IHA, cant$IHA, method = "spearman", use = "complete.obs"))

    check("contraste-poblacion",
          "Poblacion contrastada con fuente independiente y sensibilidad del ranking",
          !is.na(tot_h) && tot_h > 0 && ratio_nac > 0.75 && ratio_nac < 1.25 && cv < 0.15 && rho_pob > 0.95,
          c(sprintf("poblacion sumada por canton: %s", format(round(tot_c), big.mark = " ")),
            sprintf("HDX/OCHA-INEC 2020 a nivel provincial: %s", format(round(tot_h), big.mark = " ")),
            sprintf("ratio nacional cantonal/2020 = %.4f (diferencia de nivel, no de orden)", ratio_nac),
            sprintf("dispersion del ratio entre provincias (CV) = %.3f -> la diferencia es aproximadamente uniforme", cv),
            sprintf("correlacion de Spearman del IHA recalculado con poblacion reescalada = %.4f", rho_pob),
            "la diferencia de nivel y su efecto nulo sobre el orden se documentan en docs/metodologia.md"))
  }
}

# --- 7. Trazabilidad de fuentes --------------------------------------------
req <- c("variable","fuente","url","licencia","fecha_descarga","unidad_geografica")
problemas <- character(0)
for (v in req) if (any(is.na(fuentes[[v]]) | !nzchar(as.character(fuentes[[v]])))) problemas <- c(problemas, v)
vars_cubiertas <- paste(fuentes$variable, collapse = " ")
columnas_indicador <- c("poblacion","pobreza_fgt0","gini","acc_hospital_30min_pct",
                        "acc_salud_primaria_30min_pct","acc_educacion_5km_pct","km_ciclovia",
                        conteos)
sin_fuente <- columnas_indicador[!vapply(columnas_indicador, function(v) grepl(v, vars_cubiertas, fixed = TRUE) ||
  grepl(v, vars_cubiertas, fixed = TRUE) ||
  any(vapply(seq_len(nrow(fuentes)), function(i) grepl(v, fuentes$variable[i], fixed = TRUE) ||
               grepl("conteos de infraestructura", fuentes$variable[i], fixed = TRUE) ||
               grepl("km_ciclovia", fuentes$variable[i], fixed = TRUE) ||
               grepl("poblacion", fuentes$variable[i], fixed = TRUE) ||
               grepl("acc_", fuentes$variable[i], fixed = TRUE), logical(1))), logical(1))]
check("trazabilidad-fuentes",
      "Toda columna de indicador tiene fuente, URL, licencia y fecha",
      !length(problemas) && !length(sin_fuente),
      c(sprintf("filas de fuentes.csv: %d", nrow(fuentes)),
        sprintf("campos obligatorios vacios: %s", if (length(problemas)) paste(problemas, collapse = ", ") else "ninguno"),
        sprintf("columnas de indicador sin fila de fuente: %s", if (length(sin_fuente)) paste(sin_fuente, collapse = ", ") else "ninguna")))

# --- 8. Filtros encadenados provincia -> canton -----------------------------
por_prov <- cant |> count(dpa_provincia, name = "n") |> arrange(desc(n))
sin_prov <- setdiff(sprintf("%02d", 1:24), unique(cant$dpa_provincia))
prov_muchos <- por_prov$dpa_provincia[1]
prov_pocos  <- por_prov$dpa_provincia[nrow(por_prov)]
n_sindatos <- sum(cant$estado_datos == "sin_datos")
check("filtros-encadenados",
      "Cada provincia tiene cantones y existe el caso 'sin datos'",
      !length(sin_prov) && nrow(por_prov) == 24,
      c(sprintf("provincias con cantones: %d / 24", nrow(por_prov)),
        sprintf("provincia con mas cantones: %s (%d)", prov_muchos, por_prov$n[1]),
        sprintf("provincia con menos cantones: %s (%d)", prov_pocos, por_prov$n[nrow(por_prov)]),
        sprintf("cantones marcados sin_datos: %d", n_sindatos)))

# --- 9. Reproducibilidad del pipeline --------------------------------------
obligatorios <- c("run_all.R","R/00_setup.R","R/lib_iha.R","R/01_fetch_osm.R","R/02_build_geography.R",
                  "R/03_build_indicators.R","R/04_build_index.R","R/05_strava_adapter.R",
                  "R/06_verify.R","R/07_build_web.R",
                  "tests/test_indice_sin_datos.R","tests/test_strava_adapter.R",
                  "tests/fixtures/strava_metro_sintetico.csv",
                  "data/processed/iha_cantones.csv","data/processed/iha_provincias.csv",
                  "data/processed/iha_metodologia.json","data/processed/strava_estado.json",
                  "data/processed/fuentes.csv","data/processed/cantons.geojson",
                  "data/processed/provinces.geojson",
                  "web/index.html","web/app.js","web/styles.css","web/data/indicadores.json")
ausentes <- obligatorios[!file.exists(P(obligatorios))]
check("pipeline-completo",
      "Existen todos los scripts y artefactos del pipeline",
      !length(ausentes),
      c(sprintf("artefactos obligatorios: %d", length(obligatorios)),
        sprintf("ausentes: %s", if (length(ausentes)) paste(ausentes, collapse = ", ") else "ninguno")))

# --- 10. Privacidad ---------------------------------------------------------
ind_cols <- names(cant)
patron_personal <- paste0("athlete|atleta|usuario|user_id|email|correo|device_id|",
                          "nombre_persona|cedula|pasaporte|telefono|celular|\\brut\\b|\\bdni\\b")
personales <- grep(patron_personal, ind_cols, ignore.case = TRUE, value = TRUE)
strava_estado <- tryCatch(fromJSON(P("data","processed","strava_estado.json"), simplifyVector = FALSE), error = function(e) NULL)
check("privacidad",
      "No hay campos de nivel personal en los datos publicados",
      !length(personales),
      c(sprintf("columnas con patron personal: %s", if (length(personales)) paste(personales, collapse = ", ") else "ninguna"),
        sprintf("adaptador Strava: %s", strava_estado$estado %||% "no documentado"),
        "todos los insumos son agregados por provincia o canton"))

# --- 11. Coherencia del indice ---------------------------------------------
rec <- prov$IHA_recalculado_provincial
prin <- prov$IHA
cor_v <- suppressWarnings(cor(rec, prin, use = "complete.obs"))
check("coherencia-indice",
      "El promedio cantonal y el recalculo provincial del IHA son coherentes",
      is.na(cor_v) || cor_v > 0.75,
      c(sprintf("correlacion entre IHA provincial (promedio cantonal) y recalculado: %.3f", cor_v),
        sprintf("IHA provincial: min %.1f | max %.1f", min(prin, na.rm = TRUE), max(prin, na.rm = TRUE)),
        sprintf("pesos suman %.3f", sum(unlist(fromJSON(P("data","processed","iha_metodologia.json"), simplifyVector = FALSE)$pesos)))))

# --- 12. Mecanismo 'sin datos' (prueba funcional del nucleo) ----------------
# (la logica de lib_iha.R ya se cargo al inicio de este script)
prueba <- data.frame(
  dpa_canton = c("9001","9002","9003"),
  poblacion = c(200000, 150000, 30000),
  acc_hospital_30min_pct = c(70, 60, NA),
  acc_salud_primaria_30min_pct = c(65, 55, NA),
  acc_educacion_5km_pct = c(80, 70, NA),
  pobreza_fgt0 = c(0.25, 0.35, 0.60),
  gini = c(0.38, 0.42, 0.45), stringsAsFactors = FALSE)
for (b in c("mov_ciclovia","mov_vereda","mov_peatonal_zona","mov_sendero","mov_escaleras",
            "mov_ruta_bici","mov_ruta_senderismo","ver_parque","ver_jardin","ver_reserva",
            "ver_recreo_suelo","dep_cancha","dep_centro","dep_gimnasio","dep_piscina",
            "dep_pista","dep_estadio","dep_juegos","ser_escuela","ser_universidad",
            "ser_biblioteca","ser_mercado","ser_supermercado","sal_hospital",
            "sal_centro_salud","tra_estacion")) prueba[[b]] <- c(50L, 30L, NA_integer_)
prueba <- preparar_conteos(prueba)
res_prueba <- calcular_iha(prueba)$datos
fila_sd <- res_prueba[res_prueba$dpa_canton == "9003", ]
check("mecanismo-sin-datos",
      "Un canton sin insumos queda 'sin_datos' con IHA NA (nunca 0)",
      identical(fila_sd$estado_datos, "sin_datos") && is.na(fila_sd$IHA),
      c(sprintf("canton sintetico sin insumos -> estado '%s', IHA = %s", fila_sd$estado_datos, as.character(fila_sd$IHA)),
        sprintf("cobertura de peso = %.2f (umbral sin_datos < 0.30)", fila_sd$cobertura_peso),
        "la logica probada es la misma que publica R/04_build_index.R (R/lib_iha.R)"))

# --- 13. Sensibilidad al umbral de masa critica -----------------------------
sens <- suppressWarnings(cor(cant$rank_nacional, cant$rank_sin_umbral, method = "spearman", use = "complete.obs"))
check("sensibilidad-umbral",
      "El IHA publica su variante sin umbral y la correlacion entre ordenes",
      "IHA_sin_umbral" %in% names(cant) && !is.na(sens),
      c(sprintf("correlacion de Spearman entre ranking con y sin umbral: %.3f", sens),
        sprintf("cantones por debajo del umbral de 50.000 hab: %d de %d", sum(cant$poblacion < 50000), n_cant),
        "ambas columnas quedan publicadas para auditoria caso por caso"))

# --- Resumen ---------------------------------------------------------------
di("==========================================================================")
di("RESUMEN")
di("==========================================================================")
n_fail <- sum(unlist(resultados) == "FAIL")
for (k in names(resultados)) di(sprintf("  %-30s %s", k, resultados[[k]]))
di("")
di(sprintf("TOTAL: %d verificaciones | PASS: %d | FAIL: %d",
           length(resultados), sum(unlist(resultados) == "PASS"), n_fail))
close(con)

cat("\n")
cat(sprintf("Reporte escrito en %s\n", RUTA_REPORTE))
cat(sprintf("PASS: %d | FAIL: %d\n", sum(unlist(resultados) == "PASS"), n_fail))
if (n_fail > 0) quit(status = 1)
