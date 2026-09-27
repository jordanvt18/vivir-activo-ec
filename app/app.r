# ---------------------------------------------------------------------------
# app.R  —  Vivir Activo EC: explorador del Indice de Habitabilidad Activa
# Aplicacion Shiny con mapa dinamico y filtros encadenados provincia -> canton.
#
# Ejecutar:  Rscript -e "shiny::runApp('app')"   (o desde RStudio: Run App)
# Despliegue: ver docs/despliegue.md (shinyapps.io o Shiny Server).
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(shiny); library(leaflet); library(sf); library(dplyr); library(readr)
  library(DT); library(htmltools); library(scales)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || all(is.na(a))) b else a

# --- Localizacion de la raiz del proyecto ---------------------------------
raiz_proyecto <- function() {
  r <- Sys.getenv("VAEC_ROOT", "")
  if (nzchar(r) && dir.exists(file.path(r, "data", "processed"))) return(normalizePath(r))
  d <- normalizePath(getwd())
  for (i in 1:5) {
    if (dir.exists(file.path(d, "data", "processed"))) return(d)
    nd <- dirname(d); if (identical(nd, d)) break; d <- nd
  }
  stop("No se encontro la raiz del proyecto (data/processed). Define VAEC_ROOT.")
}
ROOT <- raiz_proyecto()

cant_geo <- st_read(file.path(ROOT, "data", "processed", "cantons.geojson"), quiet = TRUE)
prov_geo <- st_read(file.path(ROOT, "data", "processed", "provinces.geojson"), quiet = TRUE)
datos <- read_csv(file.path(ROOT, "data", "processed", "iha_cantones.csv"),
                  show_col_types = FALSE, progress = FALSE)

# --- Paleta "cartografia calida de datos" (preset 02 Stamen Design) --------
PAL_CALIDA  <- c("#f8f4ec", "#ecdfc6", "#dcbf95", "#c99a63", "#a9723f", "#7d4a2a", "#46281a")
COL_ACENTO  <- "#1e3a5f"   # azul profundo
COL_SALVIA  <- "#7d8f69"   # verde salvia
COL_SINDATO <- "#b9b3a8"   # gris calido para "sin datos"

INDICADORES <- list(
  "Indice de Habitabilidad Activa (IHA)" = "IHA",
  "Movilidad activa"                     = "D1_movilidad_activa",
  "Deporte y recreacion"                 = "D2_deporte_recreacion",
  "Naturaleza y areas verdes"            = "D3_naturaleza_areas_verdes",
  "Acceso a salud y educacion"           = "D4_acceso_salud_educacion",
  "Servicios y vida cotidiana"           = "D5_servicios_vida_cotidiana",
  "Contexto socioeconomico"              = "D6_contexto_socioeconomico",
  "Personas (habitantes)"                = "poblacion",
  "Densidad (hab/km2)"                   = "densidad_hab_km2",
  "Pobreza por ingresos (FGT0)"          = "pobreza_fgt0",
  "Kilometros de ciclovia"               = "km_ciclovia"
)

EXPLICACION <- list(
  IHA = "Resume, en una sola nota de 0 a 100, cuanta oportunidad tiene el canton para una vida cotidiana activa: moverse caminando o en bici, hacer deporte, estar cerca de espacios verdes y de servicios, y vivir en un entorno con menos pobreza. Es un promedio ponderado de las seis dimensiones y esta pensado para comparar cantones entre si, no como una nota absoluta.",
  D1_movilidad_activa = "Mide cuanta infraestructura para moverse sin auto tiene el canton por habitante: tramos de ciclovia, red peatonal (veredas, calles peatonales, escaleras) y senderos o rutas de senderismo y bicicleta. Mas alto = mas facil moverse a pie o en bici.",
  D2_deporte_recreacion = "Cantidad de espacios deportivos y recreativos por habitante: canchas, centros deportivos, gimnasios, piscinas, pistas, estadios y juegos infantiles. Mas alto = mas oferta para hacer ejercicio.",
  D3_naturaleza_areas_verdes = "Parques, jardines, reservas naturales y areas de recreo por habitante. Mas alto = mas contacto cotidiano con verde.",
  D4_acceso_salud_educacion = "Porcentaje de la poblacion del canton que puede llegar en auto a un hospital, a atencion primaria y a una escuela en 30 minutos o menos. Mas alto = servicios esenciales mas cerca.",
  D5_servicios_vida_cotidiana = "Escuelas, universidades, bibliotecas, mercados, supermercados y estaciones de transporte por habitante. Mas alto = mas servicios a mano para la vida diaria.",
  D6_contexto_socioeconomico = "Combina el nivel de pobreza por ingresos y la desigualdad del canton (Gini). Mas alto = mejor situacion socioeconomica relativa.",
  poblacion = "Poblacion estimada del canton. Se usa para calcular las tasas por 100.000 habitantes.",
  densidad_hab_km2 = "Habitantes por kilometro cuadrado. Los valores muy altos suelen indicar cantones urbanos y pequenos en superficie.",
  pobreza_fgt0 = "Incidencia de pobreza por ingresos (FGT0): proporcion de la poblacion bajo la linea de pobreza. Mas bajo = mejor. Se muestra en tanto por uno.",
  km_ciclovia = "Longitud total de tramos de ciclovia mapeados en OpenStreetMap dentro del canton."
)

NOTA_SIN_DATOS <- "Este canton no tiene informacion suficiente para calcular el indice y aparece como 'sin datos'. No se rellena con cero: un cero significaria 'mala oportunidad medida', y aqui lo que ocurre es que falta medicion."

# --- Preparacion -----------------------------------------------------------
datos$provincia <- as.character(datos$provincia)
datos$canton    <- as.character(datos$canton)
provincias_lista <- sort(unique(datos$provincia))

etiqueta_canton <- function(p) {
  d <- datos[datos$provincia == p, c("dpa_canton","canton","IHA")]
  d <- d[order(-d$IHA), ]
  vals <- setNames(as.character(d$dpa_canton),
                   ifelse(is.na(d$IHA), paste0(d$canton, " (sin datos)"),
                          sprintf("%s  (IHA %.0f)", d$canton, d$IHA)))
  c("Todos los cantones de la provincia" = "", vals)
}

fmt_num <- function(x, indicador) {
  if (is.na(x)) return("sin datos")
  if (indicador %in% c("poblacion")) return(format(round(x), big.mark = ".", decimal.mark = ","))
  if (indicador %in% c("IHA","D1_movilidad_activa","D2_deporte_recreacion","D3_naturaleza_areas_verdes",
                       "D4_acceso_salud_educacion","D5_servicios_vida_cotidiana","D6_contexto_socioeconomico"))
    return(sprintf("%.1f / 100", x))
  if (indicador == "pobreza_fgt0") return(sprintf("%.1f %%", 100 * x))
  if (indicador == "densidad_hab_km2") return(sprintf("%.0f hab/km2", x))
  if (indicador == "km_ciclovia") return(sprintf("%.1f km", x))
  format(x, big.mark = ".", decimal.mark = ",")
}

# --- Interfaz --------------------------------------------------------------
ui <- fluidPage(
  tags$head(tags$style(HTML(sprintf("
    body { background:#f8f4ec; color:#2b241d; font-family:'Segoe UI',system-ui,sans-serif; }
    .titulo { padding:14px 0 6px 0; border-bottom:3px solid %s; margin-bottom:14px; }
    .titulo h1 { font-size:26px; margin:0; color:%s; letter-spacing:-.3px; }
    .titulo p { margin:4px 0 0 0; color:#6b6153; font-size:13.5px; }
    .panel-lateral { background:#fffdf9; border:1px solid #e6dcc8; border-radius:6px;
                     padding:12px 14px; box-shadow:0 1px 3px rgba(70,40,26,.07); margin-bottom:12px; }
    .panel-lateral h4 { font-size:13px; text-transform:uppercase; letter-spacing:.06em;
                        color:#7d4a2a; margin:0 0 8px 0; }
    .ficha { background:#fffdf9; border-left:4px solid %s; border-radius:4px;
             padding:10px 12px; margin-bottom:10px; }
    .ficha .valor { font-size:30px; font-weight:600; color:%s; line-height:1.1; }
    .ficha .rotulo { font-size:12px; color:#6b6153; text-transform:uppercase; letter-spacing:.05em; }
    .explica { font-size:13px; line-height:1.5; color:#4a4238; }
    .aviso { background:#fdf6e3; border-left:4px solid #c99a63; padding:8px 10px;
             font-size:12.5px; color:#5a4a33; border-radius:3px; }
    .tabla-mini td, .tabla-mini th { font-size:12.5px; padding:4px 6px; }
    .leaflet-container { background:#eef1ea; }
  ", COL_ACENTO, COL_SALVIA, COL_ACENTO)))),
  div(class = "titulo",
      h1("Vivir Activo EC"),
      p("Indice de Habitabilidad Activa por canton. Datos abiertos: INEC/OCHA, OpenStreetMap, HeiGIT.",
        " ", tags$b("Sin datos personales:"), " todo el analisis es agregado por canton.")),
  sidebarLayout(
    sidebarPanel(width = 3,
      div(class = "panel-lateral",
        h4("1. Elige donde mirar"),
        selectInput("provincia", "Provincia", choices = c("Todo el Ecuador" = "", provincias_lista)),
        selectInput("canton_filtro", "Canton", choices = c("Todos los cantones de la provincia" = "")),
        selectInput("indicador", "2. Que quieres ver en el mapa", choices = INDICADORES, selected = "IHA")
      ),
      div(class = "panel-lateral",
        h4("Que significa"),
        div(class = "explica", textOutput("explica_indicador"))
      ),
      div(class = "panel-lateral",
        h4("Como leer el mapa"),
        div(class = "explica",
          "El color va del crema (valor bajo) al marron profundo (valor alto) ",
          "y se recalcula entre los cantones visibles, asi que siempre estas comparando ",
          "unidades equivalentes. Los cantones ", tags$b("grises"),
          " no tienen datos suficientes: no son cero, simplemente no se midieron."),
        tags$hr(),
        div(class = "aviso", NOTA_SIN_DATOS)
      )
    ),
    mainPanel(width = 9,
      leafletOutput("mapa", height = 520),
      fluidRow(
        column(4, div(class = "ficha", div(class = "rotulo", textOutput("ficha_rotulo")),
                      div(class = "valor", textOutput("ficha_valor")),
                      div(class = "rotulo", textOutput("ficha_extra")))),
        column(8, h4(textOutput("titulo_detalle"), style = "font-size:15px; color:#7d4a2a;"),
                tableOutput("detalle"))
      ),
      h4("Todos los cantones visibles", style = "font-size:15px; color:#7d4a2a; margin-top:14px;"),
      DTOutput("tabla")
    )
  )
)

# --- Servidor --------------------------------------------------------------
server <- function(input, output, session) {

  observeEvent(input$provincia, {
    sel <- input$provincia
    if (!nzchar(sel)) {
      updateSelectInput(session, "canton_filtro", choices = c("Todos los cantones de la provincia" = ""), selected = "")
    } else {
      updateSelectInput(session, "canton_filtro", choices = etiqueta_canton(sel), selected = "")
    }
  }, ignoreNULL = FALSE)

  cant_visibles <- reactive({
    d <- datos
    if (nzchar(input$provincia)) d <- d[d$provincia == input$provincia, ]
    if (nzchar(input$canton_filtro)) d <- d[d$dpa_canton == input$canton_filtro, ]
    d
  })

  geo_visibles <- reactive({
    g <- cant_geo
    if (nzchar(input$provincia)) {
      g <- g[g$dpa_canton %in% cant_visibles()$dpa_canton, ]
    }
    if (nzchar(input$canton_filtro)) {
      g <- g[g$dpa_canton %in% cant_visibles()$dpa_canton, ]
    }
    g
  })

  rango_zoom <- reactive({
    g <- geo_visibles()
    if (!nrow(g)) return(NULL)
    bb <- sf::st_bbox(g)
    list(lng1 = as.numeric(bb["xmin"]), lat1 = as.numeric(bb["ymin"]),
         lng2 = as.numeric(bb["xmax"]), lat2 = as.numeric(bb["ymax"]))
  })

  output$explica_indicador <- renderText(EXPLICACION[[input$indicador]] %||% "")

  output$mapa <- renderLeaflet({
    leaflet(options = leafletOptions(minZoom = 5)) |>
      addProviderTiles("CartoDB.Positron") |>
      setView(lng = -78.5, lat = -1.3, zoom = 6)
  })

  observe({
    g <- geo_visibles()
    ind <- input$indicador
    vals <- g[[ind]]
    g$valor_mapa <- if (ind %in% names(g)) g[[ind]] else datos[[ind]][match(g$dpa_canton, datos$dpa_canton)]

    hay <- !is.na(g$valor_mapa)
    if (sum(hay) >= 2) {
      pal <- colorNumeric(PAL_CALIDA, domain = range(g$valor_mapa[hay]), na.color = COL_SINDATO)
      fill <- pal(g$valor_mapa)
    } else if (sum(hay) == 1) {
      fill <- ifelse(hay, PAL_CALIDA[7], COL_SINDATO)
      pal <- function(x) rep(PAL_CALIDA[7], length(x))
    } else {
      fill <- rep(COL_SINDATO, nrow(g))
      pal <- function(x) rep(COL_SINDATO, length(x))
    }

    etiquetas <- sprintf(
      "<div style='font-family:Segoe UI,sans-serif'><b>%s</b><br/><span style='color:#7d4a2a'>%s</span><br/>%s: <b>%s</b></div>",
      g$canton, g$provincia,
      names(INDICADORES)[match(ind, unlist(INDICADORES))],
      vapply(g$valor_mapa, fmt_num, character(1), indicador = ind))

    proxy <- leafletProxy("mapa")
    proxy |> clearShapes() |> clearControls()
    if (nrow(g)) {
      proxy |> addPolygons(
        data = g, layerId = g$dpa_canton,
        fillColor = fill, fillOpacity = 0.88,
        color = "white", weight = 0.6, opacity = 0.75,
        highlightOptions = highlightOptions(color = COL_ACENTO, weight = 2.2,
                                            bringToFront = TRUE),
        label = lapply(etiquetas, HTML))
      if (sum(hay) >= 2) proxy |> addLegend(pal = pal, values = g$valor_mapa[hay],
                                            title = names(INDICADORES)[match(ind, unlist(INDICADORES))],
                                            position = "bottomright", na.label = "sin datos")
    }
    rz <- rango_zoom()
    if (!is.null(rz) && nzchar(input$canton_filtro)) {
      proxy |> fitBounds(rz$lng1, rz$lat1, rz$lng2, rz$lat2)
    } else if (!is.null(rz) && nzchar(input$provincia)) {
      proxy |> fitBounds(rz$lng1, rz$lat1, rz$lng2, rz$lat2)
    }
  })

  # Click en el mapa -> selecciona el canton
  observeEvent(input$mapa_shape_click, {
    id <- input$mapa_shape_click$id
    if (is.null(id)) return()
    fila <- datos[datos$dpa_canton == id, ]
    if (!nrow(fila)) return()
    updateSelectInput(session, "provincia", selected = fila$provincia[1])
    updateSelectInput(session, "canton_filtro",
                      choices = etiqueta_canton(fila$provincia[1]), selected = id)
  })

  unidad_foco <- reactive({
    d <- datos
    if (nzchar(input$canton_filtro)) return(d[d$dpa_canton == input$canton_filtro, ][1, ])
    NULL
  })

  output$ficha_rotulo <- renderText({
    u <- unidad_foco()
    if (is.null(u)) "Promedio de lo visible" else paste0(u$canton, " · ", u$provincia)
  })
  output$ficha_valor <- renderText({
    ind <- input$indicador
    if (is.null(unidad_foco())) {
      v <- cant_visibles()[[ind]]
      fmt_num(mean(v, na.rm = TRUE), ind)
    } else {
      fmt_num(unidad_foco()[[ind]], ind)
    }
  })
  output$ficha_extra <- renderText({
    u <- unidad_foco()
    if (is.null(u)) return(sprintf("%d cantones en pantalla", nrow(cant_visibles())))
    if (is.na(u$IHA)) return(u$estado_datos)
    sprintf("Puesto %d de %d cantones con indice", u$rank_nacional, sum(!is.na(datos$IHA)))
  })

  output$titulo_detalle <- renderText({
    u <- unidad_foco()
    if (is.null(u)) "Resumen del territorio visible" else paste("Ficha de", u$canton)
  })

  output$detalle <- renderTable({
    u <- unidad_foco()
    if (is.null(u)) {
      d <- cant_visibles()
      data.frame(
        Concepto = c("Cantones visibles","Con indice","Sin datos suficientes","IHA promedio",
                     "IHA mas alto","IHA mas bajo","Poblacion sumada"),
        Valor = c(nrow(d), sum(!is.na(d$IHA)), sum(d$estado_datos == "sin_datos"),
                  fmt_num(mean(d$IHA, na.rm = TRUE), "IHA"),
                  if (all(is.na(d$IHA))) "sin datos" else paste(d$canton[which.max(d$IHA)], fmt_num(max(d$IHA, na.rm = TRUE), "IHA")),
                  if (all(is.na(d$IHA))) "sin datos" else paste(d$canton[which.min(d$IHA)], fmt_num(min(d$IHA, na.rm = TRUE), "IHA")),
                  format(sum(d$poblacion, na.rm = TRUE), big.mark = ".")),
        check.names = FALSE)
    } else {
      data.frame(
        Concepto = c("Indice (IHA)","Movilidad activa","Deporte y recreacion","Naturaleza y areas verdes",
                     "Acceso salud y educacion","Servicios y vida cotidiana","Contexto socioeconomico",
                     "Poblacion 2022","Densidad","Pobreza FGT0","km de ciclovia",
                     "Fortalezas","Brechas","Estado de los datos"),
        Valor = c(fmt_num(u$IHA, "IHA"),
                  fmt_num(u$D1_movilidad_activa, "D1_movilidad_activa"),
                  fmt_num(u$D2_deporte_recreacion, "D2_deporte_recreacion"),
                  fmt_num(u$D3_naturaleza_areas_verdes, "D3_naturaleza_areas_verdes"),
                  fmt_num(u$D4_acceso_salud_educacion, "D4_acceso_salud_educacion"),
                  fmt_num(u$D5_servicios_vida_cotidiana, "D5_servicios_vida_cotidiana"),
                  fmt_num(u$D6_contexto_socioeconomico, "D6_contexto_socioeconomico"),
                  fmt_num(u$poblacion, "poblacion"),
                  fmt_num(u$densidad_hab_km2, "densidad_hab_km2"),
                  fmt_num(u$pobreza_fgt0, "pobreza_fgt0"),
                  fmt_num(u$km_ciclovia, "km_ciclovia"),
                  u$principales_fortalezas, u$principales_brechas, u$estado_datos),
        check.names = FALSE)
    }
  }, striped = FALSE, hover = TRUE, bordered = FALSE, spacing = "xs")

  output$tabla <- renderDT({
    d <- cant_visibles()[, c("canton","provincia","IHA","estado_datos","D1_movilidad_activa",
                             "D2_deporte_recreacion","D3_naturaleza_areas_verdes",
                             "D4_acceso_salud_educacion","D5_servicios_vida_cotidiana",
                             "D6_contexto_socioeconomico","poblacion","rank_nacional")]
    names(d) <- c("Canton","Provincia","IHA","Estado","Movilidad","Deporte","Naturaleza",
                  "Acceso","Servicios","Contexto","Poblacion","Puesto")
    d[order(-d$IHA), ] |>
      datatable(rownames = FALSE, extensions = "Buttons",
                options = list(pageLength = 12, dom = "frtip", buttons = c("csv","excel"),
                               language = list(search = "Buscar:", zeroRecords = "Sin resultados",
                                               info = "Mostrando _START_ a _END_ de _TOTAL_ cantones",
                                               infoEmpty = "Sin registros",
                                               lengthMenu = "Mostrar _MENU_ cantones",
                                               paginate = list(previous = "Anterior", `next` = "Siguiente")))) |>
      formatRound(c("IHA","Movilidad","Deporte","Naturaleza","Acceso","Servicios","Contexto"), 1) |>
      formatCurrency("Poblacion", currency = "", interval = 3, mark = ".", dec.mark = ",")
  })
}

shinyApp(ui, server)
