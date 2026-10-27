import { icons } from './icons.js';
import { ringMark, lockup, tierFor, resting } from './brand.js';
import { captures, signingKey, prefs } from './store.js';
import {
  sha256Hex, randomIdentifier, wire, embeddedProof, receipt as Receipt,
} from './core/proof.js';

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const escapeHTML = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const reduceMotion = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

function hydrate(root = document) {
  for (const node of $$('[data-icon]', root)) {
    if (node.dataset.hydrated) continue;
    node.innerHTML = icons[node.dataset.icon](Number(node.dataset.size) || 22);
    node.dataset.hydrated = '1';
  }
  for (const node of $$('[data-lockup]', root)) if (!node.firstChild) node.innerHTML = lockup();
  for (const node of $$('[data-ring]', root)) if (!node.firstChild) node.innerHTML = ringMark({ tier: node.dataset.ring });
  for (const node of $$('.alignment', root)) if (!node.firstChild) {
    const size = Number(node.dataset.size) || 60, tier = tierFor(size);
    node.innerHTML = ringMark({ tier, drift: resting(tier) });
    node.style.width = node.style.height = `${size}px`;
    node.firstElementChild.style.width = node.firstElementChild.style.height = '100%';
    setAlignmentLabel(node);
  }
}

const ALIGNMENT_LABELS = { aligned: 'Image and proof line up', offset: 'Image and proof do not line up', searching: 'Checking', idle: 'No proof to compare' };
function setAlignmentLabel(node) {
  node.setAttribute('role', 'img');
  node.setAttribute('aria-label', ALIGNMENT_LABELS[node.dataset.phase] || '');
}
function alignment(phase, size) { return `<span class="alignment" data-phase="${phase}" data-size="${size}"></span>`; }

/** Opens a modal with focus on the dialog itself, so no control looks pre-selected. */
function openDialog(dialog) {
  dialog.tabIndex = -1;
  dialog.showModal();
  dialog.focus();
}

let toastTimer;
function toast(message) {
  const node = $('#toast');
  node.textContent = message; node.hidden = false;
  clearTimeout(toastTimer); toastTimer = setTimeout(() => { node.hidden = true; }, 4000);
}

function vibrate(pattern) {
  if (prefs.get('shutterHaptics') && 'vibrate' in navigator) try { navigator.vibrate(pattern); } catch { /* unsupported */ }
}

function download(data, name, type) {
  const blob = data instanceof Blob ? data : new Blob([data], { type });
  const url = URL.createObjectURL(blob), a = document.createElement('a');
  a.href = url; a.download = name; document.body.append(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 30_000);
}

async function share(data, name, type) {
  const file = new File([data], name, { type });
  if (navigator.canShare?.({ files: [file] })) {
    try { await navigator.share({ files: [file] }); return; } catch (e) { if (e.name === 'AbortError') return; }
  }
  download(file, name, type);
}

async function readFile(file, limit) {
  if (file.size > limit) throw Object.assign(new Error('tooLarge'), { code: 'tooLarge' });
  return new Uint8Array(await file.arrayBuffer());
}

// MARK: Worker

const worker = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
const jobs = new Map(); let jobCounter = 0;
worker.onmessage = ({ data }) => {
  const job = jobs.get(data.job); if (!job) return;
  if (data.progress) { job.progress?.(data.progress); return; }
  jobs.delete(data.job);
  if (data.error) job.reject(Object.assign(new Error(data.error.message), { code: data.error.code }));
  else job.resolve(data.result);
};
function call(op, args, progress) {
  return new Promise((resolve, reject) => {
    const job = ++jobCounter; jobs.set(job, { resolve, reject, progress });
    worker.postMessage({ job, op, args });
  });
}

// MARK: Captured photos

const state = { captures: [], busy: false };
const photoURLs = new Map();
function photoURL(capture) {
  const cached = photoURLs.get(capture.id);
  if (cached && cached.blob === capture.photo) return cached.url;
  if (cached) URL.revokeObjectURL(cached.url);
  const url = URL.createObjectURL(capture.photo);
  photoURLs.set(capture.id, { blob: capture.photo, url });
  return url;
}
const formatDate = (t, long = false) => new Intl.DateTimeFormat(undefined, long
  ? { dateStyle: 'long', timeStyle: 'short' } : { dateStyle: 'medium', timeStyle: 'short' }).format(t);

async function refreshCaptures() {
  try { state.captures = await captures.all(); }
  catch { toast('Saved photos are unavailable because this browser blocked site storage.'); state.captures = []; }
  renderThumb();
}

function renderThumb(pop = false) {
  const thumb = $('#thumb'), latest = state.captures[0];
  thumb.innerHTML = latest ? `<img src="${photoURL(latest)}" alt="">` : `<span class="empty">${icons.photos(22)}</span>`;
  thumb.classList.toggle('pop', pop && !reduceMotion());
}

// MARK: Tabs

let activeTab = 'capture';
function selectTab(name) {
  activeTab = name;
  for (const tab of $$('.tab')) {
    if (tab.dataset.tab === name) tab.setAttribute('aria-current', 'page'); else tab.removeAttribute('aria-current');
  }
  for (const screen of $$('.screen')) screen.hidden = screen.id !== name;
  if (name === 'capture') camera.start(); else camera.stop();
  if (name === 'settings') renderPermission();
  window.scrollTo(0, 0);
}

// MARK: Camera

const camera = {
  stream: null, facing: 'environment', zoom: 1, flash: false, hasTorch: false, ready: false,
  message: null, starting: false, keyReady: null, cameras: 0,

  async start() {
    if (this.stream || this.starting || activeTab !== 'capture' || document.hidden || $('#shell').hidden) return;
    this.starting = true; this.ready = false; this.message = null; render();
    try {
      if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) {
        this.message = "This browser can't open the camera here. Use a current browser over HTTPS."; return;
      }
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: false, video: { facingMode: { ideal: this.facing }, width: { ideal: 1920 }, height: { ideal: 1440 } },
      });
      if (activeTab !== 'capture' || document.hidden) { stream.getTracks().forEach((t) => t.stop()); return; }
      this.stream = stream;
      const video = $('#video'); video.srcObject = stream;
      await video.play().catch(() => {});
      const track = stream.getVideoTracks()[0], settings = track.getSettings?.() || {};
      this.hasTorch = !!track.getCapabilities?.().torch;
      if (settings.facingMode) this.facing = settings.facingMode === 'user' ? 'user' : 'environment';
      this.cameras = (await navigator.mediaDevices.enumerateDevices()).filter((d) => d.kind === 'videoinput').length;
      this.ready = true;
    } catch (error) {
      this.message = error.name === 'NotAllowedError' ? 'Allow camera access to take photos.'
        : error.name === 'NotFoundError' || error.name === 'OverconstrainedError' ? 'No camera was found on this device. You can still verify photos.'
        : 'The camera couldn’t start. Close other apps using it, then try again.';
    } finally { this.starting = false; render(); renderPermission(); }
  },
  stop() {
    this.stream?.getTracks().forEach((t) => t.stop());
    this.stream = null; this.ready = false; this.flash = false;
    $('#video').srcObject = null; render();
  },
  async switchCamera() {
    if (state.busy) return;
    this.facing = this.facing === 'user' ? 'environment' : 'user';
    this.stop(); this.zoom = 1; await this.start();
  },
  setZoom(value) { this.zoom = value; render(); },
  async setTorch(on) {
    const track = this.stream?.getVideoTracks()[0];
    try { await track?.applyConstraints({ advanced: [{ torch: on }] }); } catch { /* not supported */ }
  },
  focus(x, y) {
    const track = this.stream?.getVideoTracks()[0], caps = track?.getCapabilities?.() || {};
    if (caps.pointsOfInterest || caps.focusMode)
      track.applyConstraints({ advanced: [{ pointsOfInterest: [{ x, y }], focusMode: 'single-shot', exposureMode: 'continuous' }] }).catch(() => {});
  },
  /** Grabs what the viewfinder shows (cover crop, digital zoom, front mirror), at most 1024 px. */
  async grab() {
    const video = $('#video'), box = $('#viewfinder').getBoundingClientRect();
    const vw = video.videoWidth, vh = video.videoHeight;
    if (!vw || !vh) throw new Error('no frame');
    const cover = Math.max(box.width / vw, box.height / vh);
    const sw = box.width / cover / this.zoom, sh = box.height / cover / this.zoom;
    const sx = (vw - sw) / 2, sy = (vh - sh) / 2;
    const scale = Math.min(1, 1024 / Math.max(sw, sh));
    const w = Math.max(1, Math.floor(sw * scale)), h = Math.max(1, Math.floor(sh * scale));
    const canvas = document.createElement('canvas'); canvas.width = w; canvas.height = h;
    const context = canvas.getContext('2d');
    if (this.facing === 'user') { context.translate(w, 0); context.scale(-1, 1); }
    context.drawImage(video, sx, sy, sw, sh, 0, 0, w, h);
    const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', 1));
    return new Uint8Array(await blob.arrayBuffer());
  },
};

function readiness() {
  if (!window.crypto?.subtle) return ['Signing unavailable in this browser', false];
  if (camera.keyReady === false) return ['Signing key unavailable', false];
  if (camera.ready && camera.keyReady) return ['Signing on', true];
  if (camera.message?.startsWith('No camera')) return ['No camera found', false];
  if (camera.message) return ['Camera access needed', false];
  return ['Starting camera', false];
}

function render() {
  const finder = $('#viewfinder'), [text, ready] = readiness();
  const canCapture = camera.ready && camera.keyReady && !state.busy;
  finder.classList.toggle('ready', camera.ready);
  finder.style.setProperty('--zoom', camera.zoom);
  finder.style.setProperty('--mirror', camera.facing === 'user' ? -1 : 1);
  $('#camera-message-text').textContent = camera.message ?? 'Opening camera…';
  $('#camera-retry').hidden = camera.message !== 'Allow camera access to take photos.';
  $('#grid').hidden = !prefs.get('cameraGrid');
  $('#readiness').classList.toggle('ready', ready && !state.busy);
  $('#readiness-text').textContent = state.busy ? 'Embedding proof and signing…' : text;
  const shutter = $('#shutter');
  shutter.disabled = !canCapture; shutter.classList.toggle('working', state.busy);
  shutter.setAttribute('aria-label', state.busy ? 'Signing photo' : 'Take signed photo');
  $('#switch-camera').disabled = !camera.ready || state.busy || camera.cameras < 2;
  const flash = $('#flash');
  flash.disabled = !camera.hasTorch || state.busy;
  flash.innerHTML = camera.flash ? icons.bolt(20) : icons.boltOff(20);
  flash.setAttribute('aria-pressed', String(camera.flash));
  flash.setAttribute('aria-label', camera.flash ? 'Turn flash off' : 'Turn flash on');
  for (const b of $$('#zoom button')) b.setAttribute('aria-pressed', String(Number(b.dataset.zoom) === camera.zoom));
  for (const b of $$('#zoom button')) b.disabled = state.busy;
  $('#signing').hidden = !state.busy;
}

async function takePhoto() {
  if (state.busy || !camera.ready || !camera.keyReady) return;
  state.busy = true; render();
  vibrate(10);
  const flash = $('#shutter-flash');
  if (!reduceMotion()) { flash.classList.remove('fire'); void flash.offsetWidth; flash.classList.add('fire'); }
  let provisional;
  try {
    if (camera.flash) { await camera.setTorch(true); await wait(250); }
    provisional = await camera.grab();
  } catch {
    state.busy = false; render(); toast('Photo capture failed. Please try again.'); return;
  } finally { if (camera.flash) camera.setTorch(false); }
  await finalizeCapture(provisional);
}

/** Mirrors CaptureProvenance.captured: retain, watermark, sign, embed, re-verify, store. */
async function finalizeCapture(provisional) {
  const id = randomIdentifier(), session = randomIdentifier(), createdAt = Date.now();
  let message, saved = null;
  try {
    // Keep the sole photo if later signing or storage fails.
    await captures.put({ id, createdAt, photo: new Blob([provisional], { type: 'image/jpeg' }), complete: false });
    const { jpeg } = await call('finalize', { bytes: provisional, id });
    const key = await signingKey.load();
    const digest = await sha256Hex(jpeg);
    const payload = wire.offlineCameraRequest(id, digest, session);
    const signature = await signingKey.sign(key, wire.signatureInput(payload, key.keyID, 'register'));
    const record = { id, session, fileSHA256: digest, publicKey: key.publicKey, signature };
    const signed = await Receipt.request(record);
    const receiptData = Receipt.encode(record);
    const finalBytes = embeddedProof.embed(receiptData, jpeg);
    if (!(await Receipt.verifies(record, finalBytes, signed))) throw new Error('signature');
    saved = { id, createdAt, photo: new Blob([finalBytes], { type: 'image/jpeg' }), receipt: receiptData, request: signed, complete: true, downloaded: false };
    await captures.put(saved);
    const stored = (await captures.all()).find((c) => c.id === id);
    const reread = new Uint8Array(await stored.photo.arrayBuffer());
    if (!(await Receipt.verifies(record, reread, signed))) throw new Error('storage');
    if (prefs.get('saveCopy')) {
      download(stored.photo, `ProofCam-${id}.jpg`, 'image/jpeg');
      saved.downloaded = true; await captures.put(saved);
      message = 'Proof embedded and downloaded.';
    } else message = 'Proof embedded and saved in ProofCam.';
  } catch {
    message = 'Couldn’t sign this photo. Any saved image is kept in ProofCam; it wasn’t downloaded.';
  }
  state.busy = false;
  await refreshCaptures(); renderThumb(true); render();
  const succeeded = message.startsWith('Proof embedded');
  vibrate(succeeded ? 15 : [20, 60, 20]);
  showOutcome(message, state.captures[0], succeeded);
}

function showOutcome(message, capture, succeeded) {
  const dialog = $('#outcome');
  dialog.innerHTML = `
    <div class="outcome-head">
      <div class="print">${capture ? `<img src="${photoURL(capture)}" alt="">` : '<span class="blank"></span>'}</div>
      <div>
        <p class="outcome-state" style="color:var(${succeeded ? '--success' : '--warning'})">${alignment(succeeded ? 'aligned' : 'offset', 40)}${succeeded ? 'Signed' : 'Needs attention'}</p>
        <h2 class="display-m" id="outcome-title">${escapeHTML(message)}</h2>
      </div>
    </div>
    ${succeeded ? '<p class="note">The proof is inside the JPEG, so it travels with the original. Share the original file to keep them together.</p>' : ''}
    <div class="button-stack">
      <button class="button primary" data-action="photos">View photos</button>
      <button class="button secondary" data-action="done">Done</button>
    </div>`;
  hydrate(dialog);
  const phase = $('.alignment', dialog); phase.dataset.phase = 'searching'; setAlignmentLabel(phase);
  requestAnimationFrame(() => requestAnimationFrame(() => { phase.dataset.phase = succeeded ? 'aligned' : 'offset'; setAlignmentLabel(phase); }));
  dialog.onclick = (event) => {
    const action = event.target.closest('[data-action]')?.dataset.action;
    if (event.target === dialog || action === 'done') dialog.close();
    if (action === 'photos') { dialog.close(); openLibrary(); }
  };
  openDialog(dialog);
}

// MARK: Library

function openLibrary() {
  const dialog = $('#library');
  renderLibrary(dialog);
  openDialog(dialog);
}

function renderLibrary(dialog) {
  const list = state.captures;
  dialog.innerHTML = `
    <div class="panel-bar"><span></span><h2>Captured photos</h2><button class="text-button" data-action="close">Done</button></div>
    <div class="panel-body">${list.length ? `<div class="library-grid">${list.map((c) => `
      <button class="library-item" data-id="${c.id}" aria-label="Photo from ${escapeHTML(formatDate(c.createdAt))}, ${c.complete ? 'signed' : 'signing incomplete'}">
        <span class="frame"><img src="${photoURL(c)}" alt="" loading="lazy"></span>
        <span class="badge" style="--tone:var(${c.complete ? '--success' : '--warning'})">${c.complete ? 'Signed' : 'Incomplete'}</span>
        <time>${escapeHTML(formatDate(c.createdAt))}</time>
      </button>`).join('')}</div>` : `
      <div class="empty-state">
        <div class="proof-illustration" aria-hidden="true">
          <div class="slip"><b>SHA-256</b>P-256 signature<i></i></div>
          <div class="photo"><span>${icons.photo(34)}</span></div>
        </div>
        <h3 class="display-l">No captured photos</h3>
        <p>Signed photos you take with ProofCam will be kept here in this browser.</p>
      </div>`}</div>`;
  dialog.onclick = (event) => {
    if (event.target === dialog || event.target.closest('[data-action="close"]')) dialog.close();
    const item = event.target.closest('.library-item');
    if (item) renderDetail(dialog, state.captures.find((c) => c.id === item.dataset.id));
  };
}

function renderDetail(dialog, capture) {
  const tone = capture.complete ? '--success' : '--warning';
  dialog.innerHTML = `
    <div class="panel-bar"><button class="text-button back" data-action="back">${icons.chevronLeft(18)}Photos</button><span></span><button class="text-button" data-action="close">Done</button></div>
    <div class="detail-photo"><img src="${photoURL(capture)}" alt="Captured photo"></div>
    <div class="panel-body">
      <p class="detail-status" style="--tone:var(${tone})">${capture.complete ? icons.check(16) : icons.alert(16)}${capture.complete ? 'Signed in this browser' : 'Signing incomplete'}</p>
      <h2 class="display-l detail-title">${escapeHTML(formatDate(capture.createdAt, true))}</h2>
      ${capture.complete ? `
        <dl class="records">
          <div class="record"><dt>Proof</dt><dd>Embedded in JPEG</dd></div>
          <div class="record"><dt>Signing key</dt><dd>This browser</dd></div>
          <div class="record"><dt>Downloaded</dt><dd style="--rec-tone:var(${capture.downloaded ? '--text' : '--secondary'})">${capture.downloaded ? 'Yes' : 'Not yet'}</dd></div>
          <div class="record"><dt>Capture ID</dt><dd class="mono">${capture.id.slice(0, 8)}</dd></div>
        </dl>
        <div class="detail-actions button-stack">
          <button class="button primary" data-action="share">${icons.share(20)}Share photo</button>
          ${capture.downloaded ? '' : '<button class="button secondary" data-action="download">Download photo</button>'}
          <div class="link-row">
            <button class="text-button" data-action="receipt">Share signature file</button>
            <button class="text-button" data-action="request">Export registration request</button>
          </div>
        </div>
        <p class="fine">The signed proof is embedded inside this JPEG, so it travels with the original. It does not prove that the scene itself is truthful.</p>`
      : '<p class="fine">This photo was retained after an interrupted capture. It has not been signed or downloaded as a signed image.</p>'}
    </div>`;
  dialog.scrollTop = 0;
  dialog.onclick = async (event) => {
    if (event.target === dialog) { dialog.close(); return; }
    const action = event.target.closest('[data-action]')?.dataset.action;
    const name = `ProofCam-${capture.id}`;
    if (action === 'close') dialog.close();
    if (action === 'back') renderLibrary(dialog);
    if (action === 'share') await share(await capture.photo.arrayBuffer(), `${name}.jpg`, 'image/jpeg');
    if (action === 'download') {
      download(capture.photo, `${name}.jpg`, 'image/jpeg');
      capture.downloaded = true; await captures.put(capture); renderDetail(dialog, capture);
    }
    if (action === 'receipt') await share(capture.receipt, `${capture.id}.json`, 'application/json');
    if (action === 'request') download(capture.request, `${capture.id}.cbor`, 'application/cbor');
  };
}

// MARK: Verify (PhotoVerification)

const verification = {
  data: null, imageURL: null, supplied: null, outcome: 'idle', source: null, checking: false,
  title: '', detail: '', expectedDigest: null, fileDigest: null, proofIsEmbedded: false,

  async load(bytes) {
    this.reset(false);
    if (bytes.length > 25 * 1024 * 1024) return this.fail('This file is too large. Choose a photo smaller than 25 MB.');
    this.imageURL = URL.createObjectURL(new Blob([bytes]));
    this.checking = true; renderVerify();
    try { await call('decodable', { bytes }); }
    catch {
      URL.revokeObjectURL(this.imageURL); this.imageURL = null; $('#verify-result').innerHTML = '';
      this.checking = false; return this.fail('Choose an opaque JPEG or PNG photo.');
    }
    this.data = bytes;
    await this.check();
  },
  async importReceipt(bytes) {
    try {
      if (bytes.length > 4096) throw new Error('size');
      this.supplied = Receipt.decode(bytes);
      if (this.data) await this.check(); else { this.outcome = 'receiptReady'; renderVerify(); }
    } catch {
      this.supplied = null;
      this.fail('This signature file could not be read. Choose the JSON signature exported by ProofCam.');
    }
  },
  async clearReceipt() {
    this.supplied = null;
    if (this.data) await this.check(); else this.reset();
  },
  reset(draw = true) {
    if (this.imageURL) URL.revokeObjectURL(this.imageURL);
    Object.assign(this, { data: null, imageURL: null, expectedDigest: null, fileDigest: null, proofIsEmbedded: false, source: null, checking: false, mismatchSource: null });
    $('#verify-result').innerHTML = '';
    this.outcome = this.supplied ? 'receiptReady' : 'idle';
    if (draw) renderVerify();
  },
  async check() {
    this.proofIsEmbedded = false; this.expectedDigest = null;
    const data = this.data; this.checking = true; renderVerify();
    const started = performance.now();
    const settle = async () => { const left = 450 - (performance.now() - started); if (left > 0 && !reduceMotion()) await wait(left); this.checking = false; };
    this.fileDigest = await Receipt.digestOf(data);
    let embedded = null;
    try { const raw = embeddedProof.extract(data); if (raw && raw.length <= 4096) embedded = Receipt.decode(raw); } catch { embedded = null; }
    if (embedded) {
      this.expectedDigest = embedded.fileSHA256;
      try {
        const ok = await Receipt.verifies(embedded, data);
        await settle();
        if (!ok) { this.mismatchSource = 'embedded'; return this.fail('The embedded proof is intact, but the image bytes no longer match it.', true); }
        this.proofIsEmbedded = true; return this.success('embedded');
      } catch { await settle(); return this.fail('The proof embedded in this photo is invalid or unsupported.'); }
    }
    if (this.supplied) {
      this.expectedDigest = this.supplied.fileSHA256;
      try {
        const ok = await Receipt.verifies(this.supplied, data);
        await settle();
        if (!ok) { this.mismatchSource = 'supplied'; return this.fail('The photo does not match this signature. It may have been edited or re-encoded.', true); }
        return this.success('supplied');
      } catch { await settle(); return this.fail('The signature is invalid or unsupported.'); }
    }
    for (const capture of state.captures) {
      if (!capture.complete || !capture.receipt) continue;
      try {
        const local = Receipt.decode(capture.receipt);
        if (local.fileSHA256 !== this.fileDigest || !(await Receipt.verifies(local, data, capture.request))) continue;
        this.expectedDigest = local.fileSHA256; await settle(); return this.success('local');
      } catch { continue; }
    }
    await settle();
    this.title = 'No matching signature found';
    this.detail = 'No saved signature in this browser matches these exact bytes. Import the photo’s signature, or choose the original file if a shared copy was changed.';
    this.outcome = 'noProof'; renderVerify();
  },
  fail(message, mismatch = false) {
    this.checking = false; this.title = 'Unable to verify'; this.detail = message;
    this.outcome = mismatch ? 'mismatch' : 'failed'; renderVerify(); vibrate([20, 60, 20]);
  },
  success(source) {
    this.title = 'Signature verified'; this.outcome = 'verified'; this.source = source;
    this.detail = {
      embedded: 'The cryptographic proof carried inside this JPEG matches its image bytes. The signing key’s owner has not been independently verified.',
      local: 'This photo exactly matches a signed capture saved in ProofCam in this browser.',
      supplied: 'This photo exactly matches the supplied signature. The signing key’s owner has not been independently verified.',
    }[source];
    renderVerify(); vibrate(15);
  },
};

function verifyCopy(v) {
  const verified = v.outcome === 'verified', mismatch = v.outcome === 'mismatch', noProof = v.outcome === 'noProof';
  const tone = verified ? '--success' : mismatch || v.outcome === 'failed' ? '--warning' : '--secondary';
  const symbol = verified ? icons.check(16) : mismatch || v.outcome === 'failed' ? icons.cross(16) : icons.minus(16);
  const headline = verified ? (v.source === 'supplied' ? 'Matches the proof file.' : 'Matches its proof.')
    : mismatch ? 'Doesn’t match its proof.' : noProof ? 'No proof found.' : 'Couldn’t check this file.';
  let records = [];
  if (verified) records = [
    ['Proof', v.source === 'embedded' ? 'Embedded in JPEG' : v.source === 'supplied' ? 'Separate JSON file' : 'Saved in this browser'],
    ['Signature', 'Valid, P-256', '--success'],
    ['Key owner', v.source === 'local' ? 'This browser' : 'Not independently verified'],
    ['Checked', 'In this browser'],
  ];
  else if (mismatch) records = [
    ['Proof', v.mismatchSource === 'supplied' ? 'Separate JSON file' : 'Embedded, intact'],
    ['Image bytes', 'Changed after signing', '--warning'], ['Checked', 'In this browser'],
  ];
  else if (noProof) records = [['Embedded proof', 'None found'], ['Saved signatures', 'No match in this browser']];
  const confirms = verified ? ['The image bytes are the ones that were signed.', 'The signed proof is intact.']
    : mismatch ? ['The file changed after it was signed. Ask the sender for the original file.']
    : noProof ? ['This file carries no proof ProofCam can read, and no saved signature matches it.']
    : ['ProofCam couldn’t read this file or its proof.'];
  const doesNot = verified ? ['Whether the event happened as described.', 'Who took the photo, or who owns the key.', 'Whether the scene was staged or AI-generated.']
    : mismatch ? ['What changed, who changed it, or why.', 'Whether the change matters.']
    : noProof ? ['That the photo is fake. Most photos weren’t taken with ProofCam.'] : ['Anything about the photo’s content.'];
  return { tone, symbol, headline, records, confirms, doesNot };
}

function digestLine(label, digest, reference) {
  let html = '';
  for (let i = 0; i < digest.length; i++) {
    if (i > 0 && i % 8 === 0) html += ' ';
    html += digest[i] === reference[i] ? digest[i] : `<mark>${digest[i]}</mark>`;
  }
  const a11y = label === 'This file' && digest !== reference ? 'This file’s fingerprint differs from the proof' : `${label} fingerprint: ${digest}`;
  return `<div class="digest" role="group" aria-label="${a11y}"><span>${label}</span><code>${html}</code></div>`;
}

let lastOutcome = null;
function renderVerify() {
  const v = verification;
  const showingResult = v.checking || !['idle', 'receiptReady'].includes(v.outcome);
  $('#verify-chooser').hidden = showingResult;
  const result = $('#verify-result'); result.hidden = !showingResult;
  $('#receipt-subtitle').textContent = v.supplied ? 'Signature ready. Choose its photo next.' : 'For copies whose embedded proof was removed';
  $('#clear-receipt').hidden = !v.supplied;
  $('#drop-zone').classList.toggle('busy', v.checking);
  if (!showingResult) { lastOutcome = null; return; }

  const c = verifyCopy(v);
  const phase = v.checking ? 'searching' : v.outcome === 'verified' ? 'aligned' : v.outcome === 'mismatch' ? 'offset' : 'idle';
  const key = `${v.checking}|${v.outcome}|${v.source}|${v.fileDigest}|${v.detail}`;
  if (key === lastOutcome) return;
  lastOutcome = key;

  if (v.checking) {
    result.innerHTML = `
      <div class="result-photo">${v.imageURL ? `<img src="${v.imageURL}" alt="">` : `<span class="placeholder">${icons.photo(40)}</span>`}
        <span class="alignment-badge">${alignment('searching', 60)}</span>
        <button class="back-button" data-action="back" aria-label="Back to Verify" disabled>${icons.chevronLeft(18)}</button></div>
      <div class="status-rule" style="--tone:var(--border)"></div>
      <div class="result-body"><div class="result-head" aria-live="polite">
        <p class="result-status" style="--tone:var(--secondary)"><span class="spinner"></span>Checking in this browser</p>
        <h2 class="display-l">Checking the photo against its proof</h2></div></div>`;
    hydrate(result); return;
  }

  const digests = v.fileDigest && v.expectedDigest ? (() => {
    let differing = Math.abs(v.fileDigest.length - v.expectedDigest.length);
    for (let i = 0; i < Math.min(v.fileDigest.length, v.expectedDigest.length); i++) if (v.fileDigest[i] !== v.expectedDigest[i]) differing++;
    return `<div class="fingerprints reveal" style="--i:2;--tone-2:var(${differing ? '--warning' : '--success'})">
      <h3>SHA-256 fingerprints</h3>
      ${digestLine('In proof', v.expectedDigest, v.expectedDigest)}
      ${digestLine('This file', v.fileDigest, v.expectedDigest)}
      <p class="digest-summary">${differing ? `${differing} of ${v.expectedDigest.length} characters differ.` : `All ${v.expectedDigest.length} characters match.`}</p></div>`;
  })() : '';

  const photo = result.querySelector('.result-photo');
  const body = `
    <div class="status-rule" style="--tone:var(${c.tone})"></div>
    <div class="result-body" style="--tone:var(${c.tone})">
      <div class="result-head reveal" style="--i:0" role="status">
        <p class="result-status">${c.symbol}${escapeHTML(v.title)}</p>
        <h2 class="display-l">${c.headline}</h2>
        <p class="detail">${escapeHTML(v.detail)}</p>
      </div>
      ${c.records.length ? `<dl class="records reveal" style="--i:1">${c.records.map(([k, val, t]) =>
        `<div class="record"><dt>${k}</dt><dd${t ? ` style="--rec-tone:var(${t})"` : ''}>${val}</dd></div>`).join('')}</dl>` : ''}
      ${digests}
      <div class="meaning reveal" style="--i:3">
        <h3 class="display-m">What this result means</h3>
        <h4 class="confirms">Confirms</h4><ul>${c.confirms.map((t) => `<li>${t}</li>`).join('')}</ul>
        <h4>Doesn’t confirm</h4><ul class="muted">${c.doesNot.map((t) => `<li>${t}</li>`).join('')}</ul>
      </div>
      <button class="button primary reveal" style="--i:4" data-action="back">Check another photo</button>
    </div>`;
  if (photo) {
    // Keep the photo and its alignment mark so the back rings settle from where they were.
    while (photo.nextSibling) photo.nextSibling.remove();
    photo.insertAdjacentHTML('afterend', body);
    $('.back-button', photo).disabled = false;
  } else {
    result.innerHTML = `<div class="result-photo">${v.imageURL ? `<img src="${v.imageURL}" alt="">` : `<span class="placeholder">${icons.photo(40)}</span>`}
      <span class="alignment-badge">${alignment('searching', 60)}</span>
      <button class="back-button" data-action="back" aria-label="Back to Verify">${icons.chevronLeft(18)}</button></div>${body}`;
    hydrate(result);
  }
  const mark = $('.alignment', result);
  requestAnimationFrame(() => requestAnimationFrame(() => { mark.dataset.phase = phase; setAlignmentLabel(mark); }));
}

async function verifyFiles(files) {
  for (const file of files) {
    const isJSON = file.type === 'application/json' || /\.json$/i.test(file.name);
    try {
      const bytes = await readFile(file, isJSON ? 4096 : 25 * 1024 * 1024);
      if (isJSON) await verification.importReceipt(bytes); else await verification.load(bytes);
    } catch (e) {
      verification.fail(e.code === 'tooLarge'
        ? (isJSON ? 'This signature file could not be read. Choose the JSON signature exported by ProofCam.' : 'This file is too large. Choose a photo smaller than 25 MB.')
        : 'The file could not be opened. Please try again.');
    }
  }
}

// MARK: Introduction

const PAGES = [
  ['Problem', 'Photos change as they travel.',
    'A resident photographs a flooded storm drain. By the time it reaches a council meeting, it has been forwarded, cropped and screenshotted.',
    'ProofCam is for student journalists, residents, researchers and field teams who document what happens where they live.'],
  ['Proof', 'The proof rides inside the photo.',
    'A private key kept in this browser signs the image’s SHA-256 fingerprint. That signed record is embedded directly in the JPEG.',
    'Share the original JPEG to keep the image and its proof together. No account is required.'],
  ['Limits', 'A match means unchanged.',
    'Anyone with the original file can open Verify and check whether the image still matches its embedded proof.',
    'A match does not prove the event happened as described, or who took the photo.'],
];

function artwork(index) {
  const card = (caption, icon, x, y, angle) =>
    `<div class="card-print" style="transform:translate(-50%,-50%) translate(${x}px,${y}px) rotate(${angle}deg)"><span>${icon}</span>${caption}</div>`;
  if (index === 0) return card('Screenshot', icons.photos(24), 104, -10, 7) + card('Forwarded', icons.photo(24), 0, 8, 2) + card('Original', icons.photo(24), -104, -6, -5);
  if (index === 1) return `<div class="proof-slip"><b>SHA-256</b>P-256, browser key</div>${card('Proof inside', icons.photo(24), -30, 0, -3)}`;
  return ringMark({ tier: 'lg', drift: [0.9, -0.6] });
}

function renderIntro(root, { completionTitle = 'Open camera', onDone }) {
  root.innerHTML = `
    <div class="intro">
      <div class="intro-top"><span data-lockup></span><button class="text-button" data-action="skip">Skip</button></div>
      <div class="intro-tabs" role="tablist">${PAGES.map(([tab], i) =>
        `<button role="tab" data-page="${i}" aria-label="${tab}, page ${i + 1} of ${PAGES.length}">${tab}</button>`).join('')}</div>
      <div class="intro-pages" tabindex="-1">${PAGES.map(([, title, body, note], i) => `
        <article class="intro-page" role="tabpanel" aria-label="${title}">
          <div class="intro-art" aria-hidden="true">${artwork(i)}</div>
          <h2 class="display-xl">${title}</h2><p class="body">${body}</p><p class="note">${note}</p>
        </article>`).join('')}</div>
      <div class="intro-foot"><button class="button primary" data-action="next">Continue</button><small>No account. Photos stay in this browser.</small></div>
    </div>`;
  hydrate(root);
  const pages = $('.intro-pages', root), articles = $$('.intro-page', root);
  let page = 0;
  const slip = $('.proof-slip', root);
  const set = (index) => {
    page = index;
    $$('.intro-tabs button', root).forEach((b, i) => {
      b.setAttribute('aria-selected', String(i === page)); b.classList.toggle('done', i <= page);
    });
    articles.forEach((a, i) => a.classList.toggle('active', i === page));
    if (slip) slip.style.transform = page === 1 ? 'translate(-50%,-50%) translate(46px,-40px) rotate(4deg)' : 'translate(-50%,-50%) translate(96px,36px) rotate(8deg)';
    $('[data-action="next"]', root).textContent = page === PAGES.length - 1 ? completionTitle : 'Continue';
    $('[data-action="skip"]', root).hidden = page === PAGES.length - 1;
  };
  const go = (index) => pages.scrollTo({ left: index * pages.clientWidth, behavior: reduceMotion() ? 'auto' : 'smooth' });
  pages.addEventListener('scroll', () => {
    const index = Math.round(pages.scrollLeft / pages.clientWidth);
    if (index !== page) set(index);
  }, { passive: true });
  root.onclick = (event) => {
    const target = event.target.closest('[data-action],[data-page]'); if (!target) return;
    if (target.dataset.page) go(Number(target.dataset.page));
    if (target.dataset.action === 'skip') onDone();
    if (target.dataset.action === 'next') page === PAGES.length - 1 ? onDone() : go(page + 1);
  };
  root.onkeydown = (event) => {
    if (event.key === 'ArrowRight' && page < PAGES.length - 1) go(page + 1);
    if (event.key === 'ArrowLeft' && page > 0) go(page - 1);
  };
  set(0);
}

// MARK: Settings

async function renderPermission() {
  const node = $('#camera-permission');
  try {
    const status = await navigator.permissions.query({ name: 'camera' });
    node.textContent = { granted: 'Allowed', denied: 'Blocked', prompt: 'Ask each time' }[status.state] || 'Unknown';
    status.onchange = renderPermission;
  } catch { node.textContent = camera.ready ? 'Allowed' : 'Managed by your browser'; }
}

function setupSettings() {
  for (const input of $$('[data-pref]')) {
    input.checked = prefs.get(input.dataset.pref);
    input.addEventListener('change', () => { prefs.set(input.dataset.pref, input.checked); render(); });
  }
  $('#haptics-note').hidden = 'vibrate' in navigator;
  $('#open-guide').onclick = () => {
    const dialog = $('#guide');
    renderIntro(dialog, { completionTitle: 'Done', onDone: () => dialog.close() });
    openDialog(dialog);
  };
  $('#open-lab').onclick = openLab;
}

// MARK: Research lab

const lab = { version: 3, busy: false, status: 'Import a JPEG or PNG from Files. Research use only.', marked: null, markedURL: null, report: null, captureStatus: 'Camera captures are saved with a browser-signed request. Registration is a separate Mac step.' };

function labStatus(report) {
  const correct = report.samples.filter((s) => s.recovery.decodedIDs.length === 1 && s.recovery.decodedIDs[0] === report.expectedID).length;
  let text = `${report.candidate}: ${correct}/20 JPEG recoveries. ${report.screenshots.length} screenshot tests recorded. Export JSON for all attempts. JPEG p95: ${Math.trunc(report.embedP95Milliseconds)} ms; extraction p95: ${Math.trunc(report.extractP95Milliseconds)} ms.`;
  const last = report.screenshots.at(-1);
  if (last) text += ' Latest screenshot: ' + (last.recovery.decodedIDs.length === 1 && last.recovery.decodedIDs[0] === report.expectedID ? 'matching ID.' : last.recovery.decodedIDs.length === 0 ? 'no ID recovered.' : 'different or conflicting IDs.');
  return text;
}

function openLab() {
  const dialog = $('#lab');
  renderLab(dialog); openDialog(dialog);
}

function renderLab(dialog) {
  const complete = state.captures;
  dialog.innerHTML = `
    <div class="panel-bar"><span></span><h2>Lab</h2><button class="text-button" data-action="close">Done</button></div>
    <div class="panel-body">
      <h2 class="display-l">Research lab</h2>
      <p class="lede" style="margin-top:8px">Tools for testing how well an invisible watermark survives re-saving and screenshots. Everything runs in this browser. Results are measurements, not proof that a photo is authentic, came from a camera, or is free of AI.</p>

      <section class="lab-section"><h3>Watermark benchmark</h3><div class="group">
        <p class="lab-status" aria-live="polite">${escapeHTML(lab.status)}</p>
        <div class="segmented" role="group" aria-label="Watermark version">${[1, 2, 3].map((v) =>
          `<button data-version="${v}" aria-pressed="${lab.version === v}" ${lab.busy ? 'disabled' : ''}>v${v}</button>`).join('')}</div>
        ${lab.busy ? '<p class="progress"><span class="spinner"></span>Running locally…</p>' : ''}
        <button class="row link" data-action="benchmark" ${lab.busy ? 'disabled' : ''}>Choose image and run 20 samples</button>
        ${lab.markedURL ? `<img class="lab-image" src="${lab.markedURL}" alt="Marked JPEG result">` : ''}
        <button class="row link" data-action="save-marked" ${!lab.marked || lab.busy ? 'disabled' : ''}>Save marked JPEG</button>
      </div><p class="group-footer">Applies to the next source. v1 is fastest, v2 favors stronger marking, and v3 (the default) uses smaller tiles with adaptive strength. v2 and v3 search edited images and take longer.</p></section>

      <section class="lab-section"><h3>Screenshot recovery</h3><div class="group">
        <label class="visually-hidden" for="lab-rect">Optional crop</label>
        <input class="text-field" id="lab-rect" placeholder="Optional crop: left,top,right,bottom" autocapitalize="none" autocorrect="off" spellcheck="false" inputmode="numeric" value="${escapeHTML(lab.rect || '')}">
        <label class="row"><span>I captured this using a system screenshot</span><input type="checkbox" role="switch" id="lab-attested" ${lab.attested ? 'checked' : ''}></label>
        <button class="row link" data-action="screenshot" ${!lab.report || lab.busy ? 'disabled' : ''}>Import screenshot</button>
      </div><p class="group-footer">${lab.report ? 'Save the marked JPEG, open it in a viewer, take a screenshot, then import it here.' : 'Run a benchmark first. Then save the marked JPEG, open it, take a screenshot, and import the screenshot here.'}</p></section>

      <section class="lab-section"><h3>Export</h3><div class="group">
        <button class="row link" data-action="export" ${!lab.report || lab.busy ? 'disabled' : ''}>Export research JSON</button>
      </div><p class="group-footer">A detected identifier is not proof that a photo is authentic. The lab uses no network services.</p></section>

      <section class="lab-section"><h3>Signing and registration (development)</h3><div class="group">
        <p class="lab-status">${escapeHTML(lab.captureStatus)}</p>
        <button class="row link" data-action="enroll" ${lab.busy ? 'disabled' : ''}>Prepare device enrollment</button>
        <p class="lab-status" style="font-size:.8125rem;color:var(--secondary)">App Attest is an iPhone feature and isn't available on the web. Browser signatures do not attest the app.</p>
        ${complete.map((c) => `<div class="capture-list-item">
          <strong style="font-size:.9375rem;font-weight:500">Capture ${c.id.slice(0, 8)} — ${c.complete ? 'registration pending' : 'incomplete, photo retained'}</strong>
          <button class="text-button" data-export-jpeg="${c.id}">Export capture JPEG</button>
          ${c.complete ? `<button class="text-button" data-export-request="${c.id}">Export signed request</button>` : ''}
        </div>`).join('')}
      </div><p class="group-footer">Select the private invitation file from your local server, then save the signed enrollment request. Keep both files private. Browser signatures bind exported bytes; registration and independent verification run on your Mac. This does not certify camera origin or absence of AI.</p></section>
    </div>`;
  dialog.onclick = (event) => labClick(dialog, event);
  $('#lab-rect', dialog).oninput = (e) => { lab.rect = e.target.value; };
  $('#lab-attested', dialog).onchange = (e) => { lab.attested = e.target.checked; };
}

function pickFile(accept) {
  return new Promise((resolve) => {
    const input = document.createElement('input');
    input.type = 'file'; input.accept = accept;
    input.onchange = () => resolve(input.files[0] || null);
    input.oncancel = () => resolve(null);
    input.click();
  });
}

function parseRectangle(text) {
  if (!text || !text.trim()) return null;
  const values = text.split(',').map((v) => v.trim());
  if (values.length !== 4 || !values.every((v) => /^-?\d+$/.test(v))) throw new Error('Enter left,top,right,bottom within the decoded screenshot.');
  return values.map(Number);
}

async function labClick(dialog, event) {
  if (event.target === dialog) { dialog.close(); return; }
  const target = event.target.closest('button'); if (!target || target.disabled) return;
  const action = target.dataset.action;
  if (action === 'close') { dialog.close(); return; }
  if (target.dataset.version) { lab.version = Number(target.dataset.version); renderLab(dialog); return; }
  if (target.dataset.exportJpeg) {
    const c = state.captures.find((x) => x.id === target.dataset.exportJpeg); download(c.photo, `${c.id}.jpg`, 'image/jpeg'); return;
  }
  if (target.dataset.exportRequest) {
    const c = state.captures.find((x) => x.id === target.dataset.exportRequest); download(c.request, `${c.id}.cbor`, 'application/cbor'); return;
  }
  if (action === 'save-marked') { download(lab.marked, 'proofcam-marked.jpg', 'image/jpeg'); return; }
  if (action === 'export') {
    download(new TextEncoder().encode(JSON.stringify(sortKeys(lab.report), null, 2)), 'proofcam-report.json', 'application/json'); return;
  }
  if (action === 'enroll') {
    const file = await pickFile('*/*'); if (!file) return;
    try {
      const data = await readFile(file, 1024), invitation = wire.invitation(data), key = await signingKey.load();
      download(await signingKey.signedEnvelope(key, wire.enrollment(key.publicKey, invitation), 'enroll'), 'proofcam-enrollment.cbor', 'application/cbor');
    } catch { lab.captureStatus = 'Enrollment preparation failed. Check the invitation file and try again.'; renderLab(dialog); }
    return;
  }
  if (action === 'benchmark' || action === 'screenshot') {
    const file = await pickFile('image/jpeg,image/png'); if (!file) return;
    let rectangle = null;
    try { if (action === 'screenshot') rectangle = parseRectangle(lab.rect); }
    catch (e) { lab.status = `Failed: ${e.message}`; renderLab(dialog); return; }
    lab.busy = true; renderLab(dialog);
    const progress = (status) => { lab.status = status; const node = $('.lab-status', dialog); if (node) node.textContent = status; };
    try {
      const bytes = await readFile(file, 25 * 1024 * 1024);
      if (action === 'benchmark') {
        const { marked, report } = await call('benchmark', { bytes, version: lab.version }, progress);
        if (lab.markedURL) URL.revokeObjectURL(lab.markedURL);
        lab.marked = marked; lab.markedURL = URL.createObjectURL(new Blob([marked], { type: 'image/jpeg' })); lab.report = report;
      } else {
        const { result } = await call('screenshot', { bytes, candidate: lab.report.candidate, rectangle, attested: !!lab.attested }, progress);
        lab.report.screenshots.push(result);
      }
      lab.status = labStatus(lab.report);
    } catch (e) {
      lab.status = e.code === 'insufficientCapacity' && lab.version !== 1
        ? (lab.version === 3 ? 'Failed: v3 needs at least a 132×120-pixel tile after normalization.' : 'Failed: v2 needs at least a 160×144-pixel tile after normalization.')
        : `Failed: ${e.code === 'tooLarge' ? 'Choose an image smaller than 25 MB.' : e.message}`;
    }
    lab.busy = false; renderLab(dialog);
  }
}

function sortKeys(value) {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map((k) => [k, sortKeys(value[k])]));
  return value;
}

// MARK: Startup

function setupCapture() {
  $('#shutter').onclick = takePhoto;
  $('#switch-camera').onclick = () => camera.switchCamera();
  $('#flash').onclick = () => { camera.flash = !camera.flash; render(); };
  $('#thumb').onclick = openLibrary;
  $('#camera-retry').onclick = () => camera.start();
  $('#zoom').onclick = (event) => { const b = event.target.closest('[data-zoom]'); if (b) camera.setZoom(Number(b.dataset.zoom)); };
  let focusTimer;
  $('#viewfinder').addEventListener('click', (event) => {
    if (!camera.ready || state.busy || event.target.closest('button')) return;
    const box = event.currentTarget.getBoundingClientRect(), ring = $('#focus-ring');
    ring.hidden = true; void ring.offsetWidth; ring.hidden = false;
    ring.style.left = `${event.clientX - box.left}px`; ring.style.top = `${event.clientY - box.top}px`;
    camera.focus((event.clientX - box.left) / box.width, (event.clientY - box.top) / box.height);
    clearTimeout(focusTimer); focusTimer = setTimeout(() => { ring.hidden = true; }, 1300);
  });
  document.addEventListener('visibilitychange', () => { if (document.hidden) camera.stop(); else if (activeTab === 'capture') camera.start(); });
  document.addEventListener('keydown', (event) => {
    if (activeTab === 'capture' && event.code === 'Space' && !event.repeat && document.activeElement === document.body && !$('dialog[open]')) {
      event.preventDefault(); takePhoto();
    }
  });
}

function setupVerify() {
  for (const id of ['pick-photo', 'pick-file', 'pick-receipt']) {
    const input = $(`#${id}`);
    input.onchange = async () => { const files = [...input.files]; input.value = ''; await verifyFiles(files); };
  }
  $('#clear-receipt').onclick = () => verification.clearReceipt();
  $('#verify-result').onclick = (event) => { if (event.target.closest('[data-action="back"]')) verification.reset(); };
  const zone = $('#drop-zone');
  zone.addEventListener('dragover', (e) => { e.preventDefault(); zone.classList.add('dragging'); });
  zone.addEventListener('dragleave', () => zone.classList.remove('dragging'));
  zone.addEventListener('drop', (e) => {
    e.preventDefault(); zone.classList.remove('dragging');
    const files = [...e.dataTransfer.files].sort((a) => (/\.json$/i.test(a.name) ? -1 : 1));
    if (files.length) verifyFiles(files);
  });
}

function showApp() {
  $('#intro-root').hidden = true; $('#shell').hidden = false;
  selectTab('capture');
}

async function start() {
  hydrate();
  $$('.tab').forEach((tab) => { tab.onclick = () => selectTab(tab.dataset.tab); });
  setupCapture(); setupVerify(); setupSettings();
  await refreshCaptures();
  try { await signingKey.load(); camera.keyReady = true; } catch { camera.keyReady = false; }
  render();
  if (prefs.get('introductionCompleted')) showApp();
  else {
    const root = $('#intro-root'); root.hidden = false;
    renderIntro(root, { onDone: () => { prefs.set('introductionCompleted', true); root.innerHTML = ''; showApp(); } });
  }
  if ('serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('sw.js').catch(() => {});
}

start();
