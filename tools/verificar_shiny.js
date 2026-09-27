// ---------------------------------------------------------------------------
// verificar_shiny.js — Verificación de interacción real de la app Shiny
//
// Ejercita la app Shiny en local con el protocolo DevTools: comprueba que los
// controles se construyen, que el filtro provincia -> cantón está encadenado,
// que la ficha y la tabla responden y que el mapa dibuja los cantones.
//
// Uso: node verificar_shiny.js <url> <salida.txt> <ruta-chrome>
// ---------------------------------------------------------------------------

const { spawn } = require('child_process');
const fs = require('fs'); const path = require('path'); const os = require('os');
const URL_APP = process.argv[2] || 'http://127.0.0.1:7654/';
const SALIDA = process.argv[3] || 'verificacion_shiny.txt';
const CHROME = process.argv[4] || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const PUERTO = 9336;
const PERFIL = path.join(os.tmpdir(), 'vaec-shiny-' + Date.now());
const esperar = ms => new Promise(r => setTimeout(r, ms));

async function objetivo() {
  for (let i = 0; i < 40; i++) {
    try {
      const l = await (await fetch(`http://127.0.0.1:${PUERTO}/json/list`)).json();
      const p = l.find(t => t.type === 'page');
      if (p && p.webSocketDebuggerUrl) return p.webSocketDebuggerUrl;
    } catch (_) {}
    await esperar(500);
  }
  throw new Error('sin CDP');
}
class CDP {
  constructor(ws) { this.ws = ws; this.id = 0; this.pend = new Map(); }
  static async conectar(u) {
    const ws = new WebSocket(u);
    await new Promise((res, rej) => { ws.onopen = res; ws.onerror = () => rej(new Error('ws')); });
    const c = new CDP(ws);
    ws.onmessage = ev => {
      const m = JSON.parse(ev.data);
      if (m.id && c.pend.has(m.id)) { const { res, rej } = c.pend.get(m.id); c.pend.delete(m.id);
        m.error ? rej(new Error(JSON.stringify(m.error))) : res(m.result); }
    };
    return c;
  }
  enviar(method, params = {}) {
    const id = ++this.id;
    return new Promise((res, rej) => {
      this.pend.set(id, { res, rej });
      this.ws.send(JSON.stringify({ id, method, params }));
      setTimeout(() => { if (this.pend.has(id)) { this.pend.delete(id); rej(new Error('timeout ' + method)); } }, 90000);
    });
  }
  async ev(expr) {
    const r = await this.enviar('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true });
    if (r.exceptionDetails) throw new Error('JS: ' + JSON.stringify(r.exceptionDetails).slice(0, 200));
    return r.result.value;
  }
}

const ESTADO = `(() => {
  const opts = sel => { const e = document.querySelector(sel); return e ? e.options.length : -1; };
  const val  = sel => { const e = document.querySelector(sel); return e ? e.value : '(no existe)'; };
  const txt  = sel => { const e = document.querySelector(sel); return e ? e.textContent.trim() : ''; };
  return {
    provincia: { opciones: opts('#provincia'), valor: val('#provincia') },
    canton:    { opciones: opts('#canton_filtro'), valor: val('#canton_filtro') },
    indicador: { opciones: opts('#indicador'), valor: val('#indicador') },
    fichaRotulo: txt('#ficha_rotulo'),
    fichaValor: txt('#ficha_valor'),
    fichaExtra: txt('#ficha_extra'),
    tituloDetalle: txt('#titulo_detalle'),
    filasDetalle: document.querySelectorAll('#detalle table tr').length,
    filasDT: document.querySelectorAll('#tabla tbody tr').length,
    filasDTInfo: txt('#tabla_info'),
    poligonosMapa: document.querySelectorAll('#mapa path.leaflet-interactive').length,
    canvasMapa: document.querySelectorAll('#mapa canvas').length,
    tiles: document.querySelectorAll('#mapa img.leaflet-tile').length,
    explicacion: txt('#explica_indicador').length,
    errores: (window.__errores || []).length
  };
})()`;

(async () => {
  const lineas = []; const log = s => { console.log(s); lineas.push(s); };
  const pruebas = [];
  const ok = (n, cond, det) => pruebas.push(`${cond ? 'PASS' : 'FAIL'} | ${n} | ${det}`);
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', `--remote-debugging-port=${PUERTO}`,
    `--user-data-dir=${PERFIL}`, '--remote-allow-origins=*', '--window-size=1440,1100', 'about:blank'], { stdio: 'ignore' });
  try {
    const cdp = await CDP.conectar(await objetivo());
    await cdp.enviar('Page.enable'); await cdp.enviar('Runtime.enable');
    await cdp.enviar('Page.addScriptToEvaluateOnNewDocument', {
      source: 'window.__errores=[];window.addEventListener("error",e=>window.__errores.push(String(e.message)));'
    });
    log(`URL: ${URL_APP}`);
    await cdp.enviar('Page.navigate', { url: URL_APP });

    // Espera compuesta: los controles aparecen antes que las salidas del
    // servidor (mapa, tabla, fichas). Hay que esperar a las dos cosas.
    let listo = false;
    for (let i = 0; i < 120; i++) {
      listo = await cdp.ev(`(() => {
        const prov  = document.querySelectorAll('#provincia option').length;
        const ind   = document.querySelectorAll('#indicador option').length;
        const filas = document.querySelectorAll('#tabla tbody tr').length;
        const polis = document.querySelectorAll('#mapa path.leaflet-interactive').length;
        return prov > 1 && ind > 1 && filas > 0 && polis > 50;
      })()`);
      if (listo) break;
      await esperar(1000);
    }
    log(`\nAplicación lista (controles y salidas renderizados): ${listo}`);
    await esperar(2500);

    const inicial = await cdp.ev(ESTADO);
    log(''); log('== 1. ESTADO INICIAL =='); log(JSON.stringify(inicial, null, 2));

    // Filtro encadenado: provincia
    await cdp.ev(`(() => { const s=document.querySelector('#provincia'); s.value='Azuay'; s.dispatchEvent(new Event('change',{bubbles:true})); return true; })()`);
    await esperar(4000);
    const trasProv = await cdp.ev(ESTADO);
    log(''); log('== 2. TRAS ELEGIR PROVINCIA Azuay ==');
    log(JSON.stringify({ opcionesCanton: trasProv.canton.opciones, fichaRotulo: trasProv.fichaRotulo, filasDT: trasProv.filasDT, poligonos: trasProv.poligonosMapa }, null, 2));

    // Filtro encadenado: cantón
    await cdp.ev(`(() => { const s=document.querySelector('#canton_filtro'); s.value='0101'; s.dispatchEvent(new Event('change',{bubbles:true})); return true; })()`);
    await esperar(4000);
    const trasCanton = await cdp.ev(ESTADO);
    log(''); log('== 3. TRAS ELEGIR CANTON 0101 (Cuenca) ==');
    log(JSON.stringify({ valorCanton: trasCanton.canton.valor, fichaRotulo: trasCanton.fichaRotulo, fichaValor: trasCanton.fichaValor, fichaExtra: trasCanton.fichaExtra, filasDetalle: trasCanton.filasDetalle }, null, 2));

    // Cambio de indicador
    await cdp.ev(`(() => { const s=document.querySelector('#indicador'); s.value='pobreza_fgt0'; s.dispatchEvent(new Event('change',{bubbles:true})); return true; })()`);
    await esperar(3500);
    const trasInd = await cdp.ev(ESTADO);
    log(''); log('== 4. TRAS CAMBIAR INDICADOR ==');
    log(JSON.stringify({ indicador: trasInd.indicador.valor, fichaValor: trasInd.fichaValor, explicacion: trasInd.explicacion }, null, 2));

    const shot = await cdp.enviar('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true });
    fs.writeFileSync(path.join(path.dirname(SALIDA), 'shiny_escritorio.png'), Buffer.from(shot.data, 'base64'));
    log(''); log('Captura de la app Shiny guardada.');

    ok('shiny-provincias-cargadas', inicial.provincia.opciones === 25, `opciones de provincia: ${inicial.provincia.opciones} (esperado 25)`);
    ok('shiny-cantones-nacional', inicial.canton.opciones === 222, `opciones de cantón: ${inicial.canton.opciones} (esperado 222)`);
    ok('shiny-indicadores', inicial.indicador.opciones === 11, `opciones de indicador: ${inicial.indicador.opciones} (esperado 11)`);
    ok('shiny-tabla-inicial', inicial.filasDT === 12, `filas visibles de la tabla (paginada a 12): ${inicial.filasDT}`);
    ok('shiny-filtro-provincia-encadena', trasProv.canton.opciones === 16, `cantones de Azuay: ${trasProv.canton.opciones} (esperado 15 + "todos")`);
    ok('shiny-filtro-canton-enfoca', /Cuenca/.test(trasCanton.fichaRotulo), `rotulo de la ficha: ${trasCanton.fichaRotulo}`);
    ok('shiny-ficha-con-valor', trasCanton.fichaValor !== '' && trasCanton.fichaValor !== '—', `valor de la ficha: ${trasCanton.fichaValor}`);
    ok('shiny-detalle-con-filas', trasCanton.filasDetalle >= 12, `filas del detalle: ${trasCanton.filasDetalle}`);
    ok('shiny-cambio-indicador', trasInd.fichaValor !== trasCanton.fichaValor, `valor antes: ${trasCanton.fichaValor} | después: ${trasInd.fichaValor}`);
    ok('shiny-explicacion-presente', inicial.explicacion > 80, `caracteres de explicación: ${inicial.explicacion}`);
    ok('shiny-mapa-dibujado', inicial.poligonosMapa > 100 || inicial.canvasMapa > 0, `polígonos SVG: ${inicial.poligonosMapa}, canvas: ${inicial.canvasMapa}`);
    ok('shiny-sin-errores-js', inicial.errores === 0, `errores capturados: ${inicial.errores}`);

    log(''); log('== RESUMEN ==');
    pruebas.forEach(p => log(p));
    const fallos = pruebas.filter(p => p.startsWith('FAIL')).length;
    log(''); log(`TOTAL: ${pruebas.length} comprobaciones | PASS: ${pruebas.length - fallos} | FAIL: ${fallos}`);
    fs.writeFileSync(SALIDA, lineas.join('\n'), 'utf8');
    chrome.kill();
    process.exit(fallos === 0 ? 0 : 1);
  } catch (e) {
    log('ERROR: ' + e.message);
    fs.writeFileSync(SALIDA, lineas.join('\n'), 'utf8');
    chrome.kill(); process.exit(2);
  }
})();
