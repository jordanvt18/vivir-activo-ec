# Privacidad y uso responsable de datos

## Resumen en una frase

**Este proyecto no contiene ni procesa ningún dato personal.** Todo el análisis se hace sobre
**agregados por unidad geográfica** (cantón y, para la población de control, provincia).

---

## 1. Qué se usó y a qué nivel

| Insumo | Nivel mínimo de desagregación | ¿Identifica personas? |
|---|---|---|
| Límites administrativos (geoBoundaries) | Polígono de cantón | No |
| Población, pobreza y Gini (HDX / INEC) | Cantón | No: son estimaciones agregadas |
| Accesibilidad a servicios (HeiGIT) | ADM2 (cantón) | No: porcentajes de población por banda de viaje |
| Infraestructura (OpenStreetMap) | Elemento del mapa (una vereda, una cancha, un parque) | No: son objetos del territorio, no personas |
| Ciclovías (OpenStreetMap, geometría) | Tramos de vía | No |

**No se usó en ningún momento:** trayectorias GPS, identificadores de atleta, correos, nombres,
dispositivos, ni datos por debajo del nivel de cantón.

---

## 2. Qué NO hace el proyecto

- **No rastrea personas.** No hay recolección de ubicación, ni de actividad de usuarios.
- **No usa el heatmap de Strava** ni intenta reconstruir sus datos agregados. Los términos de uso
  de Strava lo prohíben, y hacerlo sería además una mala práctica de protección de datos.
- **No publica información a nivel de parroquia, barrio o edificio.** El desglose máximo es cantón.
- **No infiere nada sobre individuos a partir de patrones agregados.**

---

## 3. Qué pasa si se integran datos licenciados de Strava Metro

El repositorio incluye un adaptador (`R/lib_strava.R`, `R/05_strava_adapter.R`) preparado para
incorporar datos agregados de Strava Metro **en caso de obtener licencia**. Sus reglas son:

1. **Solo agregados por cantón.** El esquema aceptado es
   `dpa_canton, actividad_total, ciclistas, peatones, periodo` (más una columna `marca` opcional).
2. **Rechazo automático por campos personales.** Si un archivo trae cualquiera de estas columnas,
   se descarta completo y se registra el motivo:
   `athlete_id`, `atleta_id`, `usuario`, `user_id`, `email`, `correo`, `lat`, `lon`, `latitude`,
   `longitude`, `gps`, `device_id`, `nombre`, `telefono`, `cedula`.
   La comprobación está probada en `tests/test_strava_adapter.R`.
3. **Sin efecto sobre el índice publicado.** Los datos de Strava, si existen, se publican como
   columnas aparte (`strava_*`) y **no alteran los pesos del IHA v1.0**, de modo que la
   comparación con la metodología publicada siga siendo válida.
4. **Cumplimiento de los términos de la fuente.** Si hay licencia, se respetarán sus condiciones de
   uso, umbrales mínimos de agregación y límites de redistribución, que se documentarán en este
   mismo archivo antes de publicar cualquier cifra.

Actualmente el estado publicado es **`no_disponible_sin_licencia`**, visible de forma explícita en
`data/processed/strava_estado.json`.

---

## 4. El fixture sintético del repositorio

`tests/fixtures/strava_metro_sintetico.csv` **no son datos reales**. Se genera con
`set.seed(20260927)` a partir de la población cantonal y lleva la columna
`marca = SINTETICO_NO_SON_DATOS_REALES`. Existe solo para probar el adaptador.

---

## 5. Principios de presentación de resultados

1. **Distinguir ausencia de cero.** Un cantón sin datos se muestra como *«sin datos»*, nunca como
   0, porque un cero significaría «se midió y salió mal» (ver `docs/metodologia.md` §4).
2. **Hacer visible el sesgo.** Que OpenStreetMap refleja lo *mapeado* —y que el mapeo es desigual
   entre ciudad y campo— se advierte en la app, en la guía de uso y en la metodología.
3. **No dar consejo personalizado.** La herramienta publica evidencia ordenada, no recomendaciones
   individuales de mudanza. No es asesoría inmobiliaria, legal ni financiera.
4. **Publicar el contexto suficiente para juzgar.** Fórmulas, pesos, fuentes, licencias y variantes
   de sensibilidad están a la vista, y `iha_metodologia.json` es legible por máquina.

---

## 6. Cómo reportar un problema

Si detectas un dato incorrecto, una fuente mal atribuida o cualquier preocupación de privacidad,
abre un *issue* en el repositorio del proyecto describiendo el caso concreto (cantón, indicador y
valor observado). Los problemas de privacidad se tratan con prioridad.

---

## 7. Marco normativo aplicable (Ecuador)

El proyecto se diseñó para ser compatible con el principio de **minimización de datos** y con el
tratamiento de datos agregados o anonimizados establecido en la **Ley Orgánica de Protección de
Datos Personales del Ecuador (LOPDP, 2021)** y su reglamento: no se tratan datos personales, no se
identifica a titulares y no se realiza perfilado individual. Se aplica el mismo criterio respecto
del **RGPD** europeo, por si el proyecto se reutiliza en ese contexto.

---

*Última revisión: 2026-09-27, junto con el corte de datos publicado.*
