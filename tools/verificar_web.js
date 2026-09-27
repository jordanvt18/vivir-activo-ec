// ---------------------------------------------------------------------------
// verificar_web.js — Verificación de interacción REAL del sitio publicado
//
// Abre la URL pública en Chrome headless, espera a que la app cargue los datos
// y luego ejercita la interfaz por el protocolo DevTools (CDP):
//   1. estado inicial (todo el país)
//   2. filtro encadenado: elegir provincia -> la lista de cantones se reduce
//   3. elegir cantón -> la ficha y la tabla se enfocan
//   4. cambiar de indicador -> la leyenda y la escala se recalculan
//   5. "Ver todo el país" -> vuelve al estado nacional
//   6. ruta vacía: buscar un texto inexistente -> tabla sin filas
//   7. captura de pantalla real (PNG)
//
// Uso: node verificar_web.js <url> <carpeta-salida>
// Sin dependencias: usa el cliente WebSocket nativo de Node 22.
// ---------------------------------------------------------------------------

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const URL_SITIO = process.argv[2] || 'https://jordanvt18.github.io/vivir-activo-ec/';
const OUT = process.argv[3] || '.';
const CHROME = process.argv[4] || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const PUERTO = 9333;
const PERFIL = path.join(os.tmpdir(), 'vaec-cdp-' + Date.now());

const esperar = ms => new Promise(r => setTimeout(r, ms));

// Espera activa a que la app haya terminado de cargar los datos y construido
// la interfaz. Sin esto, un arranque lento hace fallar las comprobaciones por
// una razón que no es un defecto de la aplicación.
async function esperarListo(cdp, timeoutMs = 120000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutMs) {
    const estado = await cdp.evaluar(`({
      prov: document.querySelectorAll('#sel-provincia option').length,
      ind: document.querySelectorAll('#sel-indicador option').length,
      filas: document.querySelectorAll('#tabla-cuerpo tr').length,
      tiles: document.querySelectorAll('#mapa img.leaflet-tile').length
    })`);
    if (estado.prov > 1 && estado.ind > 1 && estado.filas > 0) {
      return { esperaMs: Date.now() - t0, ...estado };
    }
    await esperar(1000);
  }
  throw new Error('La aplicación no terminó de inicializar en ' + timeoutMs + ' ms');
}

async function obtenerObjetivo() {
  for (let i = 0; i < 40; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${PUERTO}/json/list`);
      const lista = await r.json();
      const p = lista.find(t => t.type === 'page');
      if (p && p.webSocketDebuggerUrl) return p.webSocketDebuggerUrl;
    } catch (_) { /* aun no levanta */ }
    await esperar(500);
  }
  throw new Error('No se pudo conectar al puerto de depuracion de Chrome');
}

class CDP {
  constructor(ws) { this.ws = ws; this.id = 0; this.pend = new Map(); this.eventos = []; }
  static async conectar(url) {
    const ws = new WebSocket(url);
    await new Promise((res, rej) => {
      ws.onopen = res;
      ws.onerror = e => rej(new Error('WebSocket error'));
    });
    const c = new CDP(ws);
    ws.onmessage = ev => {
      const m = JSON.parse(ev.data);
      if (m.id && c.pend.has(m.id)) {
        const { res, rej } = c.pend.get(m.id); c.pend.delete(m.id);
        m.error ? rej(new Error(JSON.stringify(m.error))) : res(m.result);
      } else if (m.method) c.eventos.push(m);
    };
    return c;
  }
  enviar(method, params = {}) {
    const id = ++this.id;
    return new Promise((res, rej) => {
      this.pend.set(id, { res, rej });
      this.ws.send(JSON.stringify({ id, method, params }));
      setTimeout(() => {
        if (this.pend.has(id)) { this.pend.delete(id); rej(new Error('timeout: ' + method)); }
      }, 60000);
    });
  }
  async evaluar(expr) {
    const r = await this.enviar('Runtime.evaluate', {
      expression: expr, returnByValue: true, awaitPromise: true
    });
    if (r.exceptionDetails) throw new Error('JS: ' + JSON.stringify(r.exceptionDetails));
    return r.result.value;
  }
}

const ESTADO_JS = `(() => ({
  opcionesProvincia: document.querySelectorAll('#sel-provincia option').length,
  valorProvincia: document.getElementById('sel-provincia').value,
  opcionesCanton: document.querySelectorAll('#sel-canton option').length,
  valorCanton: document.getElementById('sel-canton').value,
  primerosCantones: Array.from(document.querySelectorAll('#sel-canton option')).slice(0,4).map(o=>o.textContent),
  filas: document.querySelectorAll('#tabla-cuerpo tr').length,
  tituloTabla: document.getElementById('tabla-titulo').textContent,
  fichaRotulo: document.getElementById('ficha-rotulo').textContent,
  fichaValor: document.getElementById('ficha-valor').textContent.trim(),
  fichaExtra: document.getElementById('ficha-extra').textContent,
  escala: document.getElementById('escala-min').textContent + ' / ' + document.getElementById('escala-max').textContent,
  escalaTitulo: document.getElementById('escala-titulo').textContent,
  explicacion: document.getElementById('explica-indicador').textContent.slice(0,60),
  detalle: Array.from(document.querySelectorAll('#detalle-cuerpo tr')).slice(0,4).map(t=>t.textContent),
  detalleFilas: document.querySelectorAll('#detalle-cuerpo tr').length,
  leyenda: (document.getElementById('leyenda-html')||{}).textContent ? document.getElementById('leyenda-html').textContent.slice(0,90) : '(sin leyenda)',
  fuentesFilas: document.querySelectorAll('#tabla-fuentes tbody tr').length,
  parrafosMetodo: document.querySelectorAll('#cuerpo-metodo p.explica').length,
  opcionesIndicador: document.querySelectorAll('#sel-indicador option').length,
  imgTiles: document.querySelectorAll('#mapa img.leaflet-tile').length,
  erroresJS: (window.__errores||[]).length
}))()`;

(async () => {
  const lineas = [];
  const log = s => { console.log(s); lineas.push(s); };
  let chrome;

  try {
    chrome = spawn(CHROME, [
      '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
      '--hide-scrollbars', '--window-size=1440,1100',
      `--remote-debugging-port=${PUERTO}`, `--user-data-dir=${PERFIL}`,
      '--remote-allow-origins=*', 'about:blank'
    ], { stdio: 'ignore' });

    const wsUrl = await obtenerObjetivo();
    const cdp = await CDP.conectar(wsUrl);

    await cdp.enviar('Page.enable');
    await cdp.enviar('Runtime.enable');

    // Captura de errores de consola de la propia pagina
    await cdp.enviar('Page.addScriptToEvaluateOnNewDocument', {
      source: 'window.__errores=[];window.addEventListener("error",e=>window.__errores.push(String(e.message)));'
    });

    log(`URL: ${URL_SITIO}`);
    log('');
    await cdp.enviar('Page.navigate', { url: URL_SITIO });
    await esperar(3000);   // margen inicial para el arranque del documento

    const listo = await esperarListo(cdp);
    log(`Aplicación lista tras ${listo.esperaMs} ms (provincias=${listo.prov}, indicadores=${listo.ind}, filas=${listo.filas}, tiles=${listo.tiles})`);
    await esperar(2500);   // margen para que terminen de pintar los tiles

    const inicial = await cdp.evaluar(ESTADO_JS);
    log('== 1. ESTADO INICIAL (todo el pais) ==');
    log(JSON.stringify(inicial, null, 2));

    // --- 2. Filtro encadenado: provincia ---
    const provAzuay = 15; // Azuay tiene 15 cantones
    await cdp.evaluar(`(() => { const s=document.getElementById('sel-provincia'); s.value='01'; s.dispatchEvent(new Event('change')); return true; })()`);
    await esperar(1500);
    const trasProv = await cdp.evaluar(ESTADO_JS);
    log('');
    log('== 2. TRAS ELEGIR PROVINCIA Azuay (01) ==');
    log(JSON.stringify({
      opcionesCanton: trasProv.opcionesCanton,
      primerosCantones: trasProv.primerosCantones,
      filas: trasProv.filas,
      tituloTabla: trasProv.tituloTabla,
      fichaRotulo: trasProv.fichaRotulo,
      fichaValor: trasProv.fichaValor
    }, null, 2));

    // --- 3. Filtro encadenado: canton ---
    await cdp.evaluar(`(() => { const s=document.getElementById('sel-canton'); s.value='0101'; s.dispatchEvent(new Event('change')); return true; })()`);
    await esperar(1500);
    const trasCanton = await cdp.evaluar(ESTADO_JS);
    log('');
    log('== 3. TRAS ELEGIR CANTON 0101 (Cuenca) ==');
    log(JSON.stringify({
      valorCanton: trasCanton.valorCanton,
      filas: trasCanton.filas,
      fichaRotulo: trasCanton.fichaRotulo,
      fichaValor: trasCanton.fichaValor,
      fichaExtra: trasCanton.fichaExtra,
      detalle: trasCanton.detalle
    }, null, 2));

    // --- 4. Cambio de indicador ---
    await cdp.evaluar(`(() => { const s=document.getElementById('sel-indicador'); s.value='pobreza_fgt0'; s.dispatchEvent(new Event('change')); return true; })()`);
    await esperar(2000);
    const trasIndicador = await cdp.evaluar(ESTADO_JS);
    log('');
    log('== 4. TRAS CAMBIAR INDICADOR a pobreza_fgt0 ==');
    log(JSON.stringify({
      escala: trasIndicador.escala,
      escalaTitulo: trasIndicador.escalaTitulo,
      explicacion: trasIndicador.explicacion,
      leyenda: trasIndicador.leyenda,
      fichaValor: trasIndicador.fichaValor
    }, null, 2));

    // --- 5. Volver al pais ---
    const clickRes = await cdp.evaluar(`(() => { try { document.getElementById('btn-pais').click(); return 'ok'; } catch(e) { return 'error: '+e.message; } })()`);
    const valInmediato = await cdp.evaluar(`document.getElementById('sel-provincia').value`);
    await esperar(1500);
    const trasPais = await cdp.evaluar(ESTADO_JS);
    log('');
    log('== 5. TRAS "Ver todo el pais" ==');
    log(JSON.stringify({ click: clickRes, valorProvinciaInmediato: valInmediato, valorProvincia: trasPais.valorProvincia, opcionesCanton: trasPais.opcionesCanton, filas: trasPais.filas, tituloTabla: trasPais.tituloTabla }, null, 2));

    // --- 6. Ruta vacia: busqueda sin resultados ---
    await cdp.evaluar(`(() => { const b=document.getElementById('buscar'); b.value='zzzz-no-existe'; b.dispatchEvent(new Event('input')); return true; })()`);
    await esperar(1200);
    const vacio = await cdp.evaluar(ESTADO_JS);
    log('');
    log('== 6. RUTA VACIA: busqueda sin resultados ==');
    log(JSON.stringify({ filas: vacio.filas, tituloTabla: vacio.tituloTabla }, null, 2));

    // --- 7. Captura de pantalla real ---
    await cdp.evaluar(`(() => { const b=document.getElementById('buscar'); b.value=''; b.dispatchEvent(new Event('input')); document.getElementById('btn-pais').click(); return true; })()`);
    await esperar(3000);
    const shot = await cdp.enviar('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true });
    fs.writeFileSync(path.join(OUT, 'sitio_escritorio.png'), Buffer.from(shot.data, 'base64'));
    log('');
    log('Captura escritorio guardada.');

    // Captura movil
    await cdp.enviar('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 2, mobile: true });
    await esperar(2500);
    const shotM = await cdp.enviar('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true });
    fs.writeFileSync(path.join(OUT, 'sitio_movil.png'), Buffer.from(shotM.data, 'base64'));
    log('Captura movil guardada.');

    // --- 8. Comprobaciones automaticas ---
    const pruebas = [];
    const ok = (n, cond, detalle) => pruebas.push(`${cond ? 'PASS' : 'FAIL'} | ${n} | ${detalle}`);

    ok('opciones-provincia', inicial.opcionesProvincia === 25, `esperado 25 (Todo el Ecuador + 24), obtenido ${inicial.opcionesProvincia}`);
    ok('opciones-canton-nacional', inicial.opcionesCanton === 222, `esperado 222 (Todos + 221), obtenido ${inicial.opcionesCanton}`);
    ok('filas-tabla-nacional', inicial.filas === 221, `esperado 221, obtenido ${inicial.filas}`);
    ok('filtro-provincia-reduce-cantones', trasProv.opcionesCanton === provAzuay + 1, `Azuay debe ofrecer ${provAzuay} cantones + "Todos", obtenido ${trasProv.opcionesCanton}`);
    ok('filtro-provincia-reduce-filas', trasProv.filas === provAzuay, `esperado ${provAzuay} filas, obtenido ${trasProv.filas}`);
    ok('filtro-canton-una-fila', trasCanton.filas === 1, `esperado 1 fila, obtenido ${trasCanton.filas}`);
    ok('ficha-muestra-cuenca', /Cuenca/.test(trasCanton.fichaRotulo), `rotulo: ${trasCanton.fichaRotulo}`);
    ok('detalle-con-dimensiones', trasCanton.detalleFilas >= 14, `filas de detalle de la ficha: ${trasCanton.detalleFilas} (esperado >= 14)`);
    ok('cambio-indicador-recalcula', trasIndicador.escalaTitulo.includes('FGT0') || trasIndicador.escalaTitulo.includes('índice'), `escala: ${trasIndicador.escalaTitulo}`);
    ok('boton-pais-restaura', trasPais.opcionesCanton === 222 && trasPais.filas === 221 && trasPais.valorProvincia === '', `provincia: "${trasPais.valorProvincia}", cantones: ${trasPais.opcionesCanton}, filas: ${trasPais.filas}`);
    ok('busqueda-vacia', vacio.filas === 0, `esperado 0, obtenido ${vacio.filas}`);
    ok('sin-errores-js', inicial.erroresJS === 0, `errores capturados: ${inicial.erroresJS}`);
    ok('tiles-del-mapa', inicial.imgTiles > 0, `tiles cargados: ${inicial.imgTiles}`);
    ok('fuentes-visibles', inicial.fuentesFilas >= 8, `filas de fuentes: ${inicial.fuentesFilas}`);
    ok('indicadores-disponibles', inicial.opcionesIndicador === 22, `esperado 22, obtenido ${inicial.opcionesIndicador}`);

    log('');
    log('== 8. COMPROBACIONES AUTOMATICAS ==');
    pruebas.forEach(p => log(p));
    const fallos = pruebas.filter(p => p.startsWith('FAIL')).length;
    log('');
    log(`TOTAL: ${pruebas.length} comprobaciones | PASS: ${pruebas.length - fallos} | FAIL: ${fallos}`);

    fs.writeFileSync(path.join(OUT, 'verificacion_web.txt'), lineas.join('\n'), 'utf8');
    chrome.kill();
    process.exit(fallos === 0 ? 0 : 1);
  } catch (e) {
    log('ERROR: ' + e.message);
    fs.writeFileSync(path.join(OUT, 'verificacion_web.txt'), lineas.join('\n'), 'utf8');
    if (chrome) chrome.kill();
    process.exit(2);
  }
})();
