// Port of ProvenanceWire, EmbeddedProof and LocalCaptureReceipt. Byte formats match the
// iPhone app, so a proof made here verifies there and the reverse.

const encoder = new TextEncoder();
export const utf8 = (s) => encoder.encode(s);
export const toHex = (bytes) => Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
export const concat = (...parts) => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0; for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
};
const equalBytes = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);

export async function sha256(bytes) { return new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)); }
export async function sha256Hex(bytes) { return toHex(await sha256(bytes)); }
export function randomIdentifier() { return toHex(crypto.getRandomValues(new Uint8Array(16))); }

export function toBase64(bytes) {
  let s = ''; for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}
export function fromBase64(text) {
  if (typeof text !== 'string') throw new Error('malformed');
  const s = atob(text); const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}

// MARK: Deterministic CBOR (encoder only, as in the app)

function head(major, value) {
  if (value < 24) return Uint8Array.of((major << 5) | value);
  const count = value <= 0xff ? 1 : value <= 0xffff ? 2 : value <= 0xffffffff ? 4 : 8;
  const additional = { 1: 24, 2: 25, 4: 26, 8: 27 }[count];
  const out = new Uint8Array(1 + count); out[0] = (major << 5) | additional;
  let v = BigInt(value);
  for (let i = count; i >= 1; i--) { out[i] = Number(v & 0xffn); v >>= 8n; }
  return out;
}
export const cbor = {
  unsigned: (v) => head(0, v),
  negative: (v) => head(1, -(v + 1)),
  bytes: (b) => concat(head(2, b.length), b),
  text: (s) => { const b = utf8(s); return concat(head(3, b.length), b); },
  array: (items) => concat(head(4, items.length), ...items),
  map: (entries) => {
    const sorted = [...entries].sort(([a], [b]) => {
      if (a.length !== b.length) return a.length - b.length;
      for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return a[i] - b[i];
      return 0;
    });
    return concat(head(5, sorted.length), ...sorted.flat());
  },
  null: () => Uint8Array.of(0xf6),
};

// MARK: ProvenanceWire

const PREFIX = 'proofcam.dev.v1.';
const object = (fields) => cbor.map(fields.map(([k, v]) => [cbor.text(k), v]));
const isHex = (v, count) => typeof v === 'string' && v.length === count && /^[0-9a-f]+$/.test(v);

export const wire = {
  invitation(data) {
    const template = object([['invitation', cbor.bytes(new Uint8Array(32))]]);
    if (data.length !== template.length || !equalBytes(data.subarray(0, data.length - 32), template.subarray(0, template.length - 32)))
      throw new Error('invitation');
    return data.slice(data.length - 32);
  },
  enrollment(publicKey, invitation) {
    if (publicKey.length !== 65 || publicKey[0] !== 4 || invitation.length !== 32) throw new Error('invitation');
    return object([['type', cbor.text(PREFIX + 'enroll')], ['version', cbor.unsigned(1)],
      ['public_key', cbor.bytes(publicKey)], ['invitation', cbor.bytes(invitation)]]);
  },
  offlineCameraRequest(id, fileSHA256, session) {
    if (!isHex(id, 32) || !isHex(fileSHA256, 64) || !isHex(session, 32)) throw new Error('identifier');
    return object([['type', cbor.text(PREFIX + 'register')], ['version', cbor.unsigned(1)],
      ['id', cbor.text(id)], ['file_sha256', cbor.text(fileSHA256)], ['session', cbor.text(session)],
      ['mode', cbor.text('offline')], ['challenge', cbor.null()], ['source', cbor.text('camera_unverified')]]);
  },
  protectedHeader(keyID) {
    if (!isHex(keyID, 64)) throw new Error('identifier');
    return cbor.map([[cbor.unsigned(1), cbor.negative(-7)], [cbor.unsigned(4), cbor.bytes(utf8(keyID))]]);
  },
  signatureInput(payload, keyID, purpose) {
    if (!['register', 'enroll', 'challenge', 'attest'].includes(purpose)) throw new Error('signature');
    return cbor.array([cbor.text('Signature1'), cbor.bytes(this.protectedHeader(keyID)),
      cbor.bytes(utf8(PREFIX + purpose)), cbor.bytes(payload)]);
  },
  envelope(payload, keyID, signature) {
    if (signature.length !== 64) throw new Error('signature');
    return concat(Uint8Array.of(0xd2), cbor.array([cbor.bytes(this.protectedHeader(keyID)), cbor.map([]),
      cbor.bytes(payload), cbor.bytes(signature)]));
  },
};

// MARK: EmbeddedProof — a signed manifest in a JPEG comment segment

const MAGIC = utf8('ProofCam\u0000v1\u0000');

function scan(jpeg) {
  if (!(jpeg.length >= 2 && jpeg[0] === 0xff && jpeg[1] === 0xd8)) throw new Error('notJPEG');
  let offset = 2, proof = null;
  const kept = [jpeg.subarray(0, 2)];
  while (offset < jpeg.length) {
    if (jpeg[offset] !== 0xff) throw new Error('malformed');
    const markerStart = offset;
    while (offset < jpeg.length && jpeg[offset] === 0xff) offset++;
    if (offset >= jpeg.length) throw new Error('malformed');
    const marker = jpeg[offset++];
    if (marker === 0xda) { kept.push(jpeg.subarray(markerStart)); return { proof, stripped: concat(...kept) }; }
    if (marker === 0xd9) {
      kept.push(jpeg.subarray(markerStart, offset));
      if (offset !== jpeg.length) throw new Error('malformed');
      return { proof, stripped: concat(...kept) };
    }
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) { kept.push(jpeg.subarray(markerStart, offset)); continue; }
    if (offset + 2 > jpeg.length) throw new Error('malformed');
    const length = (jpeg[offset] << 8) | jpeg[offset + 1];
    if (length < 2 || offset + length > jpeg.length) throw new Error('malformed');
    const end = offset + length, payload = jpeg.subarray(offset + 2, end);
    if (marker === 0xfe && payload.length >= MAGIC.length && equalBytes(payload.subarray(0, MAGIC.length), MAGIC)) {
      if (proof) throw new Error('duplicate');
      proof = payload.slice(MAGIC.length);
    } else kept.push(jpeg.subarray(markerStart, end));
    offset = end;
  }
  throw new Error('malformed');
}

export const embeddedProof = {
  embed(proof, jpeg) {
    if (!(jpeg.length >= 2 && jpeg[0] === 0xff && jpeg[1] === 0xd8)) throw new Error('notJPEG');
    if (proof.length + MAGIC.length > 65531) throw new Error('tooLarge');
    if (scan(jpeg).proof) throw new Error('duplicate');
    const length = proof.length + MAGIC.length + 2;
    return concat(Uint8Array.of(0xff, 0xd8, 0xff, 0xfe, length >> 8, length & 0xff), MAGIC, proof, jpeg.subarray(2));
  },
  extract: (jpeg) => scan(jpeg).proof,
  proofless: (jpeg) => scan(jpeg).stripped,
};

// MARK: LocalCaptureReceipt — portable, self-signed

export const receipt = {
  /** Same field order and encoding as Swift's JSONEncoder (Data as base64). */
  encode: (r) => utf8(JSON.stringify({ id: r.id, session: r.session, fileSHA256: r.fileSHA256,
    publicKey: toBase64(r.publicKey), signature: toBase64(r.signature) })),
  decode(bytes) {
    const o = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
    if (!o || typeof o.id !== 'string' || typeof o.session !== 'string' || typeof o.fileSHA256 !== 'string') throw new Error('malformed');
    return { id: o.id, session: o.session, fileSHA256: o.fileSHA256, publicKey: fromBase64(o.publicKey), signature: fromBase64(o.signature) };
  },
  payload: (r) => wire.offlineCameraRequest(r.id, r.fileSHA256, r.session),
  keyID: (r) => sha256Hex(r.publicKey),
  async request(r) { return wire.envelope(this.payload(r), await this.keyID(r), r.signature); },
  /** SHA-256 of the file with any embedded proof segment removed. */
  async digestOf(file) {
    let comparable = file;
    try { comparable = embeddedProof.proofless(file); } catch { /* not a JPEG: hash every byte */ }
    return sha256Hex(comparable);
  },
  async verifies(r, file, storedRequest) {
    if ((await this.digestOf(file)) !== r.fileSHA256) return false;
    const key = await crypto.subtle.importKey('raw', r.publicKey, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
    if (r.signature.length !== 64) throw new Error('signature');
    const input = wire.signatureInput(this.payload(r), await this.keyID(r), 'register');
    if (!(await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, key, r.signature, input))) return false;
    if (storedRequest) return equalBytes(storedRequest, await this.request(r));
    return true;
  },
};
