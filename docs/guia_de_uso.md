# Guía de uso — Vivir Activo EC

Esta guía está escrita para que **cualquier persona, sin formación técnica**, pueda usar el mapa y
entender qué está viendo. Si buscas las fórmulas y las fuentes, ve a
[`metodologia.md`](metodologia.md).

---

## 1. ¿Qué es esto, en una frase?

Es un mapa de Ecuador que colorea cada cantón según **qué tan fácil es vivir ahí una vida activa**:
poder caminar o pedalear, hacer deporte, tener verde cerca, llegar rápido a un hospital o a una
escuela y resolver el día a día sin viajes largos.

No dice "este cantón es mejor que aquel" en abstracto. Dice **en qué es mejor cada uno**, para que
tú decidas según lo que te importa.

---

## 2. Cómo usar el mapa en 30 segundos

1. **Elige una provincia** en el primer desplegable. La lista de cantones se actualiza sola con los
   cantones de esa provincia. Si quieres ver todo el país, deja «Todo el Ecuador».
2. **Elige un cantón** si quieres mirar uno en detalle, o deja «Todos los cantones».
3. **Elige qué pintar** en el segundo desplegable: el índice general o una de sus seis dimensiones.
4. **Pasa el mouse** sobre un cantón para ver su ficha rápida. **Haz clic** para fijarlo abajo.
5. Mira la **tabla de abajo** para comparar todos los cantones visibles; puedes ordenarla por
   cualquier columna, buscarla y descargarla en CSV.

El botón **«Ver todo el país»** devuelve el mapa al punto de partida.

---

## 3. Cómo leer los colores (importante)

- **Crema claro** = valor bajo · **marrón oscuro** = valor alto.
- El mapa **recalcula los colores cada vez que cambias la selección**. Si estás viendo todo el
  país, comparas contra el país. Si estás viendo una provincia, comparas dentro de esa provincia.
  Eso significa que el mismo cantón puede verse más oscuro dentro de su provincia que frente al
  país entero: **no es un error, es el punto**.
- **Gris** = «sin datos». No es un cero. Es un cantón sobre el que no hay información suficiente
  para calcular el índice. En este corte no hay ningún cantón en gris, pero el mecanismo existe y
  se activaría automáticamente si un cantón perdiera cobertura.

> **La nota es relativa.** Un 70 quiere decir «mejor que el 70 % de los cantones comparados», no
> «70 sobre 100 de calidad absoluta». Comparar es la clave: la misma cifra significa cosas
> distintas en un grupo de 24 provincias que en uno de 221 cantones.

---

## 4. Qué significa cada indicador, en lenguaje llano

| Indicador | Qué quiere decir | Más oscuro significa |
|---|---|---|
| **Índice de Habitabilidad Activa (IHA)** | Resumen de todo lo demás en una sola nota | Más oportunidad de vida activa |
| **Movilidad activa** | Cuánta infraestructura hay para moverse sin auto: ciclovías, veredas, calles peatonales, escaleras, senderos | Más fácil moverse a pie o en bici |
| **Deporte y recreación** | Canchas, centros deportivos, gimnasios, piscinas, pistas, estadios, juegos infantiles | Más oferta para hacer ejercicio |
| **Naturaleza y áreas verdes** | Parques, jardines, reservas naturales y áreas de recreo | Más verde en la vida cotidiana |
| **Acceso a salud y educación** | Qué porcentaje de la población llega a un hospital, a atención primaria y a una escuela en un tiempo o distancia razonables | Servicios esenciales más cerca |
| **Servicios y vida cotidiana** | Escuelas, universidades, bibliotecas, mercados, supermercados y estaciones de transporte | Más servicios a mano |
| **Contexto socioeconómico** | Pobreza por ingresos y desigualdad del cantón | Mejor situación relativa |
| **Población** | Cuánta gente vive ahí | *(ni bueno ni malo: es contexto)* |
| **Densidad** | Habitantes por km² | *(contexto: los valores altos suelen ser cantones urbanos y pequeños)* |
| **Pobreza por ingresos (FGT0)** | Proporción de la población bajo la línea de pobreza | ⚠️ **Más oscuro = MÁS pobreza** (aquí el marrón es malo) |
| **Gini** | Desigualdad en los ingresos | ⚠️ **Más oscuro = MÁS desigualdad** |
| **Kilómetros de ciclovía** | Longitud de ciclovías mapeadas en el cantón | Más kilómetros |
| **Cobertura de datos del índice** | Porcentaje del índice que se pudo calcular con datos reales | Datos más completos |

⚠️ **Ojo con las dos excepciones:** en Pobreza y en Gini, más oscuro es *peor*. En el mapa, la
leyenda lo indica: cuando dice «más oscuro = peor», el color oscuro es una señal negativa.

---

## 5. Cómo comparar cantones sin equivocarse

**Tres preguntas antes de sacar conclusiones:**

1. **¿Qué me importa de verdad?** Si pedaleas todos los días, mira «Movilidad activa» y «Kilómetros
   de ciclovía». Si tienes hijos pequeños, «Acceso a salud y educación» y «Servicios». Si buscas
   tranquilidad y verde, «Naturaleza y áreas verdes». El índice general sirve para un primer
   barrido, no para decidir.
2. **¿Contra quién estoy comparando?** Si dudas entre dos cantones de provincias distintas, filtren
   primero a «Todo el Ecuador» para verlos en la misma escala.
3. **¿Tengo datos suficientes?** Mira la columna «Datos» en la tabla: `ok`, `parcial` o `sin datos`.
   Un cantón con datos parciales merece una lectura más cauta.

**Ejemplos de lectura útil**

- *«Quiero saber si mi cantón actual está bien o mal en bici respecto al país.»* → Provincia: Todo
  el Ecuador · Indicador: Movilidad activa · busca tu cantón en la tabla y mira su valor y su
  puesto.
- *«Me interesa una provincia concreta y no sé entre qué cantones elegir.»* → elige la provincia ·
  Indicador: Índice de Habitabilidad Activa · ordena la tabla por IHA y luego revisa las dos
  columnas de fortalezas y brechas del cantón que te interese.
- *«Busco barato pero con servicios cerca.»* → ordena por «Pobreza» y busca un IHA razonable en
  «Acceso» y «Servicios». Recuerda que más oscuro en pobreza es peor.

---

## 6. Qué NO te dice este mapa

Esta parte es tan importante como los datos. El índice **no mide**:

- **Precio de la vivienda, arriendo ni costo de vida.**
- **Empleo, ingresos ni oportunidades laborales.**
- **Seguridad ni convivencia.**
- **Calidad real** de hospitales, escuelas o parques (mide cercanía y cantidad, no funcionamiento).
- **Tráfico real ni tiempos puerta a puerta.** El acceso se estima viajando **en auto**, con
  velocidades estándar por tipo de vía.

Y hay un sesgo que conviene tener presente: los datos de infraestructura vienen de
**OpenStreetMap**, un mapa colaborativo. Un cantón con buena infraestructura que **no está mapeada**
aparece peor de lo que es. En Ecuador el mapeo es más completo en ciudades que en zonas rurales, así
que **desconfía de los valores bajos extremos** en cantones rurales: pueden ser un problema de
mapeo, no de realidad.

---

## 7. Sobre el "análisis con Strava"

Quizá llegaste aquí buscando algo del estilo "qué dicen los datos de Strava sobre dónde vivir".
Es una idea potente, pero conviene saber dos cosas antes de creerle a cualquier mapa que la use:

1. **Los datos agregados de Strava (Strava Metro) no son abiertos: requieren un convenio.** Y el
   heatmap público no se puede desarmar para reconstruirlos.
2. **Quien usa Strava no es una muestra de la población.** Sobrerrepresenta a hombres, adultos,
   gente de ciudad y de renta media-alta. Una ruta muy brillante en el heatmap puede significar
   "aquí pasa mucha gente con Strava", no "aquí es donde vive bien la gente".

Por eso este proyecto **mide la infraestructura y el acceso**, que sí son abiertos y no dependen de
quién tiene la app instalada. Y por eso advertimos de esto tanto aquí como dentro del mapa.

---

## 8. Preguntas frecuentes

**¿Por qué mi cantón tiene un número bajo si conozco gente que corre ahí?**
Mira «Cobertura de datos» y la columna «Datos». Si está en `parcial`, faltan datos. Si no,
probablemente la infraestructura exista pero **no esté mapeada** en OpenStreetMap: se puede
contribuir a arreglarlo editando el mapa.

**¿Por qué mi cantón baja o sube tanto si cambio de dimensión?**
Porque cada dimensión mide cosas distintas. Un cantón puede tener excelentes senderos y pocos
servicios: eso es información útil, no una contradicción.

**¿Esta nota decide dónde debo vivir?**
No. Es una herramienta para **hacer mejores preguntas** y descartar opciones, no para decidir. Antes
de mudarte, visita, conversa con vecinos y verifica precios y servicios en terreno.

**¿Puedo usar los datos y el mapa?**
Sí. El código es MIT y los datos tienen licencias abiertas (ver
[`fuentes_y_licencias.md`](fuentes_y_licencias.md)). Solo hay que **citar las fuentes**, en
particular OpenStreetMap y geoBoundaries.

**¿Se actualiza solo?**
No. Es un corte con fecha única (2026-09-27). Volver a generarlo es ejecutar un comando; ver
[`despliegue.md`](despliegue.md).

---

## 9. Si quieres ir más allá

- Descarga la tabla completa desde la propia página (**«Descargar CSV»**).
- Todos los datos crudos están en `data/processed/` y `web/data/`.
- Cada indicador indica su fuente, licencia y fecha en `data/processed/fuentes.csv` y en la sección
  «Metodología, fuentes y descarga de datos» del mapa.
- Para entender el cálculo completo: [`metodologia.md`](metodologia.md).

---

*Recordatorio legal: esto no es asesoría inmobiliaria, legal ni financiera. Es un ejercicio de
datos abiertos sobre el entorno construido y el acceso a servicios.*
