/* ---------------------------------------------------------------------------
   Vivir Activo EC — lógica del explorador interactivo
   Mapa coroplético dinámico con filtros encadenados provincia -> cantón.
   Sin dependencias más allá de Leaflet. Datos: ./data/*.json|geojson
   --------------------------------------------------------------------------- */

const RAMP = ['#f8f4ec', '#ecdfc6', '#dcbf95', '#c99a63', '#a9723f', '#7d4a2a', '#46281a'];
const COL_SIN_DATO = '#b9b3a8';
const COL_BORDE = '#fffdf9';

const estado = {
  provincia: '',
  canton: '',
  indicador: 'IHA',
  buscar: '',
  orden: { campo: 'IHA', asc: false },
  capas: {},
  datos: null,
  capaActual: null
};

/* ----------------------------- utilidades ------------------------------- */

function colorInterp(t) {
  if (!isFinite(t)) return COL_SIN_DATO;
  t = Math.max(0, Math.min(1, t));
  const n = RAMP.length - 1;
  const x = t * n;
  const i = Math.min(n - 1, Math.floor(x));
  const f = x - i;
  const a = hex2rgb(RAMP[i]);
  const b = hex2rgb(RAMP[i + 1]);
  const c = a.map((v, k) => Math.round(v + (b[k] - v) * f));
  return `rgb(${c[0]},${c[1]},${c[2]})`;
}

function hex2rgb(h) {
  return [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
}

function fmt(valor, ind) {
  if (valor === null || valor === undefined || Number.isNaN(valor)) return 'sin datos';
  const d = ind.decimales === undefined ? 1 : ind.decimales;
  if (ind.formato === 'porcentaje') return `${(valor * 100).toFixed(1).replace('.', ',')} %`;
  if (ind.formato === 'entero') return Math.round(valor).toLocaleString('es-EC');
  if (ind.formato === 'hab_km2') return `${Math.round(valor).toLocaleString('es-EC')} hab/km²`;
  if (ind.formato === 'km') return `${valor.toFixed(1).replace('.', ',')} km`;
  if (ind.formato === 'indice') return `${valor.toFixed(d).replace('.', ',')} / 100`;
  return valor.toFixed(d).replace('.', ',');
}

function fmtCorto(valor, ind) {
  if (valor === null || valor === undefined || Number.isNaN(valor)) return 'sin datos';
  const d = ind.decimales === undefined ? 1 : ind.decimales;
  if (ind.formato === 'porcentaje') return `${(valor * 100).toFixed(1).replace('.', ',')}%`;
  if (ind.formato === 'entero') return Math.round(valor).toLocaleString('es-EC');
  return valor.toFixed(d).replace('.', ',');
}

const COLOR_ESTADO = { ok: 'e-ok', parcial: 'e-parcial', sin_datos: 'e-sindatos' };
const TEXTO_ESTADO = { ok: 'Datos completos', parcial: 'Datos parciales', sin_datos: 'Sin datos' };

/* ------------------------------- arranque ------------------------------- */

Promise.all([
  fetch('./data/indicadores.json').then(r => r.json()),
  fetch('./data/cantones.geojson').then(r => r.json()),
  fetch('./data/provincias.geojson').then(r => r.json())
]).then(([meta, geoCant, geoProv]) => {
  estado.datos = meta;
  estado.geoCant = geoCant;
  estado.geoProv = geoProv;
  estado.porDpa = new Map(meta.cantones.map(c => [c.dpa, c]));
  inicializar(meta, geoCant, geoProv);
}).catch(err => {
  document.getElementById('mapa').innerHTML =
    `<div style="padding:22px;font-family:inherit">No se pudieron cargar los datos (${err}). ` +
    `Revisa que existan ./data/indicadores.json, ./data/cantones.geojson y ./data/provincias.geojson.</div>`;
});

function inicializar(meta, geoCant, geoProv) {
  // Encabezado y pie
  if (meta.version_iha) document.querySelector('.chip-acento').textContent = meta.version_iha;
  document.querySelectorAll('.chip')[1].textContent =
    `${meta.cantones.length} cantones · ${meta.provincias.length} provincias`;
  if (meta.generado) {
    document.getElementById('pie-version').textContent =
      `Índice calculado el ${meta.generado.slice(0, 10)}. Datos de OpenStreetMap con fecha base ${meta.fecha_corte_osm || 'no disponible'}.`;
  }
  if (meta.repo) {
    const a = document.createElement('a');
    a.href = meta.repo; a.textContent = meta.repo.replace('https://', '');
    const c = document.getElementById('pie-repo'); c.textContent = ''; c.appendChild(a);
  }

  // Selects
  const selProv = document.getElementById('sel-provincia');
  selProv.innerHTML = '<option value="">Todo el Ecuador</option>' +
    meta.provincias.map(p => `<option value="${p.dpa}">${p.nombre}</option>`).join('');

  const selInd = document.getElementById('sel-indicador');
  const grupos = {};
  meta.indicadores.forEach(i => { (grupos[i.grupo] = grupos[i.grupo] || []).push(i); });
  selInd.innerHTML = Object.entries(grupos).map(([g, items]) =>
    `<optgroup label="${g}">` + items.map(i =>
      `<option value="${i.id}"${i.id === 'IHA' ? ' selected' : ''}>${i.label}</option>`).join('') +
    '</optgroup>').join('');

  selProv.addEventListener('change', () => {
    estado.provincia = selProv.value;
    estado.canton = '';
    reconstruirCantones();
    refrescar();
  });
  document.getElementById('sel-canton').addEventListener('change', e => {
    estado.canton = e.target.value; refrescar();
  });
  selInd.addEventListener('change', e => { estado.indicador = e.target.value; refrescar(); });

  document.getElementById('btn-pais').addEventListener('click', () => {
    estado.provincia = ''; estado.canton = '';
    setTimeout(reconstruirCantones, 350);
    refrescar();
  });
  document.getElementById('btn-reset').addEventListener('click', () => {
    estado.buscar = ''; document.getElementById('buscar').value = '';
    refrescar();
  });
  document.getElementById('buscar').addEventListener('input', e => {
    estado.buscar = e.target.value.toLowerCase().trim();
    pintarTabla();
  });
  document.getElementById('btn-csv').addEventListener('click', descargarCSV);

  document.querySelectorAll('.plegable').forEach(h => {
    h.addEventListener('click', () => h.closest('.colapsable').classList.toggle('cerrado'));
  });

  pintarFuentes(meta.fuentes || []);
  reconstruirCantones();
  montarMapa(geoProv);
  refrescar();
}

function reconstruirCantones() {
  const sel = document.getElementById('sel-canton');
  let lista = estado.datos.cantones;
  if (estado.provincia) lista = lista.filter(c => c.prov === estado.provincia);
  lista = lista.slice().sort((a, b) => {
    const va = a.v.IHA, vb = b.v.IHA;
    if (va === null && vb === null) return a.nombre.localeCompare(b.nombre, 'es');
    if (va === null) return 1;
    if (vb === null) return -1;
    return vb - va;
  });
  sel.innerHTML = '<option value="">Todos los cantones</option>' + lista.map(c =>
    `<option value="${c.dpa}"${c.dpa === estado.canton ? ' selected' : ''}>` +
    `${c.nombre}${c.v.IHA === null ? ' (sin datos)' : ` · IHA ${c.v.IHA.toFixed(0)}`}</option>`).join('');
  if (estado.canton && !lista.some(c => c.dpa === estado.canton)) estado.canton = '';
  sel.value = estado.canton;
}

/* --------------------------------- mapa --------------------------------- */

let mapa, capaCantones, capaProvincias;

function montarMapa(geoProv) {
  mapa = L.map('mapa', { zoomControl: true, minZoom: 5, maxZoom: 12, preferCanvas: true })
    .setView([-1.4, -78.4], 6);
  L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
    attribution: '&copy; OpenStreetMap &copy; CARTO', subdomains: 'abcd', maxZoom: 19
  }).addTo(mapa);
  capaCantones = L.geoJSON(null, {
    style: estiloCanton,
    onEachFeature: (f, layer) => {
      layer.on('mouseover', e => { e.target.setStyle({ color: '#1e3a5f', weight: 2.2 }); e.target.bringToFront(); });
      layer.on('mouseout', () => capaCantones.resetStyle(layer));
      layer.on('click', () => {
        estado.canton = f.properties.dpa_canton;
        document.getElementById('sel-canton').value = estado.canton;
        refrescar();
      });
    }
  }).addTo(mapa);
  capaProvincias = L.geoJSON(geoProv, {
    style: { color: '#1e3a5f', weight: 1.1, opacity: .5, fill: false, dashArray: '4 3' },
    interactive: false
  }).addTo(mapa);

  const leyenda = L.control({ position: 'bottomright' });
  leyenda.onAdd = () => {
    const d = L.DomUtil.create('div', 'leyenda');
    d.id = 'leyenda-html';
    return d;
  };
  leyenda.addTo(mapa);
  window._leyenda = leyenda;
}

function estiloCanton(f) {
  return { fillColor: f.properties._color || COL_SIN_DATO, fillOpacity: .88,
           color: COL_BORDE, weight: .6, opacity: .8 };
}

function visibles() {
  let l = estado.datos.cantones;
  if (estado.provincia) l = l.filter(c => c.prov === estado.provincia);
  if (estado.canton) l = l.filter(c => c.dpa === estado.canton);
  return l;
}

function metaIndicador() {
  return estado.datos.indicadores.find(i => i.id === estado.indicador);
}

function refrescar() {
  const ind = metaIndicador();
  const lista = visibles();
  const valores = lista.map(c => c.v[ind.id]).filter(v => v !== null && v !== undefined && isFinite(v));
  const min = valores.length ? Math.min(...valores) : 0;
  const max = valores.length ? Math.max(...valores) : 1;
  const rango = max - min || 1;

  // Colores
  const colorDe = dpa => {
    const c = estado.porDpa.get(dpa);
    const v = c ? c.v[ind.id] : null;
    if (v === null || v === undefined || !isFinite(v)) return COL_SIN_DATO;
    return colorInterp((v - min) / rango);
  };

  // Capa
  const dpasVisibles = new Set(lista.map(c => c.dpa));
  capaCantones.clearLayers();
  const gj = JSON.parse(JSON.stringify(estado.geoCant));
  gj.features = gj.features.filter(f => dpasVisibles.has(f.properties.dpa_canton));
  gj.features.forEach(f => {
    f.properties._color = colorDe(f.properties.dpa_canton);
    const c = estado.porDpa.get(f.properties.dpa_canton);
    const v = c ? c.v[ind.id] : null;
    f.properties._tooltip =
      `<b>${f.properties.canton}</b><br/><span style="color:#7d4a2a">${f.properties.provincia}</span><br/>` +
      `${ind.label}: <b>${fmt(v, ind)}</b>` +
      (c && c.v.IHA !== null ? `<br/>IHA: <b>${c.v.IHA.toFixed(1)}</b> · puesto ${c.rank}` : '');
  });
  capaCantones.addData(gj);
  capaCantones.eachLayer(l => { l.bindTooltip(l.feature.properties._tooltip, { sticky: true }); });

  // Leyenda
  const ley = document.getElementById('leyenda-html');
  if (ley) {
    if (valores.length) {
      const pasos = [];
      for (let i = RAMP.length - 1; i >= 0; i--) {
        const marca = min + (i / (RAMP.length - 1)) * rango;
        pasos.push(`<div class="leyenda-fila"><span class="leyenda-i" style="background:${RAMP[i]}"></span>` +
          `<span>${fmtCorto(marca, ind)}</span></div>`);
      }
      ley.innerHTML = `<div class="leyenda-titulo">${ind.label}</div>${pasos.join('')}` +
        `<div class="leyenda-fila" style="margin-top:4px"><span class="leyenda-i" style="background:${COL_SIN_DATO}"></span><span>sin datos</span></div>`;
    } else {
      ley.innerHTML = '<div class="leyenda-titulo">Sin valores para pintar</div>';
    }
  }

  // Escala del panel
  document.getElementById('escala-barra').style.background =
    `linear-gradient(90deg, ${RAMP.join(',')})`;
  document.getElementById('escala-min').textContent = valores.length ? fmtCorto(min, ind) : '—';
  document.getElementById('escala-max').textContent = valores.length ? fmtCorto(max, ind) : '—';
  document.getElementById('escala-titulo').textContent = valores.length
    ? `${ind.label} · ${ind.direccion === 'alto_mejor' ? 'más oscuro = mejor' : 'más oscuro = peor'}`
    : 'Sin datos para este indicador en la selección';

  document.getElementById('explica-indicador').textContent = ind.explica;

  // Zoom
  if (estado.provincia) {
    const g = estado.geoCant.features.filter(f =>
      f.properties.dpa_provincia === estado.provincia &&
      (!estado.canton || f.properties.dpa_canton === estado.canton));
    if (g.length) {
      const capa = L.geoJSON(g);
      mapa.fitBounds(capa.getBounds(), { padding: [22, 22], maxZoom: estado.canton ? 11 : 9 });
    }
  } else if (!estado.canton) {
    mapa.setView([-1.4, -78.4], 6);
  }

  pintarFicha(lista, ind);
  pintarDetalle(estado.canton);
  pintarTabla();
}

/* ------------------------------ ficha ----------------------------------- */

function pintarFicha(lista, ind) {
  const vals = lista.map(c => c.v[ind.id]).filter(v => v !== null && isFinite(v));
  const foco = estado.canton ? estado.porDpa.get(estado.canton) : null;
  const rot = document.getElementById('ficha-rotulo');
  const val = document.getElementById('ficha-valor');
  const ext = document.getElementById('ficha-extra');

  if (foco) {
    rot.textContent = `${foco.nombre} · ${foco.prov_nombre}`;
    val.textContent = fmt(foco.v[ind.id], ind);
    ext.textContent = foco.v.IHA === null
      ? 'Este cantón no tiene índice calculado (sin datos suficientes).'
      : `IHA ${foco.v.IHA.toFixed(1)} · puesto ${foco.rank} de ${estado.datos.cantones.filter(c => c.v.IHA !== null).length}`;
  } else if (estado.provincia) {
    rot.textContent = `${nombreProvincia(estado.provincia)} · promedio simple`;
    val.textContent = vals.length ? fmt(vals.reduce((a, b) => a + b, 0) / vals.length, ind) : '—';
    ext.textContent = `${lista.length} cantones · ${vals.length} con dato`;
  } else {
    rot.textContent = 'Promedio simple del país';
    val.textContent = vals.length ? fmt(vals.reduce((a, b) => a + b, 0) / vals.length, ind) : '—';
    ext.textContent = `${lista.length} cantones · ${lista.filter(c => c.v.IHA === null).length} sin datos`;
  }
}

function nombreProvincia(dpa) {
  const p = estado.datos.provincias.find(x => x.dpa === dpa);
  return p ? p.nombre : dpa;
}

function pintarDetalle(dpa) {
  const cuerpo = document.getElementById('detalle-cuerpo');
  const c = dpa ? estado.porDpa.get(dpa) : null;
  if (!c) {
    const lista = visibles();
    const conIha = lista.filter(x => x.v.IHA !== null).sort((a, b) => b.v.IHA - a.v.IHA);
    const pob = lista.reduce((a, x) => a + (x.v.poblacion || 0), 0);
    const filas = [
      ['Cantones visibles', lista.length],
      ['Con índice calculado', lista.filter(x => x.v.IHA !== null).length],
      ['Sin datos suficientes', lista.filter(x => x.estado === 'sin_datos').length],
      ['IHA promedio', conIha.length ? (conIha.reduce((a, x) => a + x.v.IHA, 0) / conIha.length).toFixed(1) : 'sin datos'],
      ['IHA más alto', conIha.length ? `${conIha[0].nombre} (${conIha[0].v.IHA.toFixed(1)})` : 'sin datos'],
      ['IHA más bajo', conIha.length ? `${conIha[conIha.length - 1].nombre} (${conIha[conIha.length - 1].v.IHA.toFixed(1)})` : 'sin datos'],
      ['Población sumada', Math.round(pob).toLocaleString('es-EC')]
    ];
    cuerpo.innerHTML = filas.map(([k, v]) => `<tr><td>${k}</td><td>${v}</td></tr>`).join('');
    return;
  }
  const inds = estado.datos.indicadores;
  const g = id => inds.find(i => i.id === id) || { label: id, formato: 'numero', decimales: 1 };
  const filas = [
    ['Índice de Habitabilidad Activa', c.v.IHA === null ? 'sin datos' : `${c.v.IHA.toFixed(1)} / 100`],
    ['1 · Movilidad activa', fmt(c.v.D1_movilidad_activa, g('D1_movilidad_activa'))],
    ['2 · Deporte y recreación', fmt(c.v.D2_deporte_recreacion, g('D2_deporte_recreacion'))],
    ['3 · Naturaleza y áreas verdes', fmt(c.v.D3_naturaleza_areas_verdes, g('D3_naturaleza_areas_verdes'))],
    ['4 · Acceso a salud y educación', fmt(c.v.D4_acceso_salud_educacion, g('D4_acceso_salud_educacion'))],
    ['5 · Servicios y vida cotidiana', fmt(c.v.D5_servicios_vida_cotidiana, g('D5_servicios_vida_cotidiana'))],
    ['6 · Contexto socioeconómico', fmt(c.v.D6_contexto_socioeconomico, g('D6_contexto_socioeconomico'))],
    ['Población', fmt(c.v.poblacion, g('poblacion'))],
    ['Densidad', fmt(c.v.densidad_hab_km2, g('densidad_hab_km2'))],
    ['Pobreza por ingresos (FGT0)', fmt(c.v.pobreza_fgt0, g('pobreza_fgt0'))],
    ['Kilómetros de ciclovía', fmt(c.v.km_ciclovia, g('km_ciclovia'))],
    ['Principales fortalezas', c.fortalezas || '—'],
    ['Principales brechas', c.brechas || '—'],
    ['Estado de los datos', TEXTO_ESTADO[c.estado] || c.estado]
  ];
  cuerpo.innerHTML = filas.map(([k, v]) => `<tr><td>${k}</td><td>${v}</td></tr>`).join('');
}

/* -------------------------------- tabla --------------------------------- */

const COLUMNAS = [
  { campo: 'nombre',        titulo: 'Cantón' },
  { campo: 'prov_nombre',   titulo: 'Provincia' },
  { campo: 'IHA',           titulo: 'IHA' },
  { campo: 'estado',        titulo: 'Datos' },
  { campo: 'D1',            titulo: 'Movilidad' },
  { campo: 'D2',            titulo: 'Deporte' },
  { campo: 'D3',            titulo: 'Naturaleza' },
  { campo: 'D4',            titulo: 'Acceso' },
  { campo: 'D5',            titulo: 'Servicios' },
  { campo: 'D6',            titulo: 'Contexto' },
  { campo: 'poblacion',     titulo: 'Población' },
  { campo: 'rank',          titulo: 'Puesto' }
];

function filaDe(c) {
  return {
    dpa: c.dpa, nombre: c.nombre, prov_nombre: c.prov_nombre,
    IHA: c.v.IHA, estado: c.estado,
    D1: c.v.D1_movilidad_activa, D2: c.v.D2_deporte_recreacion,
    D3: c.v.D3_naturaleza_areas_verdes, D4: c.v.D4_acceso_salud_educacion,
    D5: c.v.D5_servicios_vida_cotidiana, D6: c.v.D6_contexto_socioeconomico,
    poblacion: c.v.poblacion, rank: c.rank
  };
}

function filasVisibles() {
  let filas = visibles().map(filaDe);
  if (estado.buscar) {
    const q = estado.buscar;
    filas = filas.filter(f =>
      (f.nombre || '').toLowerCase().includes(q) || (f.prov_nombre || '').toLowerCase().includes(q));
  }
  const { campo, asc } = estado.orden;
  filas.sort((a, b) => {
    let va = campo in a ? a[campo] : a[campo];
    let vb = campo in b ? b[campo] : b[campo];
    if (va === null || va === undefined) return 1;
    if (vb === null || vb === undefined) return -1;
    if (typeof va === 'number' && typeof vb === 'number') return asc ? va - vb : vb - va;
    const s = String(va).localeCompare(String(vb), 'es');
    return asc ? s : -s;
  });
  return filas;
}

function pintarTabla() {
  const thead = document.getElementById('tabla-cabeceras');
  thead.innerHTML = COLUMNAS.map(c => {
    const flecha = estado.orden.campo === c.campo ? (estado.orden.asc ? ' ▲' : ' ▼') : '';
    return `<th data-campo="${c.campo}" class="${['nombre','prov_nombre','estado'].includes(c.campo) ? '' : 'num'}">${c.titulo}${flecha}</th>`;
  }).join('');
  thead.querySelectorAll('th').forEach(th => th.addEventListener('click', () => {
    const campo = th.dataset.campo;
    estado.orden.asc = estado.orden.campo === campo ? !estado.orden.asc : false;
    estado.orden.campo = campo;
    pintarTabla();
  }));

  const filas = filasVisibles();
  const tbody = document.getElementById('tabla-cuerpo');
  tbody.innerHTML = filas.map(f => {
    const cel = (v, fmtFn) => `<td class="num">${fmtFn(v)}</td>`;
    const num = v => v === null || v === undefined ? '<span class="sin-dato">sin datos</span>' : v.toFixed(1).replace('.', ',');
    return `<tr data-dpa="${f.dpa}" class="${estado.canton === f.dpa ? 'activa' : ''}">` +
      `<td>${f.nombre}</td><td>${f.prov_nombre}</td>` +
      cel(f.IHA, num) +
      `<td><span class="punto-estado ${COLOR_ESTADO[f.estado]}"></span>${TEXTO_ESTADO[f.estado]}</td>` +
      cel(f.D1, num) + cel(f.D2, num) + cel(f.D3, num) + cel(f.D4, num) + cel(f.D5, num) + cel(f.D6, num) +
      `<td class="num">${f.poblacion ? Math.round(f.poblacion).toLocaleString('es-EC') : '<span class="sin-dato">sin datos</span>'}</td>` +
      `<td class="num">${f.rank ?? '<span class="sin-dato">—</span>'}</td></tr>`;
  }).join('');

  tbody.querySelectorAll('tr').forEach(tr => tr.addEventListener('click', () => {
    const dpa = tr.dataset.dpa;
    estado.canton = estado.canton === dpa ? '' : dpa;
    document.getElementById('sel-canton').value = estado.canton;
    refrescar();
  }));

  const ind = metaIndicador();
  document.getElementById('tabla-titulo').textContent =
    `Cantones visibles (${filas.length}) — ordenados por ${ind.label}`;
  const total = estado.datos.cantones;
  document.getElementById('tabla-pie').textContent =
    `Cobertura nacional: ${total.length} de ${total.length} cantones oficiales representados; ` +
    `${total.filter(c => c.estado !== 'sin_datos').length} con índice calculado y ` +
    `${total.filter(c => c.estado === 'sin_datos').length} marcados como sin datos. ` +
    `Los valores en gris no son cero.`;
}

function descargarCSV() {
  const filas = filasVisibles();
  const cols = [['Cantón','nombre'],['Provincia','prov_nombre'],['DPA','dpa'],['IHA','IHA'],
    ['Estado de datos','estado'],['Movilidad activa','D1'],['Deporte y recreación','D2'],
    ['Naturaleza y áreas verdes','D3'],['Acceso salud y educación','D4'],
    ['Servicios y vida cotidiana','D5'],['Contexto socioeconómico','D6'],
    ['Población','poblacion'],['Puesto nacional','rank']];
  const esc = v => v === null || v === undefined ? '' : `"${String(v).replace(/"/g, '""')}"`;
  const lineas = [cols.map(c => esc(c[0])).join(',')];
  filas.forEach(f => lineas.push(cols.map(c => esc(f[c[1]])).join(',')));
  const blob = new Blob(['\ufeff' + lineas.join('\n')], { type: 'text/csv;charset=utf-8;' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'vivir-activo-ec_seleccion.csv';
  a.click();
  URL.revokeObjectURL(a.href);
}

function pintarFuentes(fuentes) {
  const tb = document.querySelector('#tabla-fuentes tbody');
  tb.innerHTML = fuentes.map(f => `<tr><td>${f.variable}</td><td>${f.fuente}</td>` +
    `<td>${f.licencia}</td><td>${f.fecha}</td><td>${f.unidad}</td></tr>`).join('');
}
