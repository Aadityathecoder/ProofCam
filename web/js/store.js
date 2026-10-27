// Browser-private storage. The IndexedDB database plays the role of the app's
// backup-excluded ProvenancePending folder, and holds the non-extractable signing key.
import { sha256Hex, wire } from './core/proof.js';

let opening;
function db() {
  opening ??= new Promise((resolve, reject) => {
    const request = indexedDB.open('proofcam', 1);
    request.onupgradeneeded = () => {
      request.result.createObjectStore('keys');
      request.result.createObjectStore('captures', { keyPath: 'id' });
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  return opening;
}

async function run(store, mode, action) {
  const database = await db();
  return new Promise((resolve, reject) => {
    const tx = database.transaction(store, mode), request = action(tx.objectStore(store));
    tx.oncomplete = () => resolve(request?.result);
    tx.onerror = tx.onabort = () => reject(tx.error);
  });
}

export const captures = {
  async all() {
    const list = (await run('captures', 'readonly', (s) => s.getAll())) || [];
    return list.sort((a, b) => b.createdAt - a.createdAt);
  },
  put: (capture) => run('captures', 'readwrite', (s) => s.put(capture)),
  remove: (id) => run('captures', 'readwrite', (s) => s.delete(id)),
};

/** The device signing key. Generated once, never exportable; no software fallback beyond this. */
export const signingKey = {
  async load() {
    let pair = await run('keys', 'readonly', (s) => s.get('capture-v1'));
    if (!pair) {
      pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign', 'verify']);
      await run('keys', 'readwrite', (s) => s.put(pair, 'capture-v1'));
    }
    const publicKey = new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey));
    return { privateKey: pair.privateKey, publicKey, keyID: await sha256Hex(publicKey) };
  },
  async sign(key, input) {
    return new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key.privateKey, input));
  },
  async signedEnvelope(key, payload, purpose) {
    const signature = await this.sign(key, wire.signatureInput(payload, key.keyID, purpose));
    return wire.envelope(payload, key.keyID, signature);
  },
};

const PREFS = { cameraGrid: false, shutterHaptics: true, saveCopy: false, introductionCompleted: false };
export const prefs = {
  get(name) {
    try { const v = localStorage.getItem('proofcam.' + name); return v === null ? PREFS[name] : v === 'true'; }
    catch { return PREFS[name]; }
  },
  set(name, value) { try { localStorage.setItem('proofcam.' + name, String(value)); } catch { /* private mode */ } },
};
