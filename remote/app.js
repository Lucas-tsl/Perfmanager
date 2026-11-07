'use strict';
/* PerfDeck : télécommande OBS + PerfManager pour téléphone */

/* ------------------------------------------------------------------ SHA-256
   Le navigateur bloque crypto.subtle en http sur le réseau local,
   d'où cette implémentation pour l'authentification OBS. */
// @sha-start
const SHA_K = new Uint32Array([
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2]);
function sha256(msg) {
  const r = (x, n) => (x >>> n) | (x << (32 - n));
  const len = msg.length, nb = ((len + 9 + 63) >> 6) << 6;
  const m = new Uint8Array(nb); m.set(msg); m[len] = 0x80;
  const dv = new DataView(m.buffer);
  dv.setUint32(nb - 8, Math.floor(len / 0x20000000));
  dv.setUint32(nb - 4, (len << 3) >>> 0);
  const H = new Uint32Array([0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19]);
  const w = new Uint32Array(64);
  for (let o = 0; o < nb; o += 64) {
    for (let i = 0; i < 16; i++) w[i] = dv.getUint32(o + i * 4);
    for (let i = 16; i < 64; i++) {
      const a = w[i - 15], b = w[i - 2];
      w[i] = w[i - 16] + (r(a, 7) ^ r(a, 18) ^ (a >>> 3)) + w[i - 7] + (r(b, 17) ^ r(b, 19) ^ (b >>> 10));
    }
    let a = H[0], b = H[1], c = H[2], d = H[3], e = H[4], f = H[5], g = H[6], h = H[7];
    for (let i = 0; i < 64; i++) {
      const t1 = (h + (r(e, 6) ^ r(e, 11) ^ r(e, 25)) + ((e & f) ^ (~e & g)) + SHA_K[i] + w[i]) | 0;
      const t2 = ((r(a, 2) ^ r(a, 13) ^ r(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) | 0;
      h = g; g = f; f = e; e = (d + t1) | 0; d = c; c = b; b = a; a = (t1 + t2) | 0;
    }
    H[0] += a; H[1] += b; H[2] += c; H[3] += d; H[4] += e; H[5] += f; H[6] += g; H[7] += h;
  }
  const out = new Uint8Array(32), ov = new DataView(out.buffer);
  for (let i = 0; i < 8; i++) ov.setUint32(i * 4, H[i]);
  return out;
}
const b64 = bytes => btoa(String.fromCharCode.apply(null, bytes));
function obsAuth(password, salt, challenge) {
  const enc = new TextEncoder();
  const secret = b64(sha256(enc.encode(password + salt)));
  return b64(sha256(enc.encode(secret + challenge)));
}
// @sha-end

/* ------------------------------------------------------------------ Outils */
const $ = s => document.querySelector(s);
const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
// Vibration : moteur natif dans l'appli Android, sinon API du navigateur
const vib = p => { try { if (window.PerfDeckNative) PerfDeckNative.vibrate(JSON.stringify([].concat(p))); else if (navigator.vibrate) navigator.vibrate(p); } catch (e) {} };
const buzz = () => vib(12);
const pad = n => String(n).padStart(2, '0');
const fmtTime = ms => { const s = Math.floor((ms || 0) / 1000); return `${pad(Math.floor(s / 3600))}:${pad(Math.floor(s % 3600 / 60))}:${pad(s % 60)}`; };
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

function toast(msg, kind) {
  const t = $('#toast');
  t.textContent = msg;
  t.className = 'toast show ' + (kind || '');
  clearTimeout(toast.t);
  toast.t = setTimeout(() => { t.className = 'toast'; }, 2800);
}

const I = {
  live: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="2.5" fill="currentColor"/><path d="M8 8a5.7 5.7 0 0 0 0 8M16 8a5.7 5.7 0 0 1 0 8M5.2 5.2a9.6 9.6 0 0 0 0 13.6M18.8 5.2a9.6 9.6 0 0 1 0 13.6"/></svg>',
  stop: '<svg viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="6" width="12" height="12" rx="2.5"/></svg>',
  rec: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="7" fill="currentColor"/></svg>',
  pause: '<svg viewBox="0 0 24 24" fill="currentColor"><rect x="6.5" y="5" width="4" height="14" rx="1.2"/><rect x="13.5" y="5" width="4" height="14" rx="1.2"/></svg>',
  play: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M8 5.5v13a1 1 0 0 0 1.5.9l10-6.5a1 1 0 0 0 0-1.7l-10-6.5A1 1 0 0 0 8 5.5z"/></svg>',
  clip: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M13 2 4 14h7l-1 8 9-12h-7z"/></svg>',
  mic: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/></svg>',
  micOff: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3M3 3l18 18"/></svg>',
  spk: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 9h4l5-4v14l-5-4H4z"/><path d="M16.5 9a4 4 0 0 1 0 6M19 6.5a7.5 7.5 0 0 1 0 11"/></svg>',
  eye: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></svg>',
  eyeOff: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.6 5.1A10.4 10.4 0 0 1 12 5c6.4 0 10 7 10 7a17.6 17.6 0 0 1-2.4 3.3M6.6 6.6C3.9 8.4 2 12 2 12s3.6 7 10 7a9.7 9.7 0 0 0 5.4-1.6M3 3l18 18M9.9 9.9a3 3 0 0 0 4.2 4.2"/></svg>',
  warn: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0zM12 9v4M12 17h.01"/></svg>',
  spkOff: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 9h4l5-4v14l-5-4H4z"/><path d="M17 9l5 6M22 9l-5 6"/></svg>'
};

/* ------------------------------------------------------------------ Réglages */
const KEY = 'perfdeck';
const ALERT_DEFAULTS = { vibrate: true, drop: true, dropPct: 1, gpu: true, gpuTemp: 80, cpu: true, cpuPct: 90, mic: true, micSec: 30, link: true };
function settings() {
  let s = { obsHost: location.hostname || '', obsPort: 4455, obsPassword: '', token: '' };
  try {
    // Appli Android : réglages gardés par l'appli, identiques à la maison et via Meshnet
    const raw = (window.PerfDeckNative && PerfDeckNative.loadSettings()) || localStorage.getItem(KEY) || '{}';
    s = Object.assign(s, JSON.parse(raw));
  } catch (e) {}
  s.alerts = Object.assign({}, ALERT_DEFAULTS, s.alerts || {});
  if (window.PerfDeckNative) s.obsHost = location.hostname;   // OBS suit l'adresse utilisée (Wi-Fi ou Meshnet)
  return s;
}
function saveSettings(s) {
  try { localStorage.setItem(KEY, JSON.stringify(s)); } catch (e) {}
  try { if (window.PerfDeckNative) PerfDeckNative.saveSettings(JSON.stringify(s)); } catch (e) {}
}
(() => {
  const k = new URLSearchParams(location.search).get('k');
  if (k) { const s = settings(); s.token = k; saveSettings(s); history.replaceState(null, '', location.pathname); }
})();

/* ------------------------------------------------------------------ Feuilles (popups) */
let sheetClose = null;
function openSheet(html, onClose) {
  $('#sheetBody').innerHTML = html;
  $('#sheet').classList.add('open');
  sheetClose = onClose || null;
}
function closeSheet(result) {
  $('#sheet').classList.remove('open');
  const cb = sheetClose; sheetClose = null;
  if (cb) cb(result);
}
$('#sheet .bd').addEventListener('click', () => closeSheet(false));

function confirmSheet(title, text, okLabel, danger) {
  return new Promise(res => {
    openSheet(`<h3>${esc(title)}</h3><p class="sheet-p">${esc(text || '')}</p>
      <div class="sheet-actions"><button class="btn ghost" data-a="no">Annuler</button>
      <button class="btn ${danger ? 'danger' : 'primary'}" data-a="ok">${esc(okLabel)}</button></div>`, res);
    $('#sheetBody').onclick = e => {
      const a = e.target.closest('[data-a]');
      if (a) { buzz(); closeSheet(a.dataset.a === 'ok'); }
    };
  });
}

function optRow(id, on, label, sub, numId, numVal, unit) {
  return `<div class="opt"><div class="n">${label}${sub ? `<small>${sub}</small>` : ''}</div>` +
    (numId ? `<input class="num" id="${numId}" inputmode="decimal" value="${esc(numVal)}"><span class="u">${unit}</span>` : '') +
    `<button class="tog${on ? ' on' : ''}" id="${id}" type="button" aria-label="${esc(label)}"><span class="sw"></span></button></div>`;
}

function openSettings() {
  const s = settings(), a = s.alerts;
  openSheet(`<h3>Réglages</h3>
    <p class="sheet-p">OBS : Outils → Paramètres du serveur WebSocket → Afficher les informations de connexion.</p>
    <div class="split">
      <div class="field"><label>Adresse du PC</label><input id="fHost" inputmode="url" autocomplete="off" value="${esc(s.obsHost)}"></div>
      <div class="field"><label>Port OBS</label><input id="fPort" inputmode="numeric" value="${esc(s.obsPort)}"></div>
    </div>
    <div class="field"><label>Mot de passe OBS</label>
      <div class="pw"><input id="fPwd" type="password" autocomplete="off" value="${esc(s.obsPassword)}">
        <button type="button" id="pwEye" aria-label="Afficher le mot de passe">${I.eye}</button></div>
      <div class="pwacts"><button class="btn" type="button" id="obsAuto">Récupérer depuis le PC</button>
        ${window.PerfDeckNative ? '<button class="btn" type="button" id="obsScan">Scanner le QR d\'OBS</button>' : ''}</div>
      <small>Récupéré automatiquement depuis OBS sur le PC. Sinon : OBS → Outils → Paramètres du serveur WebSocket → Afficher les informations de connexion.</small></div>
    <div class="field"><label>Code d'accès PC</label><input id="fTok" autocomplete="off" value="${esc(s.token)}">
      <small>Rempli automatiquement en scannant le QR code affiché par PerfRemote sur le PC.</small></div>
    <div class="sep">Alertes</div>
    ${optRow('aDrop', a.drop, 'Images perdues', 'Réseau, encodage ou rendu OBS', 'aDropPct', a.dropPct, '%')}
    ${optRow('aGpu', a.gpu, 'Température GPU', 'RTX 4060', 'aGpuTemp', a.gpuTemp, '°C')}
    ${optRow('aCpu', a.cpu, 'Processeur saturé', 'Plus de 10 secondes', 'aCpuPct', a.cpuPct, '%')}
    ${optRow('aMic', a.mic, 'Micro coupé', 'Tu parles micro coupé, ou coupé en live depuis', 'aMicSec', a.micSec, 's')}
    ${optRow('aLink', a.link, 'Connexion perdue', 'Stream qui se reconnecte, OBS ou PC injoignable')}
    ${optRow('aVib', a.vibrate, 'Vibrer', 'En plus de la bannière')}
    <button class="btn wide" id="aTest" type="button" style="margin:10px 0 18px">Tester une alerte</button>
    ${window.PerfDeckNative ? '<button class="btn wide" id="aServer" type="button" style="margin:-8px 0 18px">Changer de PC</button>' : ''}
    <div class="sheet-actions"><button class="btn ghost" data-a="no">Annuler</button><button class="btn primary" data-a="ok">Enregistrer</button></div>`);
  $('#sheetBody').onclick = e => {
    const t = e.target.closest('.tog');
    if (t) { buzz(); t.classList.toggle('on'); return; }
    if (e.target.closest('#aTest')) { Alerts.test(); return; }
    if (e.target.closest('#pwEye')) {
      const f = $('#fPwd'), show = f.type === 'password';
      f.type = show ? 'text' : 'password';
      $('#pwEye').innerHTML = show ? I.eyeOff : I.eye;
      return;
    }
    if (e.target.closest('#obsAuto')) { buzz(); autoObs(true); return; }
    if (e.target.closest('#obsScan')) { buzz(); closeSheet(); PerfDeckNative.scanObsQr(); return; }
    if (e.target.closest('#aServer')) { closeSheet(); PerfDeckNative.changeServer(); return; }
    const b = e.target.closest('[data-a]');
    if (!b) return;
    buzz();
    if (b.dataset.a === 'ok') {
      const n = settings();
      n.obsHost = $('#fHost').value.trim();
      n.obsPort = parseInt($('#fPort').value, 10) || 4455;
      n.obsPassword = $('#fPwd').value;
      n.token = $('#fTok').value.trim();
      const on = id => $('#' + id).classList.contains('on');
      const num = (id, def) => { const v = parseFloat(String($('#' + id).value).replace(',', '.')); return isFinite(v) && v > 0 ? v : def; };
      n.alerts = { vibrate: on('aVib'), drop: on('aDrop'), dropPct: num('aDropPct', 1), gpu: on('aGpu'), gpuTemp: num('aGpuTemp', 80),
        cpu: on('aCpu'), cpuPct: num('aCpuPct', 90), mic: on('aMic'), micSec: num('aMicSec', 30), link: on('aLink') };
      saveSettings(n);
      if (n.obsHost !== s.obsHost || n.obsPort !== s.obsPort || n.obsPassword !== s.obsPassword || !OBS.ok) { OBS.authFailed = false; OBS.reconnect(); }
      if (n.token !== s.token || !PC.ok) { PC.profiles = []; Games.list = null; PC.refresh(); }
      Alerts.clearAll();
      toast('Réglages enregistrés', 'ok');
    }
    closeSheet();
  };
}
$('#btnSettings').addEventListener('click', () => { buzz(); openSettings(); });

/* ------------------------------------------------------------------ Onglets */
let currentTab = 'obs';
function showTab(name) {
  currentTab = name;
  document.querySelectorAll('.tabs button').forEach(b => b.classList.toggle('active', b.dataset.tab === name));
  document.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t.id === 'tab-' + name));
  try { localStorage.setItem(KEY + '-tab', name); } catch (e) {}
  if (name === 'pc') PC.refresh();
  if (name === 'games') Games.load();
  OBS.updateSubs();
}
document.querySelectorAll('.tabs button').forEach(b => b.addEventListener('click', () => { buzz(); showTab(b.dataset.tab); }));

/* ------------------------------------------------------------------ OBS WebSocket v5 */
const OBS = {
  ws: null, ok: false, id: 0, pending: new Map(), timer: null, authFailed: false,
  connect() {
    if (this.ws && this.ws.readyState <= 1) return;
    const s = settings();
    // Par défaut : OBS à travers PerfRemote (même chemin que l'onglet PC, aucun pare-feu à régler)
    const url = s.obsDirect
      ? `ws://${s.obsHost}:${s.obsPort || 4455}`
      : `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/obs-ws?k=${encodeURIComponent(s.token || '')}`;
    let ws;
    try { ws = new WebSocket(url); }
    catch (e) { obsNotice('down'); this.schedule(); return; }
    this.ws = ws;
    // Jamais d'attente muette : sans réponse en 8 s, on abandonne et on réessaie
    clearTimeout(this.openTimer);
    this.openTimer = setTimeout(() => { if (this.ws === ws && !this.ok) { try { ws.close(); } catch (e) {} } }, 8000);
    ws.onmessage = ev => { try { this.onMessage(JSON.parse(ev.data)); } catch (e) {} };
    ws.onclose = ev => {
      if (this.ws !== ws) return;
      this.ok = false; this.ws = null;
      this.pending.forEach(p => p.rej(new Error('OBS déconnecté'))); this.pending.clear();
      setPill('obs', false);
      Meters.reset();
      if (st.live) Alerts.raise('obs', 'Connexion à OBS perdue pendant le live', 'bad', 'link');
      if (ev.code === 4009) { this.authFailed = true; obsNotice('auth'); autoObs(); return; }
      if (ev.code === 4100 || this.relayDown) { this.relayDown = false; obsNotice('notrunning'); autoObs(); this.schedule(); return; }
      obsNotice('down');
      autoObs();
      this.schedule();
    };
  },
  schedule() { clearTimeout(this.timer); this.timer = setTimeout(() => this.connect(), 3000); },
  wantMeters() { return document.visibilityState === 'visible' && currentTab === 'obs'; },
  subMask(m) { return 1 | 4 | 8 | 64 | 128 | (m ? 65536 : 0); },
  updateSubs() {
    if (!this.ok || !this.ws) return;
    const m = this.wantMeters();
    if (m === this.metersOn) return;
    this.metersOn = m;
    try { this.ws.send(JSON.stringify({ op: 3, d: { eventSubscriptions: this.subMask(m) } })); } catch (e) {}
    if (!m) Meters.reset();
  },
  reconnect() {
    clearTimeout(this.timer);
    if (this.ws) { const w = this.ws; this.ws = null; try { w.close(); } catch (e) {} }
    this.ok = false; setPill('obs', false);
    this.connect();
  },
  onMessage(m) {
    // Message du relais PerfRemote : OBS fermé ou serveur WebSocket désactivé sur le PC
    if (m.op === -1) { this.relayDown = true; obsNotice('notrunning'); autoObs(); try { this.ws.close(); } catch (e) {} return; }
    if (m.op === 0) {
      this.metersOn = this.wantMeters();
      const d = { rpcVersion: 1, eventSubscriptions: this.subMask(this.metersOn) };
      const a = m.d.authentication;
      if (a) d.authentication = obsAuth(settings().obsPassword || '', a.salt, a.challenge);
      this.ws.send(JSON.stringify({ op: 1, d }));
    } else if (m.op === 2) {
      this.ok = true;
      setPill('obs', true);
      Alerts.prevStats = null;
      Alerts.clear('obs');
      obsNotice(null);
      loadAll();
    } else if (m.op === 7) {
      const p = this.pending.get(m.d.requestId);
      if (!p) return;
      this.pending.delete(m.d.requestId);
      const st = m.d.requestStatus || {};
      if (st.result) p.res(m.d.responseData || {});
      else { const e = new Error(st.comment || 'Erreur OBS (' + st.code + ')'); e.code = st.code; p.rej(e); }
    } else if (m.op === 5) {
      onObsEvent(m.d.eventType, m.d.eventData || {});
    }
  },
  req(type, data) {
    return new Promise((res, rej) => {
      if (!this.ok || !this.ws) { rej(new Error('OBS non connecté')); return; }
      const id = 'r' + (++this.id);
      this.pending.set(id, { res, rej });
      this.ws.send(JSON.stringify({ op: 6, d: { requestType: type, requestId: id, requestData: data || {} } }));
      setTimeout(() => { if (this.pending.has(id)) { this.pending.delete(id); rej(new Error('OBS ne répond pas')); } }, 8000);
    });
  }
};
async function run(type, data) {
  try { return await OBS.req(type, data); }
  catch (e) { toast(e.message, 'err'); return null; }
}

function setPill(which, on) {
  $(which === 'obs' ? '#pillObs' : '#pillPc').classList.toggle('on', on);
  if (which === 'obs') document.body.classList.toggle('off-obs', !on);
}

function obsNotice(kind) {
  const n = $('#obsNotice');
  if (!kind) { n.hidden = true; return; }
  const msg = {
    setup: "Indique l'adresse du PC dans les réglages pour connecter OBS.",
    down: "<b>OBS non connecté.</b> Le PC ne répond pas pour OBS : vérifie que PerfManager est à jour sur le PC. Nouvelle tentative automatique…",
    notrunning: "<b>OBS ne répond pas sur le PC.</b> Ouvre OBS, puis vérifie que le serveur WebSocket est activé (Outils → Paramètres du serveur WebSocket → Activer). Nouvelle tentative automatique…",
    auth: '<b>Mot de passe OBS refusé.</b> Touche « Récupérer depuis le PC » dans les réglages, ou copie-le depuis OBS (Outils → Paramètres du serveur WebSocket → Afficher les informations de connexion).',
    disabled: '<b>Le serveur WebSocket d\'OBS est désactivé.</b> Dans OBS : Outils → Paramètres du serveur WebSocket → coche « Activer le serveur WebSocket », puis OK.'
  }[kind];
  n.innerHTML = msg + '<br><button class="btn" id="obsFix">Ouvrir les réglages</button>';
  n.hidden = false;
  $('#obsFix').onclick = () => { buzz(); openSettings(); };
}

/* ------------------------------------------------------------------ Mot de passe OBS automatique */
// Le PC lit les réglages du serveur WebSocket d'OBS : rien à taper ni à scanner
let obsAutoDone = false;
async function autoObs(manual) {
  if (!manual && obsAutoDone) return false;
  let r;
  try { r = await PC.api('obs'); }
  catch (e) { if (manual) toast(e.message, 'err'); return false; }
  obsAutoDone = true;
  if (!r.found) { if (manual) toast('Réglages OBS introuvables sur le PC : OBS est-il installé et lancé une fois ?', 'err'); return false; }
  if (!r.enabled) {
    obsNotice('disabled');
    if (manual) toast('Active le serveur WebSocket dans OBS (Outils → Paramètres du serveur WebSocket)', 'err');
    return false;
  }
  const s = settings();
  const pw = r.authRequired ? (r.password || '') : '';
  const port = r.port || 4455;
  if (!manual && s.obsPassword === pw && +s.obsPort === port) return false;
  s.obsPassword = pw; s.obsPort = port;
  saveSettings(s);
  if ($('#fPwd')) { $('#fPwd').value = pw; $('#fPort').value = port; }
  toast('Mot de passe OBS récupéré depuis le PC', 'ok');
  OBS.authFailed = false;
  OBS.reconnect();
  return true;
}

/* ------------------------------------------------------------------ État OBS + rendu */
const st = { scene: null, scenes: [], items: [], audio: [], live: false, liveTime: 0, drop: null,
  rec: false, recPaused: false, recTime: 0, fps: null, cpu: null, replay: null };

async function loadAll() {
  await Promise.all([loadScenes(), loadAudio(), loadReplay()]);
  pollOutputs();
}

async function loadScenes() {
  try {
    const r = await OBS.req('GetSceneList');
    st.scenes = (r.scenes || []).slice().sort((a, b) => b.sceneIndex - a.sceneIndex).map(s => s.sceneName);
    st.scene = r.currentProgramSceneName;
    renderScenes();
    loadItems();
  } catch (e) {}
}

async function loadItems() {
  if (!st.scene) { st.items = []; renderItems(); return; }
  try {
    const r = await OBS.req('GetSceneItemList', { sceneName: st.scene });
    st.items = (r.sceneItems || []).slice().sort((a, b) => b.sceneItemIndex - a.sceneItemIndex)
      .map(i => ({ id: i.sceneItemId, name: i.sourceName, on: i.sceneItemEnabled }));
  } catch (e) { st.items = []; }
  renderItems();
}

async function loadAudio() {
  try {
    const r = await OBS.req('GetInputList');
    const list = (r.inputs || []).filter(i => /wasapi|audio|pulse|coreaudio|alsa/i.test(i.inputKind || i.unversionedInputKind || ''));
    st.audio = await Promise.all(list.map(async i => {
      const [m, v] = await Promise.all([
        OBS.req('GetInputMute', { inputName: i.inputName }).catch(() => ({ inputMuted: false })),
        OBS.req('GetInputVolume', { inputName: i.inputName }).catch(() => ({ inputVolumeDb: 0 }))
      ]);
      return { name: i.inputName, out: /output/i.test(i.inputKind || ''), muted: !!m.inputMuted, db: v.inputVolumeDb };
    }));
  } catch (e) { st.audio = []; }
  renderAudio();
}

async function loadReplay() {
  try { const r = await OBS.req('GetReplayBufferStatus'); st.replay = !!r.outputActive; }
  catch (e) { st.replay = null; }
  renderKeys();
}

let statsTick = 0;
async function pollOutputs() {
  if (!OBS.ok || document.visibilityState !== 'visible') return;
  try {
    const [s, r] = await Promise.all([OBS.req('GetStreamStatus'), OBS.req('GetRecordStatus')]);
    st.live = !!s.outputActive; st.liveTime = s.outputDuration || 0;
    st.drop = s.outputTotalFrames ? (s.outputSkippedFrames / s.outputTotalFrames * 100) : (st.live ? 0 : null);
    st.rec = !!r.outputActive; st.recPaused = !!r.outputPaused; st.recTime = r.outputDuration || 0;
    Alerts.onStream(s);
    if (statsTick++ % 3 === 0) {
      const g = await OBS.req('GetStats');
      st.fps = g.activeFps; st.cpu = g.cpuUsage;
      Alerts.onStats(g);
    }
    Alerts.checkMic();
  } catch (e) {}
  renderStatus();
  renderKeys();
}
setInterval(pollOutputs, 1000);

function keyHtml(icon, label) { return icon + `<span>${esc(label)}</span>`; }

function renderKeys() {
  const kl = $('#kLive'), kr = $('#kRec'), kp = $('#kPause'), kc = $('#kClip');
  kl.classList.toggle('on', st.live);
  kl.innerHTML = keyHtml(st.live ? I.stop : I.live, st.live ? 'Couper le live' : 'Lancer le live');
  kr.classList.toggle('on', st.rec);
  kr.innerHTML = keyHtml(st.rec ? I.stop : I.rec, st.rec ? 'Stop rec' : 'Enregistrer');
  kp.disabled = !st.rec;
  kp.classList.toggle('on', st.recPaused);
  kp.innerHTML = keyHtml(st.recPaused ? I.play : I.pause, st.recPaused ? 'Reprendre' : 'Pause rec');
  kc.disabled = st.replay === null;
  kc.classList.toggle('on', st.replay === true);
  kc.innerHTML = keyHtml(I.clip, st.replay === null ? 'Replay off' : (st.replay ? 'Clip !' : 'Activer replay'));
}

function renderStatus() {
  $('#chipLive').classList.toggle('on', st.live);
  $('#vLive').textContent = st.live ? fmtTime(st.liveTime) : 'Hors ligne';
  $('#chipRec').classList.toggle('on', st.rec);
  $('#vRec').textContent = st.rec ? (st.recPaused ? 'En pause' : fmtTime(st.recTime)) : 'Arrêté';
  $('#mFps').textContent = st.fps != null ? Math.round(st.fps) : '–';
  $('#mDrop').textContent = st.drop != null ? st.drop.toFixed(1) + ' %' : '–';
  $('#mCpu').textContent = st.cpu != null ? st.cpu.toFixed(1) + ' %' : '–';
}

function renderScenes() {
  $('#scenes').innerHTML = st.scenes.length
    ? st.scenes.map(n => `<button class="scene${n === st.scene ? ' on' : ''}" data-n="${esc(n)}"><span>${esc(n)}</span></button>`).join('')
    : '<div class="muted">Aucune scène</div>';
}
$('#scenes').addEventListener('click', e => {
  const b = e.target.closest('.scene');
  if (!b || b.dataset.n === st.scene) return;
  buzz();
  st.scene = b.dataset.n;
  renderScenes();
  run('SetCurrentProgramScene', { sceneName: b.dataset.n });
});

function renderItems() {
  $('#items').innerHTML = st.items.length
    ? st.items.map(i => `<button class="row tog${i.on ? ' on' : ''}" data-id="${i.id}"><span class="n">${esc(i.name)}</span><span class="sw"></span></button>`).join('')
    : '<div class="row muted">Aucune source dans cette scène</div>';
}
$('#items').addEventListener('click', e => {
  const b = e.target.closest('.tog');
  if (!b) return;
  const it = st.items.find(i => i.id === +b.dataset.id);
  if (!it) return;
  buzz();
  it.on = !it.on;
  renderItems();
  run('SetSceneItemEnabled', { sceneName: st.scene, sceneItemId: it.id, sceneItemEnabled: it.on });
});

const dbTxt = v => (v <= -60 ? '−∞ dB' : v.toFixed(1) + ' dB');
const sliderPct = v => ((clamp(v, -60, 0) + 60) / 60 * 100) + '%';
function audioIcon(a) { return a.out ? (a.muted ? I.spkOff : I.spk) : (a.muted ? I.micOff : I.mic); }
function renderAudio() {
  $('#audio').innerHTML = st.audio.length
    ? st.audio.map((a, i) => `<div class="arow${a.muted ? ' muted' : ''}" data-i="${i}">
        <button class="mute" aria-label="Muet">${audioIcon(a)}</button>
        <div class="aw"><div class="an"><span class="n">${esc(a.name)}</span><span class="db">${dbTxt(a.db)}</span></div>
        <div class="meter"><b></b></div>
        <input type="range" min="-60" max="0" step="0.5" value="${clamp(a.db, -60, 0)}" style="--p:${sliderPct(a.db)}"></div></div>`).join('')
    : '<div class="row muted">Aucune source audio</div>';
  Meters.bind();
}
function updateAudioRow(a) {
  const row = $(`#audio .arow[data-i="${st.audio.indexOf(a)}"]`);
  if (!row) return;
  row.classList.toggle('muted', a.muted);
  row.querySelector('.mute').innerHTML = audioIcon(a);
  row.querySelector('.db').textContent = dbTxt(a.db);
  const sl = row.querySelector('input');
  if (document.activeElement !== sl) { sl.value = clamp(a.db, -60, 0); sl.style.setProperty('--p', sliderPct(a.db)); }
}
$('#audio').addEventListener('click', e => {
  const b = e.target.closest('.mute');
  if (!b) return;
  const a = st.audio[+b.closest('.arow').dataset.i];
  if (!a) return;
  buzz();
  a.muted = !a.muted;
  updateAudioRow(a);
  run('SetInputMute', { inputName: a.name, inputMuted: a.muted });
});
const volTimers = {};
$('#audio').addEventListener('input', e => {
  if (e.target.type !== 'range') return;
  const a = st.audio[+e.target.closest('.arow').dataset.i];
  if (!a) return;
  const v = +e.target.value;
  a.db = v;
  e.target.style.setProperty('--p', sliderPct(v));
  e.target.closest('.arow').querySelector('.db').textContent = dbTxt(v);
  clearTimeout(volTimers[a.name]);
  volTimers[a.name] = setTimeout(() => run('SetInputVolume', { inputName: a.name, inputVolumeDb: v <= -60 ? -100 : v }), 40);
});

function onObsEvent(type, d) {
  switch (type) {
    case 'InputVolumeMeters':
      Meters.feed(d.inputs); break;
    case 'CurrentProgramSceneChanged':
      st.scene = d.sceneName; renderScenes(); loadItems(); break;
    case 'SceneListChanged': case 'SceneCreated': case 'SceneRemoved': case 'SceneNameChanged':
      loadScenes(); break;
    case 'SceneItemEnableStateChanged':
      if (d.sceneName === st.scene) {
        const it = st.items.find(i => i.id === d.sceneItemId);
        if (it) { it.on = d.sceneItemEnabled; renderItems(); }
      }
      break;
    case 'SceneItemCreated': case 'SceneItemRemoved': case 'SceneItemListReindexed':
      if (d.sceneName === st.scene) loadItems(); break;
    case 'InputMuteStateChanged': {
      const a = st.audio.find(x => x.name === d.inputName);
      if (a) { a.muted = d.inputMuted; updateAudioRow(a); }
      break;
    }
    case 'InputVolumeChanged': {
      const a = st.audio.find(x => x.name === d.inputName);
      if (a) { a.db = d.inputVolumeDb; updateAudioRow(a); }
      break;
    }
    case 'InputCreated': case 'InputRemoved': case 'InputNameChanged':
      loadAudio(); break;
    case 'StreamStateChanged':
      if (d.outputState === 'OBS_WEBSOCKET_OUTPUT_RECONNECTING') Alerts.raise('reconnect', 'Le stream se reconnecte : connexion internet instable', 'bad', 'link');
      if (d.outputState === 'OBS_WEBSOCKET_OUTPUT_RECONNECTED') { Alerts.clear('reconnect'); toast('Stream reconnecté', 'ok'); }
      if (d.outputState === 'OBS_WEBSOCKET_OUTPUT_STOPPED') Alerts.clear('reconnect');
      if (d.outputState === 'OBS_WEBSOCKET_OUTPUT_STARTED') toast('Live lancé', 'ok');
      if (d.outputState === 'OBS_WEBSOCKET_OUTPUT_STOPPED') toast('Live terminé');
      pollOutputs(); break;
    case 'RecordStateChanged':
      if (d.outputState === 'OBS_WEBSOCKET_OUTPUT_STOPPED') toast('Enregistrement sauvegardé', 'ok');
      pollOutputs(); break;
    case 'ReplayBufferStateChanged':
      st.replay = !!d.outputActive; renderKeys(); break;
    case 'ReplayBufferSaved':
      toast('Clip sauvegardé ✓', 'ok'); break;
  }
}

$('#kLive').addEventListener('click', async () => {
  buzz();
  if (st.live && !(await confirmSheet('Couper le live ?', 'Le stream sera arrêté pour tes viewers.', 'Couper', true))) return;
  run('ToggleStream');
});
$('#kRec').addEventListener('click', () => { buzz(); run('ToggleRecord'); });
$('#kPause').addEventListener('click', () => { buzz(); run('ToggleRecordPause'); });
$('#kClip').addEventListener('click', async () => {
  buzz();
  if (st.replay === false) {
    if (await run('StartReplayBuffer')) toast('Replay buffer activé : retape pour clipper', 'ok');
  } else if (st.replay) {
    run('SaveReplayBuffer');
  }
});

/* ------------------------------------------------------------------ PC (PerfManager) */
const PC = {
  profiles: [], busy: false, ok: false,
  async api(path, body) {
    const r = await fetch('/api/' + path, {
      method: body ? 'POST' : 'GET', cache: 'no-store',
      signal: body ? undefined : AbortSignal.timeout(8000),
      headers: { 'X-Token': settings().token || '', 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined
    });
    if (r.status === 401) throw Object.assign(new Error("Code d'accès PC invalide"), { auth: true });
    if (!r.ok) throw new Error('Erreur du PC (' + r.status + ')');
    return r.json();
  },
  async refresh() {
    if (this.busy) return;
    try {
      const s = await this.api('status');
      this.ok = true; setPill('pc', true); pcNotice(null);
      Alerts.clear('pc');
      renderPcStatus(s);
      Alerts.onPc(s);
      renderUpdate(s);
      // Le PC vient d'installer une nouvelle version : on recharge l'appli pour en profiter
      if (s.version) {
        if (PC.version && PC.version !== s.version) { toast('PerfDeck a été mis à jour : rechargement…', 'ok'); setTimeout(() => location.reload(), 1500); }
        PC.version = s.version;
      }
      if (!this.profiles.length) {
        const p = await this.api('profiles');
        this.profiles = p.profiles || [];
        renderProfiles(s.profile);
        const l = await this.api('log');
        renderLog(l.lines);
      }
    } catch (e) {
      if (this.ok && !e.auth) Alerts.raise('pc', 'PC injoignable : vérifie le Wi-Fi ou Tailscale', 'bad', 'link');
      this.ok = false; setPill('pc', false);
      pcNotice(e.auth ? 'auth' : 'down');
    }
  }
};

function pcNotice(kind) {
  const n = $('#pcNotice');
  if (!kind) { n.hidden = true; return; }
  n.innerHTML = kind === 'auth'
    ? "<b>Code d'accès refusé.</b> Rescanne le QR code affiché par PerfRemote sur le PC, ou colle le code dans les réglages."
    : '<b>PC injoignable.</b> Lance <b>PerfRemote.bat</b> sur le PC et vérifie que le téléphone est sur le même Wi-Fi.';
  n.hidden = false;
}

function setCard(id, text, pct) {
  $('#c' + id).textContent = text;
  const bar = $('#b' + id);
  if (pct == null || isNaN(pct)) { bar.style.width = '0'; return; }
  pct = clamp(pct, 0, 100);
  bar.style.width = pct + '%';
  bar.style.background = pct >= 85 ? 'var(--bad)' : pct >= 60 ? 'var(--warn)' : 'var(--ok)';
}

function renderPcStatus(s) {
  setCard('Cpu', s.cpu != null ? s.cpu + ' %' : '–', s.cpu);
  setCard('Ram', s.ramTotal ? `${(+s.ramUsed).toFixed(1)} / ${Math.round(s.ramTotal)} Go` : '–', s.ramTotal ? s.ramUsed / s.ramTotal * 100 : null);
  setCard('Gpu', s.gpu != null ? `${Math.round(s.gpu)} % · ${Math.round(s.gpuTemp)} °C` : '–', s.gpu);
  setCard('Vram', s.vramTotal ? `${(+s.vramUsed).toFixed(1)} / ${Math.round(s.vramTotal)} Go` : '–', s.vramTotal ? s.vramUsed / s.vramTotal * 100 : null);
  const b = $('#banner');
  b.classList.toggle('on', !!s.profile);
  b.textContent = s.profile ? `Profil actif : ${s.profile} (depuis ${s.since})` : 'État normal, aucun profil actif';
  PC.active = s.profile || null;
  document.querySelectorAll('.prof').forEach(el => el.classList.toggle('on', PC.profiles[+el.dataset.i] && PC.profiles[+el.dataset.i].name === PC.active));
}

function renderProfiles(active) {
  $('#profiles').innerHTML = PC.profiles.map((p, i) =>
    `<button class="prof${p.name === active ? ' on' : ''}" data-i="${i}"><b>${esc(p.name)}</b><span>${esc(p.description || '')}</span></button>`).join('')
    || '<div class="muted">Aucun profil</div>';
}

function renderLog(lines) {
  lines = (lines || []).slice(-40);
  if (!lines.length) { $('#log').textContent = '—'; return; }
  $('#log').innerHTML = lines.map(l => {
    const m = /^\S+ (\S+) \[(\w+)\] (.*)$/.exec(l);
    if (!m) return `<div>${esc(l)}</div>`;
    return `<div class="${m[2].toLowerCase()}">${esc(m[1])}  ${esc(m[3])}</div>`;
  }).join('');
  const el = $('#log'); el.scrollTop = el.scrollHeight;
}

function renderUpdate(s) {
  const u = s.update;
  let html = '';
  if (u && u.available) html = `<div class="upd"><div><b>Mise à jour disponible</b><span>${esc(u.message || u.short)}</span></div><button class="btn primary" id="btnUpd">Installer</button></div>`;
  else if (u && u.error && u.configured) html = `<div class="upd err"><div><b>Mise à jour</b><span>${esc(u.error)}</span></div></div>`;
  if ($('#updCard').dataset.h !== html) { $('#updCard').innerHTML = html; $('#updCard').dataset.h = html; }
  const ver = s.version ? `Version ${esc(s.version)} · <button id="btnCheck">Vérifier les mises à jour</button>` : '';
  if ($('#verLine').dataset.h !== ver) { $('#verLine').innerHTML = ver; $('#verLine').dataset.h = ver; }
}
$('#updCard').addEventListener('click', async e => {
  if (!e.target.closest('#btnUpd') || PC.busy) return;
  buzz();
  if (!(await confirmSheet('Installer la mise à jour ?', 'PerfDeck Remote redémarre quelques secondes sur le PC. Tes profils et réglages sont conservés.', 'Installer'))) return;
  PC.busy = true;
  toast('Téléchargement de la mise à jour…');
  try {
    const r = await PC.api('update', {});
    toast(r.upToDate ? 'Déjà à jour' : `Version ${r.installed} installée : redémarrage…`, 'ok');
  } catch (err) { toast(err.message, 'err'); }
  PC.busy = false;
});
$('#verLine').addEventListener('click', async e => {
  if (!e.target.closest('#btnCheck') || PC.busy) return;
  buzz();
  try {
    const r = await PC.api('update-check', {});
    const u = r.update || {};
    toast(u.error ? u.error : (u.available ? `Version ${u.short} disponible` : 'PerfDeck est à jour'), u.error ? 'err' : 'ok');
    PC.refresh();
  } catch (err) { toast(err.message, 'err'); }
});

async function pcAction(btn, path, body, okMsg) {
  PC.busy = true;
  btn && btn.classList.add('busy');
  try {
    const r = await PC.api(path, body);
    renderLog(r.lines);
    toast(okMsg, 'ok');
  } catch (e) { toast(e.message, 'err'); }
  btn && btn.classList.remove('busy');
  PC.busy = false;
  PC.refresh();
}

$('#profiles').addEventListener('click', async e => {
  const b = e.target.closest('.prof');
  if (!b || PC.busy) return;
  buzz();
  const p = PC.profiles[+b.dataset.i];
  if (!(await confirmSheet(`Appliquer « ${p.name} » ?`, p.description, 'Appliquer'))) return;
  pcAction(b, 'apply', { name: p.name }, `« ${p.name} » appliqué`);
});
$('#btnRestore').addEventListener('click', async () => {
  if (PC.busy) return;
  buzz();
  if (!(await confirmSheet('Tout restaurer ?', 'Les services et applis arrêtés seront relancés.', 'Restaurer', true))) return;
  pcAction(null, 'restore', {}, 'PC revenu à la normale');
});
setInterval(() => { if (document.visibilityState === 'visible') PC.refresh(); }, 4000);

/* ------------------------------------------------------------------ Vumètres */
const Meters = {
  level: {}, shown: {}, els: {}, last: 0, raf: 0,
  bind() {
    this.els = {};
    document.querySelectorAll('#audio .arow').forEach(r => {
      const a = st.audio[+r.dataset.i];
      if (a) this.els[a.name] = r.querySelector('.meter b');
    });
  },
  feed(inputs) {
    for (const i of inputs || []) {
      let peak = 0, inPeak = 0;
      for (const ch of i.inputLevelsMul || []) { peak = Math.max(peak, ch[1] || 0); inPeak = Math.max(inPeak, ch[2] || 0); }
      const inDb = inPeak > 0 ? 20 * Math.log10(inPeak) : -100;
      const src = st.audio.find(x => x.name === i.inputName);
      // Micro coupé : on affiche le niveau d'entrée (en gris) pour voir que tu parles
      this.level[i.inputName] = src && src.muted ? inDb : (peak > 0 ? 20 * Math.log10(peak) : -100);
      Alerts.talk(i.inputName, inDb);
    }
    if (!this.raf) this.raf = requestAnimationFrame(t => this.draw(t));
  },
  draw(t) {
    this.raf = 0;
    const dt = this.last ? Math.min(0.1, (t - this.last) / 1000) : 0.016;
    this.last = t;
    let moving = false;
    for (const name in this.els) {
      const target = this.level[name] ?? -100;
      let cur = this.shown[name] ?? -100;
      cur = target >= cur ? target : Math.max(target, cur - 30 * dt);   // retombée douce, comme OBS
      this.shown[name] = cur;
      if (cur > target + 0.1) moving = true;
      const pct = clamp((cur + 60) / 60 * 100, 0, 100);
      this.els[name].style.width = (100 - pct) + '%';
    }
    if (moving) this.raf = requestAnimationFrame(t2 => this.draw(t2));
  },
  reset() {
    this.level = {}; this.shown = {};
    for (const n in this.els) this.els[n].style.width = '100%';
  }
};

/* ------------------------------------------------------------------ Alertes */
const Alerts = {
  active: {}, snoozed: {}, cpuHigh: 0, prevStats: null, hist: [], micSince: {}, talkSt: {},
  cfg() { return settings().alerts; },
  raise(key, msg, level, group, autoMs) {
    const a = this.cfg();
    if (group && a[group] === false) return;
    if (this.snoozed[key] && Date.now() < this.snoozed[key]) return;
    let el = this.active[key];
    if (el) { el.querySelector('.m').textContent = msg; return; }
    el = document.createElement('div');
    el.className = 'alert ' + (level || 'bad');
    el.innerHTML = I.warn + '<div class="m"></div><button aria-label="Fermer">✕</button>';
    el.querySelector('.m').textContent = msg;
    el.querySelector('button').onclick = () => { buzz(); this.snoozed[key] = Date.now() + 120000; this.clear(key); };
    $('#alerts').appendChild(el);
    this.active[key] = el;
    if (a.vibrate) vib(level === 'warn' ? [150, 90, 150] : [260, 110, 260, 110, 260]);
    if (autoMs) setTimeout(() => this.clear(key), autoMs);
  },
  clear(key) { const el = this.active[key]; if (el) { el.remove(); delete this.active[key]; } },
  clearAll() { Object.keys(this.active).forEach(k => this.clear(k)); this.snoozed = {}; },
  test() { delete this.snoozed.test; this.clear('test'); this.raise('test', 'Alerte de test : la bannière et la vibration fonctionnent', 'warn', null, 5000); },

  // Images perdues côté réseau, sur les 10 dernières secondes
  onStream(s) {
    if (s.outputReconnecting) this.raise('reconnect', 'Le stream se reconnecte : connexion internet instable', 'bad', 'link');
    else if (s.outputActive) this.clear('reconnect');
    if (!s.outputActive) { this.hist = []; this.clear('drop'); return; }
    const now = Date.now();
    this.hist.push({ t: now, sk: s.outputSkippedFrames || 0, tot: s.outputTotalFrames || 0 });
    while (this.hist.length > 1 && now - this.hist[0].t > 10000) this.hist.shift();
    const f = this.hist[0], l = this.hist[this.hist.length - 1];
    const dTot = l.tot - f.tot, pct = dTot > 0 ? (l.sk - f.sk) / dTot * 100 : 0;
    const thr = this.cfg().dropPct;
    if (dTot > 0 && pct >= thr) this.raise('drop', `Le stream perd ${pct.toFixed(1)} % des images : connexion ou débit trop juste`, 'bad', 'drop');
    else if (pct < thr / 2) this.clear('drop');
  },
  // Images sautées à l'encodage (NVENC) ou au rendu (GPU) entre deux relevés
  onStats(g) {
    const p = this.prevStats; this.prevStats = g;
    if (!p) return;
    const thr = this.cfg().dropPct;
    const rate = (sk, tot) => { const d = (g[tot] || 0) - (p[tot] || 0); return d > 0 ? ((g[sk] || 0) - (p[sk] || 0)) / d * 100 : 0; };
    const enc = rate('outputSkippedFrames', 'outputTotalFrames'), ren = rate('renderSkippedFrames', 'renderTotalFrames');
    if (enc >= thr) this.raise('enc', `OBS saute ${enc.toFixed(1)} % des images à l'encodage : baisse le préréglage NVENC`, 'bad', 'drop'); else this.clear('enc');
    if (ren >= thr) this.raise('ren', `Le rendu OBS rame (${ren.toFixed(1)} % d'images sautées) : GPU surchargé, limite les FPS du jeu`, 'bad', 'drop'); else this.clear('ren');
  },
  checkMic() {
    const lim = this.cfg().micSec * 1000, now = Date.now();
    for (const a of st.audio) {
      if (a.out) continue;
      const k = 'mic:' + a.name;
      if (a.muted && st.live) {
        this.micSince[a.name] = this.micSince[a.name] || now;
        const sec = Math.round((now - this.micSince[a.name]) / 1000);
        if (now - this.micSince[a.name] >= lim) this.raise(k, `Ton micro « ${a.name} » est coupé depuis ${sec} s pendant le live`, 'warn', 'mic');
      } else { delete this.micSince[a.name]; this.clear(k); }
    }
  },
  // Niveau d'entrée avant le mute : détecte quand tu parles micro coupé
  talk(name, inDb) {
    const a = st.audio.find(x => x.name === name);
    if (!a || a.out) return;
    const k = 'talk:' + name, now = Date.now();
    const t = this.talkSt[name] || (this.talkSt[name] = { since: 0, loud: 0 });
    if (!a.muted) { t.since = 0; this.clear(k); return; }
    if (inDb > -38) {
      t.loud = now;
      if (!t.since) t.since = now;
      if (now - t.since > 1200) this.raise(k, `Tu parles mais « ${name} » est coupé !`, 'bad', 'mic');
    } else if (now - t.loud > 1500) {
      t.since = 0;
      if (now - t.loud > 4000) this.clear(k);
    }
  },
  onPc(s) {
    const a = this.cfg();
    if (s.gpuTemp != null && s.gpuTemp >= a.gpuTemp) this.raise('gpu', `Carte graphique à ${Math.round(s.gpuTemp)} °C`, 'warn', 'gpu');
    else if (s.gpuTemp != null && s.gpuTemp < a.gpuTemp - 3) this.clear('gpu');
    if (s.cpu != null && s.cpu >= a.cpuPct) { if (++this.cpuHigh >= 3) this.raise('cpu', `Processeur à ${s.cpu} % depuis plus de 10 s`, 'warn', 'cpu'); }
    else { this.cpuHigh = 0; this.clear('cpu'); }
  }
};

/* ------------------------------------------------------------------ Jeux Steam */
const initials = n => n.split(/[\s:\-]+/).map(w => (w.match(/[\p{L}\p{N}]/u) || [''])[0]).filter(Boolean).slice(0, 2).join('').toUpperCase();
function played(ts) {
  if (!ts) return '';
  const d = (Date.now() / 1000 - ts) / 86400;
  if (d < 1) return "Joué aujourd'hui";
  if (d < 2) return 'Joué hier';
  if (d < 31) return `Joué il y a ${Math.floor(d)} j`;
  if (d < 365) return `Joué il y a ${Math.floor(d / 30)} mois`;
  return `Joué il y a ${Math.floor(d / 365)} an${d >= 730 ? 's' : ''}`;
}
function coverHtml(g) {
  const src = `/api/cover/${encodeURIComponent(g.appid)}?k=${encodeURIComponent(settings().token || '')}`;
  return `<div class="cover"><span class="ph">${esc(initials(g.name))}</span><img loading="lazy" alt="" src="${src}" data-id="${esc(g.appid)}" data-step="0"></div>`;
}
// Jaquette absente sur le PC : on essaie le site de Steam, sinon on garde les initiales
document.addEventListener('error', e => {
  const img = e.target;
  if (!(img instanceof HTMLImageElement) || !img.dataset.id) return;
  const id = img.dataset.id, step = +img.dataset.step + 1;
  const urls = [`https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/${id}/library_600x900.jpg`,
                `https://cdn.cloudflare.steamstatic.com/steam/apps/${id}/header.jpg`];
  img.dataset.step = step;
  if (step <= urls.length) img.src = urls[step - 1]; else img.remove();
}, true);

const Games = {
  list: null, steam: true, loading: false, q: '',
  async load(force) {
    if (this.loading) return;
    if (this.list && !force) { this.render(); return; }
    this.loading = true;
    if (!this.list) { $('#gamesNote').innerHTML = '<div class="muted">Chargement des jeux…</div>'; $('#games').innerHTML = ''; }
    try {
      const r = await PC.api('games' + (force ? '?refresh=1' : ''));
      this.list = r.games || []; this.steam = !!r.steam;
      if (force) toast(`${this.list.length} jeux trouvés`, 'ok');
    } catch (e) {
      this.loading = false;
      $('#gamesNote').innerHTML = `<div class="notice"><b>${e.auth ? "Code d'accès refusé." : 'PC injoignable.'}</b> ${e.auth ? 'Rescanne le QR code du PC.' : 'Lance PerfRemote.bat sur le PC.'}</div>`;
      return;
    }
    this.loading = false;
    this.render();
  },
  render() {
    if (!this.list) return;
    if (!this.steam) {
      $('#gamesNote').innerHTML = '<div class="notice"><b>Steam introuvable sur le PC.</b> Installe Steam ou lance-le une fois, puis actualise.</div>';
      $('#games').innerHTML = '';
      return;
    }
    const q = this.q.trim().toLowerCase();
    const items = this.list.filter(g => !q || g.name.toLowerCase().includes(q));
    $('#gamesNote').innerHTML = items.length ? '' : `<div class="muted">${q ? 'Aucun jeu ne correspond.' : 'Aucun jeu Steam installé trouvé.'}</div>`;
    $('#games').innerHTML = items.map(g => `<button class="game" data-id="${esc(g.appid)}">${coverHtml(g)}
      <div class="gn">${esc(g.name)}</div><div class="gs">${played(g.lastPlayed) || '&nbsp;'}</div></button>`).join('');
  }
};

$('#gq').addEventListener('input', e => { Games.q = e.target.value; Games.render(); });
$('#gRefresh').addEventListener('click', () => { buzz(); Games.load(true); });
$('#games').addEventListener('click', e => {
  const b = e.target.closest('.game');
  if (!b || !Games.list) return;
  const g = Games.list.find(x => String(x.appid) === b.dataset.id);
  if (!g) return;
  buzz();
  const profs = (PC.profiles || []).filter(p => !p.restore);
  openSheet(`<div class="sheet-cover">${coverHtml(g)}<div><h3>${esc(g.name)}</h3><p class="sheet-p" style="margin:0">${played(g.lastPlayed) || 'Steam'}</p></div></div>
    <div class="stack">
      <button class="btn primary wide" data-p="">Lancer</button>
      ${profs.map(p => `<button class="btn wide" data-p="${esc(p.name)}">${esc(p.name)}, puis lancer</button>`).join('')}
      <button class="btn ghost wide" data-x="1">Annuler</button>
    </div>`);
  $('#sheetBody').onclick = async ev => {
    const x = ev.target.closest('[data-p],[data-x]');
    if (!x) return;
    buzz();
    closeSheet();
    if (x.dataset.x) return;
    const prof = x.dataset.p;
    toast(prof ? `Profil « ${prof} », puis ${g.name}…` : `Lancement de ${g.name}…`);
    try {
      const r = await PC.api('launch', { appid: g.appid, profile: prof || null });
      if (r.lines) renderLog(r.lines);
      toast(`${g.name} se lance sur le PC`, 'ok');
      PC.refresh();
    } catch (err) { toast(err.message, 'err'); }
  };
});

/* ------------------------------------------------------------------ Plein écran, écran allumé */
let wake = null;
async function keepAwake() {
  try {
    if ('wakeLock' in navigator && !wake) {
      wake = await navigator.wakeLock.request('screen');
      wake.addEventListener('release', () => { wake = null; });
    }
  } catch (e) {}
}
$('#btnFull').addEventListener('click', async () => {
  buzz();
  try {
    if (document.fullscreenElement) await document.exitFullscreen();
    else await document.documentElement.requestFullscreen({ navigationUI: 'hide' });
  } catch (e) {}
  keepAwake();
});
document.addEventListener('visibilitychange', () => {
  OBS.updateSubs();
  if (document.visibilityState !== 'visible') return;
  keepAwake();
  if (!OBS.ok && !OBS.authFailed) OBS.connect();
  PC.refresh();
  pollOutputs();
});

if ('serviceWorker' in navigator && window.isSecureContext) {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}

/* ------------------------------------------------------------------ Démarrage */
let startTab = 'obs';
try { startTab = localStorage.getItem(KEY + '-tab') || 'obs'; } catch (e) {}
// Appli Android : déjà en plein écran avec l'écran toujours allumé
if (window.PerfDeckNative) $('#btnFull').style.display = 'none';
showTab(startTab);
renderKeys();
renderStatus();
renderScenes();
renderItems();
renderAudio();
OBS.connect();
PC.refresh();
keepAwake();
if (!settings().obsPassword) autoObs();
