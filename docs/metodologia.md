# Metodología — Índice de Habitabilidad Activa (IHA v1.0)

Documento auditable: cada indicador, su fuente, su fórmula, su peso y **por qué**. Al final,
la lista honesta de lo que este índice **no** puede decir.

- **Versión del índice:** IHA v1.0
- **Fecha de cálculo:** 2026-09-27
- **Unidad de análisis:** cantón (221 cantones oficiales de la División Político Administrativa del INEC)
- **Escala:** 0 a 100, donde más alto es mejor
- **Insumos:** únicamente datos agregados por unidad geográfica
- **Artefacto máquina-legible:** `data/processed/iha_metodologia.json`

---

## 1. La pregunta y su traducción a datos

La pregunta original —"¿dónde me conviene vivir si quiero una vida activa?"— no es directamente
medible. Se traduce en seis dimensiones observables con datos abiertos:

| Dimensión | Peso | Pregunta que responde |
|---|---:|---|
| **D1 · Movilidad activa** | 22 % | ¿Puedo moverme a pie o en bici sin depender del auto? |
| **D2 · Deporte y recreación** | 18 % | ¿Tengo dónde hacer ejercicio cerca? |
| **D3 · Naturaleza y áreas verdes** | 15 % | ¿Tengo verde y naturaleza en la vida cotidiana? |
| **D4 · Acceso a salud y educación** | 20 % | ¿Los servicios esenciales están a distancia razonable? |
| **D5 · Servicios y vida cotidiana** | 15 % | ¿Resuelvo el día a día sin viajes largos? |
| **D6 · Contexto socioeconómico** | 10 % | ¿El entorno tiene menos pobreza y desigualdad? |

**Por qué estos pesos.** D1 y D4 concentran el 42 % porque son las dos dimensiones con evidencia
más sólida en la literatura de actividad física: la infraestructura de movilidad activa y la
proximidad a servicios son los factores del entorno construido que mejor se asocian con caminar y
pedalear. D6 pesa solo 10 % y nunca se mezcla con las demás: es contexto, no entorno construido;
subirle el peso convertiría el índice en un ranking de renta disfrazado de ranking de
habitabilidad. Los pesos son una **decisión de diseño explícita y editable**, no un resultado
estadístico. `data/processed/iha_metodologia.json` los publica como datos, y la variante de
sensibilidad (§7) permite ver cuánto depende el orden de ellos.

---

## 2. Fuentes

Todas las fuentes son abiertas y se descargaron el **2026-09-27**. El registro completo con URL,
licencia, unidad geográfica y notas vive en `data/processed/fuentes.csv`.

| Bloque | Fuente | Licencia | Unidad | Qué aporta |
|---|---|---|---|---|
| Límites administrativos | geoBoundaries gbOpen ECU ADM1/ADM2 (base INEC / OCHA ROLAC) | CC BY 3.0 IGO | provincia y cantón | Geometría, áreas y denominador espacial |
| Población, pobreza, Gini | HDX — *Poverty and population data for cantons and parishes in Ecuador* (base INEC) | CC BY-IGO | cantón (DPA de 4 dígitos) | `poblacion`, `pobreza_fgt0`, `gini` |
| Población provincial de control | HDX — *Ecuador Subnational Population Statistics* (OCHA, base INEC) | CC BY-IGO | provincia | Contraste independiente de población |
| Accesibilidad a servicios | HeiGIT / Heidelberg Institute for Geoinformation Technology | CC BY 4.0 | ADM2 (geoBoundaries) | Isócronas de viaje en auto sobre OSM + población WorldPop 100 m |
| Infraestructura de actividad | OpenStreetMap vía Overpass API | ODbL 1.0 | cantón (join espacial) | 26 grupos de etiquetas: red peatonal y ciclista, deporte, verde, servicios, transporte |
| Kilómetros de ciclovía | OpenStreetMap vía Overpass API (`out geom`) | ODbL 1.0 | cantón (intersección geométrica) | Longitud geodésica real de los tramos |

**Fecha base de OpenStreetMap:** `2026-09-27` (se conserva `timestamp_osm_base` de cada consulta).

### 2.1 Homologación de nombres y códigos

geoBoundaries entrega **223 polígonos** ADM2; la DPA oficial tiene **221 cantones**. La
reconciliación se hizo en tres pasos, todos auditables en `data/interim/xwalk_canton_dpa.csv`:

| Método | Casos | Detalle |
|---|---:|---|
| `provincia+nombre_base` | 216 | Comparación por nombre sin paréntesis, dentro de la provincia correcta |
| `alias_explicito` | 3 | Variantes documentadas entre fuentes |
| `edicion<=2` | 2 | Distancia de edición ≤2 dentro de la misma provincia |
| `excluido_no_es_canton_oficial` | 2 | Polígonos que **no** son cantones de la DPA |

Los alias explícitos responden a que la DPA desambigua con paréntesis y usa topónimos alternativos:

| geoBoundaries | DPA oficial |
|---|---|
| `Bolivar` (Carchi) | `Bolívar (De Carchi)` |
| `Bolivar` (Manabí) | `Bolivar (De Manabí)` |
| `Nobol` | `Nobol (Piedrahita)` |
| `Salitre` | `Urbina Jado` |
| `Empalme` | `El Empalme` |
| `Gnral. Antonio Elizalde` | `General Antonio Elizalde (Bucay)` |
| `Pablo Sexto` | `Pablo VI` |

Los dos polígonos excluidos se documentan en `data/interim/cantones_excluidos.csv`:
**El Piedrero** (zona en disputa Guayas/Cañar) y **Las Golondrinas** (zona en disputa
Imbabura/Carchi). No se borran en silencio: quedan registrados con su motivo.

La provincia de cada polígono ADM2 se asigna por **mayor área de intersección** con ADM1, no por
punto representativo: el punto en superficie situaba el cantón Empalme en Manabí cuando
corresponde a Guayas.

---

## 3. Cómo se calcula cada indicador

### 3.1 Conteos de OpenStreetMap

Se descargan elementos por **grupo de etiquetas** usando el *bounding box* de Ecuador
(más un bbox propio para Galápagos) y se asignan a cada cantón con un **join espacial** del
centroide contra el polígono cantonal. Del total descargado, **89,4 %** (105.189 de 117.721
elementos) cae dentro de algún cantón; el resto son elementos de las esquinas del rectángulo que
pertenecen a Colombia o Perú, o puntos en el océano, y se descartan.

Las 26 etiquetas se agrupan en seis bloques:

| Columna | Etiquetas OSM | Total nacional |
|---|---|---:|
| `n_movilidad_ciclista` | `highway=cycleway` + 0,5 · `route=bicycle` | 1.023 |
| `n_red_peatonal` | `highway=footway` + `pedestrian` + `steps` | 46.252 |
| `n_senderos` | `highway=path` + `route=hiking` | 20.411 |
| `n_deporte` | `leisure=pitch` + `sports_centre` + `fitness_centre` + `swimming_pool` + `track` + `stadium` + `playground` | 14.274 |
| `n_naturaleza` | `leisure=park` + `garden` + `nature_reserve` + `landuse=recreation_ground` | 8.276 |
| `n_servicios` | `amenity=school` + `university` + `library` + `marketplace` + `shop=supermarket` + `public_transport=station` | 13.632 |

`km_ciclovia` se calcula aparte: los tramos `highway=cycleway` se piden **con geometría**
(`out geom`) y se recortan contra cada polígono cantonal; la longitud se mide
**geodésicamente** (`sf` con `s2`). Resultado del corte: **565,3 km en 46 cantones**.

**Criterio de ausencia:** si el bloque de OSM se descargó correctamente, la ausencia de un
elemento en un cantón es un **0 real** (no hay vereda mapeada), no un dato faltante. Los datos
faltantes solo aparecen si el bloque completo no se pudo descargar.

### 3.2 Accesibilidad (HeiGIT)

El dataset de HeiGIT publica la población alcanzable dentro de bandas de viaje. **No usa la misma
unidad para las tres categorías**, y no se fuerza una unidad común:

| Indicador | `range_type` | Rango usado | Significado |
|---|---|---|---|
| `acc_hospital_30min_pct` | `TIME` | 1800 s | % de población del cantón a ≤30 min en auto de un hospital |
| `acc_salud_primaria_30min_pct` | `TIME` | 1800 s | % de población a ≤30 min de atención primaria |
| `acc_educacion_5km_pct` | `DISTANCE` | 5000 m | % de población a ≤5 km de una escuela |

El campo usado es `population_share` (porcentaje acumulado de población dentro del rango).
La educación viene por **distancia** porque el dataset de origen la publica así: intentar
convertirla a minutos habría sido inventar un dato. Cobertura: hospital 217, atención primaria 202,
escuela 216 de 221 cantones. Los cinco cantones sin dato quedan con `NA` y bajan la cobertura de la
dimensión D4, sin rellenarse con cero.

### 3.3 Pobreza y desigualdad

`pobreza_fgt0` (incidencia de pobreza por ingresos) y `gini` provienen del dataset de pobreza por
cantón (base INEC), como estimaciones —no como conteos censales exactos—. Se usan invertidos:
`tasa_no_pobreza = 1 − FGT0` y `tasa_igualdad = 1 − Gini`.

---

## 4. De indicador a puntaje: el procedimiento, paso a paso

### Paso 1 — Denominador con umbral de masa crítica

Los conteos se convierten en tasas por 100.000 habitantes, pero el denominador usa
**`max(población, 50.000)`**:

```
denominador = max(poblacion, 50000) / 100000
```

**Por qué.** Con el denominador real, un cantón rural de 6.000 habitantes que tiene dos canchas y
un parque obtiene una "tasa" altísima y desplaza a ciudades reales. Ese resultado es un artefacto
aritmético del denominador, no una diferencia de oportunidad: nadie vive mejor porque su cantón
tenga pocos vecinos. El umbral de 50.000 habitantes es el tamaño a partir del cual un cantón puede
sostener una oferta completa de equipamientos; por debajo, la oferta se mide contra esa masa
mínima. **166 de los 221 cantones** están por debajo del umbral, así que esta decisión importa y se
audita en §7.

### Paso 2 — Suavizado por credibilidad

```
tasa_suav = (conteo + m · tasa_nacional) / (denominador + m)
m = 1,0        tasa_nacional = Σ(conteos) / Σ(denominadores)
```

Es el estimador estándar de credibilidad (equivalente a un previo Gamma-Poisson con media igual a
la tasa nacional y peso de una unidad de 100.000 habitantes). Evita que un cantón con un solo
equipamiento salte al primer puesto por azar de conteo. Tasas nacionales del corte
(por 100.000 habitantes): movilidad ciclista 5,27 · red peatonal 238,11 · senderos 105,08 ·
deporte 73,48 · naturaleza 42,60 · servicios 70,18.

### Paso 3 — Rango percentil

Cada sub-indicador se transforma en su **rango percentil (0-100)** entre los cantones con dato:

```
percentil = rank(valor, ties.method = "average") / (n + 1) × 100
```

**Por qué percentiles y no valores absolutos.** Los indicadores tienen escalas y asimetrías muy
distintas (de 5,27 a 238 por 100.000). El percentil los vuelve comparables y robusto a valores
extremos. **Consecuencia que hay que decir en voz alta:** la nota de un cantón depende del grupo
contra el que se compara. Un 70 significa "mejor que el 70 % de los cantones comparados", no
"70 sobre un ideal".

### Paso 4 — Dimensiones

| Dimensión | Cálculo |
|---|---|
| D1 | Media simple de los percentiles disponibles de movilidad ciclista, red peatonal y senderos |
| D2 | Percentil de `n_deporte` |
| D3 | Percentil de `n_naturaleza` |
| D4 | Media simple de los percentiles disponibles de acceso a hospital, atención primaria y escuela |
| D5 | Percentil de `n_servicios` |
| D6 | 0,7 · percentil(no pobreza) + 0,3 · percentil(igualdad) |

En D6 la pobreza pesa 0,7 y la desigualdad 0,3: la pobreza mide directamente privación; la
desigualdad matiza sin dominar.

### Paso 5 — Índice y cobertura

```
IHA = Σ(peso_d · D_d) / Σ(peso_d disponible)
```

Los pesos se **renormalizan** sobre las dimensiones que tienen dato, y se guarda
`cobertura_peso = Σ(peso_d disponible)`.

**Estado de los datos:**

| Estado | Condición | Comportamiento |
|---|---|---|
| `ok` | `cobertura_peso ≥ 0,60` | IHA calculado |
| `parcial` | `0,30 ≤ cobertura_peso < 0,60` | IHA calculado, marcado |
| `sin_datos` | `cobertura_peso < 0,30` o población `NA` | **IHA = NA, nunca 0** |

**Por qué «nunca 0» es una regla dura.** Un cero significa "se midió y salió pésimo". Un cantón
sin datos suficientes es otra cosa: no se midió. Confundirlos castigaría a los cantones con menos
información pública, que suelen ser los que más necesitan atención. La regla se prueba
funcionalmente en `tests/test_indice_sin_datos.R` y en la verificación nº 13.

En el corte publicado **los 221 cantones superan el umbral de cobertura** (`ok`), así que no hay
ninguno marcado «sin datos». El mecanismo existe, está probado y se activará cuando un cantón
pierda cobertura.

### Paso 6 — Ranking

`rank_nacional` ordena de 1 (mejor) a 221 sobre los cantones con IHA. Se añaden
`principales_fortalezas` y `principales_brechas` (las dos dimensiones extremas de cada cantón).

### Paso 7 — Agregación provincial

- **`IHA` provincial** = media de los IHA cantonales **ponderada por población** (definición principal).
- **`IHA_recalculado_provincial`** = se suman los conteos por provincia, se recalculan tasas y
  percentiles **entre las 24 provincias** y se aplica la misma fórmula.

Los dos valores **no coinciden por construcción** (en el corte, correlación 0,797): el percentil
depende del conjunto de unidades comparadas, y 24 provincias no se distribuyen igual que 221
cantones. Se publican ambos para que nadie tenga que confiar en una sola cifra.

---

## 5. Contraste con fuentes independientes

### 5.1 Población

La población cantonal del dataset de pobreza suma **14.347.037**, mientras que la fuente provincial
independiente (HDX/OCHA-INEC, 2020) suma **16.693.205**: un ratio de **0,860**. La diferencia es de
**nivel**, no de orden:

- Dispersión del ratio entre provincias (CV): **0,064** → la diferencia es aproximadamente uniforme.
- Al reescalar la población cantonal a los totales provinciales oficiales (reparto proporcional) y
  recalcular el índice completo, la correlación de Spearman entre ambos rankings es **0,985**.

**Conclusión:** la diferencia de nivel no distorsiona el orden de los cantones, y por eso el índice
usa la población cantonal (única fuente consistente a esa escala) dejando constancia del desfase.
Se documenta como limitación en §6.

### 5.2 Comprobación de que el orden no es absurdo

- Los diez primeros son Cuenca, Ibarra, Mejía, Latacunga, Quito, Portoviejo, Loja, Zamora,
  Gualaceo y Samborondón: capitales provinciales y cantones con oferta consolidada. Cuenca y Quito
  encabezando coincide con su posición habitual en estudios de calidad de vida urbana en Ecuador.
- Los últimos son Palenque, Paquisha, Vinces, El Pan, Colimes, Sevilla de Oro, Balzar, Marcabelí,
  Arajuno y Olmedo: cantones pequeños, rurales o con oferta escasa.
- Correlación entre IHA y pobreza: **negativa**, en la dirección esperada.

### 5.3 Verificación automatizada

`R/06_verify.R` ejecuta 14 comprobaciones (cobertura, unicidad, rangos, ceros falsos, consistencia
cantonal-provincial, emparejamiento geográfico, contraste de población, trazabilidad, filtros
encadenados, integridad del pipeline, privacidad, coherencia entre escalas, mecanismo «sin datos» y
sensibilidad). Resultado del corte: **14/14 PASS**. Reporte:
`tests/reports/verificacion_datos.txt`.

---

## 6. Limitaciones

1. **OpenStreetMap mide lo mapeado, no lo que existe.** Un cantón con buena infraestructura sin
   mapear aparece penalizado. La cobertura de OSM en Ecuador es desigual y mejor en ciudades.
2. **No hay indicador Strava directo** (§8). La dimensión de movilidad activa mide
   *infraestructura*, no *uso*.
3. **La accesibilidad es de viaje en auto**, con velocidades estándar por tipo de vía, sin tráfico
   real ni estacionalidad. Para movilidad activa, el auto no es el modo relevante.
4. **Pobreza y Gini son estimaciones**, no conteos censales exactos.
5. **La población cantonal tiene un desfase de nivel** frente a la serie provincial 2020 (§5.1),
   sin efecto apreciable sobre el orden.
6. **El percentil es relativo al grupo comparado.** La misma ciudad puede obtener notas distintas
   si se compara con todo el país o dentro de su provincia.
7. **El umbral de masa crítica es una decisión de diseño** con efecto real sobre los cantones
   pequeños (§7).
8. **El IHA no mide** calidad de vivienda, empleo, seguridad, calidad real de los servicios ni
   costo de vida.
9. **Corte único, sin series temporales.** Es una fotografía con fecha, no una tendencia.

---

## 7. Sensibilidad: cuánto dependen los resultados de las decisiones

Cada supuesto discutible se publica como variante verificable, no como letra pequeña.

| Decisión | Variante publicada | Efecto medido |
|---|---|---|
| Umbral de masa crítica | `IHA_sin_umbral` y `rank_sin_umbral` (denominador = población real) | Spearman entre rankings = **0,514**; el cambio se concentra en cantones bajo el umbral |
| Población de base | Recalculo con población reescalada a totales provinciales oficiales | Spearman del IHA = **0,985** |
| Escala de comparación | `IHA` cantonal vs `IHA_recalculado_provincial` | Correlación = **0,797** |
| Normalización | Percentil en vez de valor absoluto | Documentado en §4 paso 3 |

La sensibilidad al umbral (0,514) es la más alta y por eso se publica la columna completa
`IHA_sin_umbral`: cualquiera puede reproducir ambos órdenes y decidir cuál le parece más razonable
para su caso.

---

## 8. Por qué no hay un indicador Strava directo

Los análisis que inspiran este proyecto usan **Strava Metro**, el producto de datos agregados de
Strava para planificación de infraestructura. Sus características relevantes:

- **No es de acceso abierto.** Requiere un acuerdo de uso con Strava y su cobertura se limita, en
  la práctica, a las ciudades donde hay convenio.
- **El heatmap global no es una alternativa.** Sus términos de uso prohíben reconstruir los datos
  agregados a partir de él, y hacerlo sería además una mala práctica de datos personales.
- **Sesgo conocido.** Los estudios sobre datos de actividad voluntaria coinciden en que
  sobrerrepresentan a hombres, adultos, residentes urbanos y de renta media-alta, y que la relación
  entre volumen registrado y conteos reales varía por ciudad y por tipo de vía. Usarlo sin
  calibración local para ordenar cantones de todo un país sería sobreinterpretarlo.

**Qué hace este proyecto en su lugar:**

1. Mide la **infraestructura** que hace posible la actividad (OSM) y el **acceso** a servicios
   (HeiGIT): son los dos factores del entorno construido con mejor respaldo y son abiertos.
2. Documenta el sesgo de Strava explícitamente aquí, en la app y en la guía de uso.
3. Deja el **conector implementado y probado** (`R/lib_strava.R`, `R/05_strava_adapter.R`,
   `tests/test_strava_adapter.R`). Esquema esperado por período:

   ```
   dpa_canton,actividad_total,ciclistas,peatones,periodo,marca
   0101,152340,88990,63350,2025-Q4,
   ```

   Con licencia, el adaptador produce `strava_actividad_total`, `strava_actividad_por_1000` y
   `strava_percentil` **como columnas aparte, sin tocar los pesos del IHA**, para que la
   comparación con esta metodología siga siendo válida. Sin licencia, el estado publicado es
   explícito: `no_disponible_sin_licencia` (`data/processed/strava_estado.json`).

   El único fixture cargado en el repositorio es **sintético** y está marcado como tal dentro del
   propio archivo (columna `marca`) y en `tests/fixtures/LEEME.txt`.

---

## 9. Reproducir el índice

```bash
Rscript run_all.R            # pipeline completo
Rscript run_all.R --skip-fetch   # usando la caché de OSM
Rscript -e "testthat::test_dir('tests')"
```

Pasos internos: `01_fetch_osm` → `02_build_geography` → `03_build_indicators` →
`04_build_index` → `05_strava_adapter` → `07_build_web` → `06_verify`.
El núcleo del índice está en `R/lib_iha.R`, que usan tanto el cálculo oficial como las pruebas:
**lo que se prueba es exactamente lo que se publica**.

**Requisito de entorno:** R 4.4 o superior. Paquetes: `sf`, `dplyr`, `tidyr`, `readr`, `readxl`,
`jsonlite`, `httr2`, `stringi`, `units`, `leaflet`, `shiny`, `DT`, `plotly`, `scales`, `bslib`,
`testthat`, `rmapshaper` (opcional, mejora la simplificación de geometrías).

---

## 10. Glosario

| Término | Significado |
|---|---|
| **DPA** | División Político Administrativa del INEC: provincia (2 dígitos) + cantón (4 dígitos) |
| **ADM1 / ADM2** | Niveles administrativos del estándar humanitario: provincia / cantón |
| **FGT0** | Incidencia de pobreza por ingresos: proporción de población bajo la línea de pobreza |
| **Gini** | Desigualdad en la distribución del ingreso (0 = igualdad perfecta) |
| **Percentil** | Posición relativa (0-100) dentro del grupo comparado |
| **Masa crítica** | Umbral de población (50.000 hab.) usado como denominador mínimo |
| **Credibilidad** | Suavizado que acerca los valores extremos de muestras pequeñas a la media nacional |
| **ODbL** | Licencia de OpenStreetMap: uso libre con atribución y compartir igual |
