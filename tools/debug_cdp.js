const { spawn } = require('child_process');
const fs = require('fs'); const path = require('path'); const os = require('os');
const URL_SITIO = process.argv[2];
const CHROME = process.argv[3];
const PUERTO = 9334;
const PERFIL = path.join(os.tmpdir(), 'vaec-dbg-' + Date.now());
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
    if (r.exceptionDetails) return 'EXCEPCION: ' + JSON.stringify(r.exceptionDetails).slice(0, 300);
    return r.result.value;
  }
}

(async () => {
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', `--remote-debugging-port=${PUERTO}`,
    `--user-data-dir=${PERFIL}`, '--remote-allow-origins=*', '--window-size=1440,1000', 'about:blank'], { stdio: 'ignore' });
  const cdp = await CDP.conectar(await objetivo());
  await cdp.enviar('Page.enable'); await cdp.enviar('Runtime.enable');
  await cdp.enviar('Page.navigate', { url: URL_SITIO + '?dbg=' + Date.now() });
  await esperar(4000);
  for (let i = 0; i < 60; i++) {
    const n = await cdp.ev(`document.querySelectorAll('#sel-provincia option').length`);
    if (n > 1) break;
    await esperar(1000);
  }
  console.log('app.js cargado contiene el fix:',
    await cdp.ev(`fetch('./app.js').then(r=>r.text()).then(t=>t.includes("selProv.value = ''"))`));
  console.log('boton existe:', await cdp.ev(`!!document.getElementById('btn-pais')`));
  console.log('valor inicial provincia:', JSON.stringify(await cdp.ev(`document.getElementById('sel-provincia').value`)));

  await cdp.ev(`(() => { const s=document.getElementById('sel-provincia'); s.value='01'; s.dispatchEvent(new Event('change')); return true; })()`);
  await esperar(1200);
  console.log('tras elegir Azuay:', JSON.stringify(await cdp.ev(`document.getElementById('sel-provincia').value`)));

  console.log('ejecutando click en btn-pais ->', await cdp.ev(`(() => { try { document.getElementById('btn-pais').click(); return 'ok'; } catch(e) { return 'error: '+e.message; } })()`));
  console.log('valor provincia inmediatamente despues:', JSON.stringify(await cdp.ev(`document.getElementById('sel-provincia').value`)));
  await esperar(1500);
  console.log('valor provincia 1.5s despues:', JSON.stringify(await cdp.ev(`document.getElementById('sel-provincia').value`)));
  console.log('opciones canton:', await cdp.ev(`document.querySelectorAll('#sel-canton option').length`));
  console.log('filas tabla:', await cdp.ev(`document.querySelectorAll('#tabla-cuerpo tr').length`));

  chrome.kill(); process.exit(0);
})().catch(e => { console.error('ERROR', e.message); process.exit(2); });
