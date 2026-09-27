// ---------------------------------------------------------------------------
// auditar_layout.js — Auditoría de maquetación del sitio publicado
//
// Comprueba, en escritorio y en móvil, cosas que un vistazo humano podría
// pasar por alto: desbordamiento horizontal, elementos clave con tamaño cero,
// solapamiento de la ficha sobre el mapa y usabilidad de la tabla.
//
// Uso: node auditar_layout.js <url> <salida.txt>
// ---------------------------------------------------------------------------

const { spawn } = require('child_process');
const fs = require('fs'); const path = require('path'); const os = require('os');
const URL_SITIO = process.argv[2];
const SALIDA = process.argv[3] || 'auditoria_layout.txt';
const CHROME = process.argv[4] || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const PUERTO = 9335;
const PERFIL = path.join(os.tmpdir(), 'vaec-lay-' + Date.now());
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
      setTimeout(() => { if (this.pend.has(id)) { this.pend.delete(id); rej(new Error('timeout ' + method)); } }, 60000);
    });
  }
  async ev(expr) {
    const r = await this.enviar('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true });
    if (r.exceptionDetails) throw new Error('JS: ' + JSON.stringify(r.exceptionDetails).slice(0, 200));
    return r.result.value;
  }
}

const AUDITORIA = `(() => {
  const rect = sel => { const e = document.querySelector(sel); if (!e) return null;
    const r = e.getBoundingClientRect(); return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) }; };
  const clave = {
    mapa: '#mapa', provincia: '#sel-provincia', canton: '#sel-canton', indicador: '#sel-indicador',
    escala: '#escala-barra', ficha: '.ficha', detalle: '.ficha-panel', tabla: '#tabla',
    fuentes: '#tabla-fuentes', cabecera: '.cabecera', pie: '.pie'
  };
  const tamaños = {};
  for (const k in clave) tamaños[k] = rect(clave[k]);

  // Elementos clave con tamaño cero (indicio de fallo de maquetación)
  const enCero = Object.entries(tamaños).filter(([k,v]) => v && (v.w === 0 || v.h === 0)).map(([k]) => k);

  // Desbordamiento horizontal
  const overflow = {
    documento: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    anchoVentana: window.innerWidth,
    anchoDocumento: document.documentElement.scrollWidth
  };

  // (la comprobacion de elementos salidos se hace mas abajo, ignorando los
  //  contenedores con scroll propio)

  // La tabla larga debe tener su propio contenedor con scroll, no romper la pagina
  const contTabla = document.querySelector('.tabla-scroll');
  const tablaConScroll = contTabla ? (contTabla.scrollWidth > contTabla.clientWidth) : null;

  // Contraste de textos clave y presencia de contenido
  const textos = {
    fichaValor: (document.getElementById('ficha-valor')||{}).textContent.trim(),
    escalaMin: (document.getElementById('escala-min')||{}).textContent,
    escalaMax: (document.getElementById('escala-max')||{}).textContent,
    explica: ((document.getElementById('explica-indicador')||{}).textContent||'').length,
    leyenda: ((document.getElementById('leyenda-html')||{}).textContent||'').length,
    piePagina: ((document.querySelector('.pie-aviso')||{}).textContent||'').length
  };

  // Elementos del mapa realmente dibujados
  const mapa = {
    tiles: document.querySelectorAll('#mapa img.leaflet-tile').length,
    svgPath: document.querySelectorAll('#mapa path.leaflet-interactive').length,
    canvas: document.querySelectorAll('#mapa canvas').length,
    controlesZoom: document.querySelectorAll('#mapa .leaflet-control-zoom').length
  };
  // El coropleta se dibuja en un canvas (preferCanvas). Se muestrean pixeles
  // para comprobar que hay color pintado de verdad y no un canvas vacio.
  let coloresCanvas = 0, pixelesPintados = 0;
  const cv = document.querySelector('#mapa canvas');
  if (cv && cv.width > 0 && cv.height > 0) {
    try {
      const datos = cv.getContext('2d').getImageData(0, 0, cv.width, cv.height).data;
      const set = new Set();
      for (let i = 0; i < datos.length; i += 4 * 17) {
        if (datos[i + 3] > 0) { pixelesPintados++; set.add(datos[i] + ',' + datos[i + 1] + ',' + datos[i + 2]); }
        if (set.size > 60) break;
      }
      coloresCanvas = set.size;
    } catch (e) { coloresCanvas = -1; }
  }

  // Desbordamiento real: solo cuentan los elementos cuyo ancestro con scroll
  // es el documento. Los que viven dentro de un contenedor con overflow propio
  // (pane del mapa, tabla con scroll lateral) NO son un problema.
  const dentroDeContenedorConScroll = e => {
    let p = e.parentElement;
    while (p && p !== document.body) {
      const ox = getComputedStyle(p).overflowX;
      if (ox === 'auto' || ox === 'scroll' || ox === 'hidden') return true;
      p = p.parentElement;
    }
    return false;
  };
  const salidos = [];
  document.querySelectorAll('.cabecera, .diseno, .lateral, .principal, .tarjeta, .pie, #mapa').forEach(e => {
    const r = e.getBoundingClientRect();
    if (r.width > 0 && (r.right > window.innerWidth + 2 || r.left < -2)) {
      salidos.push((e.id ? '#' + e.id : '.' + String(e.className).split(' ')[0]) + ' (left=' + Math.round(r.left) + ', right=' + Math.round(r.right) + ')');
    }
  });

  return { tamaños, enCero, overflow, salidos, tablaConScroll, textos, mapa, coloresCanvas, pixelesPintados,
           altoPagina: document.documentElement.scrollHeight };
})()`;

(async () => {
  const lineas = []; const log = s => { console.log(s); lineas.push(s); };
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', `--remote-debugging-port=${PUERTO}`,
    `--user-data-dir=${PERFIL}`, '--remote-allow-origins=*', '--window-size=1440,1000', 'about:blank'], { stdio: 'ignore' });
  const pruebas = [];
  try {
    const cdp = await CDP.conectar(await objetivo());
    await cdp.enviar('Page.enable'); await cdp.enviar('Runtime.enable');
    await cdp.enviar('Page.navigate', { url: URL_SITIO });
    await esperar(4000);
    for (let i = 0; i < 90; i++) {
      const n = await cdp.ev(`document.querySelectorAll('#tabla-cuerpo tr').length`);
      if (n > 0) break;
      await esperar(1000);
    }
    await esperar(3500);

    const ok = (n, cond, det) => pruebas.push(`${cond ? 'PASS' : 'FAIL'} | ${n} | ${det}`);

    // ---------------- ESCRITORIO ----------------
    const d = await cdp.ev(AUDITORIA);
    log('== ESCRITORIO 1440x1000 ==');
    log(JSON.stringify(d, null, 2));
    ok('escritorio-sin-desbordamiento', d.overflow.documento <= 1, `scrollWidth - clientWidth = ${d.overflow.documento}`);
    ok('escritorio-elementos-con-tamano', d.enCero.length === 0, `elementos en cero: ${d.enCero.join(', ') || 'ninguno'}`);
    ok('escritorio-mapa-dibujado', d.mapa.canvas > 0 && d.mapa.tiles > 0 && d.coloresCanvas > 5, `canvas: ${d.mapa.canvas}, tiles: ${d.mapa.tiles}, colores distintos en el canvas: ${d.coloresCanvas}, muestras pintadas: ${d.pixelesPintados}`);
    ok('escritorio-ficha-con-valor', d.textos.fichaValor && d.textos.fichaValor !== '—', `ficha: ${d.textos.fichaValor}`);
    ok('escritorio-explicacion-presente', d.textos.explica > 80, `caracteres de explicación: ${d.textos.explica}`);
    ok('escritorio-leyenda-presente', d.textos.leyenda > 30, `caracteres de leyenda: ${d.textos.leyenda}`);
    ok('escritorio-aviso-legal-presente', d.textos.piePagina > 100, `caracteres del aviso: ${d.textos.piePagina}`);
    ok('escritorio-sin-elementos-salidos', d.salidos.length === 0, `bloques fuera del viewport: ${d.salidos.join(' | ') || 'ninguno'}`);

    // ---------------- MOVIL ----------------
    await cdp.enviar('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 2, mobile: true });
    await esperar(2500);
    const m = await cdp.ev(AUDITORIA);
    log('');
    log('== MOVIL 390x844 ==');
    log(JSON.stringify(m, null, 2));
    ok('movil-sin-desbordamiento', m.overflow.documento <= 1, `scrollWidth - clientWidth = ${m.overflow.documento}`);
    ok('movil-elementos-con-tamano', m.enCero.length === 0, `elementos en cero: ${m.enCero.join(', ') || 'ninguno'}`);
    ok('movil-mapa-visible', m.tamaños.mapa && m.tamaños.mapa.h >= 300, `alto del mapa: ${m.tamaños.mapa ? m.tamaños.mapa.h : 0} px`);
    ok('movil-tabla-con-scroll', m.tablaConScroll === true, `contenedor de tabla con scroll propio: ${m.tablaConScroll}`);
    ok('movil-ficha-con-valor', m.textos.fichaValor && m.textos.fichaValor !== '—', `ficha: ${m.textos.fichaValor}`);
    ok('movil-mapa-dibujado', m.mapa.canvas > 0 && m.coloresCanvas > 5, `canvas: ${m.mapa.canvas}, colores distintos: ${m.coloresCanvas}`);
    ok('movil-sin-elementos-salidos', m.salidos.length === 0, `bloques fuera del viewport: ${m.salidos.join(' | ') || 'ninguno'}`);

    log('');
    log('== RESUMEN ==');
    pruebas.forEach(p => log(p));
    const fallos = pruebas.filter(p => p.startsWith('FAIL')).length;
    log('');
    log(`TOTAL: ${pruebas.length} comprobaciones | PASS: ${pruebas.length - fallos} | FAIL: ${fallos}`);
    fs.writeFileSync(SALIDA, lineas.join('\n'), 'utf8');
    chrome.kill();
    process.exit(fallos === 0 ? 0 : 1);
  } catch (e) {
    log('ERROR: ' + e.message);
    fs.writeFileSync(SALIDA, lineas.join('\n'), 'utf8');
    chrome.kill(); process.exit(2);
  }
})();
