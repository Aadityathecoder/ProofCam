// Port of the ProofCamCore watermark candidates: DCTCore/RegisteredCandidate (v1),
// TiledCandidate (v2) and AdaptiveCandidate (v3, the capture default).
import {
  ResearchError, roundEven, makeImage, cloneImage, cropped, atLongEdge, luma,
  grayPlane, planeResized, planeTransformed, planeCoefficients,
} from './image.js';

const clamp255 = (v) => (v < 0 ? 0 : v > 255 ? 255 : v);
const hex = (bytes) => Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
const parity = (v) => { let c = 0; while (v) { c ^= v & 1; v >>>= 1; } return c; };
const sameBox = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);

// MARK: DCTCore (v1)

export const FRAME_BITS = 176;
const DCT_BASIS = Array.from({ length: 64 }, (_, i) =>
  0.25 * Math.cos((2 * Math.floor(i / 8) + 1) * Math.PI / 16) * Math.cos((2 * (i % 8) + 1) * 2 * Math.PI / 16));
const CRC_TABLE = Array.from({ length: 256 }, (_, i) => {
  let v = i >>> 0;
  for (let k = 0; k < 8; k++) v = v & 1 ? (0xedb88320 ^ (v >>> 1)) >>> 0 : v >>> 1;
  return v >>> 0;
});

export function crc32(bytes) {
  let crc = 0xffffffff;
  for (const b of bytes) crc = (CRC_TABLE[(crc ^ b) & 255] ^ (crc >>> 8)) >>> 0;
  return (crc ^ 0xffffffff) >>> 0;
}

export function frame(id) {
  if (typeof id !== 'string' || !/^[0-9a-f]{32}$/.test(id)) throw new ResearchError('invalidID');
  const bytes = [80, 67];
  for (let i = 0; i < 32; i += 2) bytes.push(parseInt(id.slice(i, i + 2), 16));
  const crc = crc32(bytes);
  for (const shift of [24, 16, 8, 0]) bytes.push((crc >>> shift) & 255);
  return bytes;
}

const crcMatches = (bytes) => bytes[0] === 80 && bytes[1] === 67 &&
  crc32(bytes.slice(0, 18)) === (((bytes[18] << 24) | (bytes[19] << 16) | (bytes[20] << 8) | bytes[21]) >>> 0);

function dctCoefficient(image, bx, by) {
  let value = 0;
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++)
    value += luma(image.data, ((by + y) * image.width + bx + x) * 4) * DCT_BASIS[y * 8 + x];
  return value;
}

/** Adds delta·basis to every channel of a block, reading from `source` and writing to `output`. */
function applyBlock(source, output, bx, by, size, basis, delta) {
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const o = ((by + y) * source.width + bx + x) * 4, change = delta * basis[y * size + x];
    for (let k = 0; k < 3; k++) output.data[o + k] = clamp255(roundEven(source.data[o + k] + change));
  }
}

function validateV1(image) {
  if (Math.floor(image.width / 8) * Math.floor(image.height / 8) < FRAME_BITS * 3) throw new ResearchError('insufficientCapacity');
}

export const DCTCore = {
  embed(image, id) {
    validateV1(image);
    const payload = frame(id), output = cloneImage(image);
    let block = 0;
    for (let by = 0; by <= image.height - 8; by += 8) for (let bx = 0; bx <= image.width - 8; bx += 8) {
      const index = block % FRAME_BITS; block++;
      const bit = (payload[index >> 3] >> (7 - index % 8)) & 1;
      const c = dctCoefficient(image, bx, by);
      const target = (2 * roundEven((c / 12 - bit) / 2) + bit) * 12;
      applyBlock(image, output, bx, by, 8, DCT_BASIS, target - c);
    }
    return output;
  },
  extract(image) {
    validateV1(image);
    const ones = new Array(FRAME_BITS).fill(0), total = new Array(FRAME_BITS).fill(0);
    let block = 0;
    for (let by = 0; by <= image.height - 8; by += 8) for (let bx = 0; bx <= image.width - 8; bx += 8) {
      const index = block % FRAME_BITS; block++; total[index]++;
      const value = roundEven(dctCoefficient(image, bx, by) / 12);
      ones[index] += ((value % 2) + 2) % 2;
    }
    const bytes = new Array(22).fill(0);
    for (let i = 0; i < FRAME_BITS; i++) {
      if (ones[i] * 2 === total[i]) return null;
      if (ones[i] * 2 > total[i]) bytes[i >> 3] |= 1 << (7 - i % 8);
    }
    return crcMatches(bytes) ? hex(bytes.slice(2, 18)) : null;
  },
};

const attempt = (geometry, width, height, rectangle, status, decodedID = null) =>
  ({ geometry, width, height, rectangle, status, decodedID });
const recovery = (candidate, ids, attempts) =>
  ({ candidate, decodedIDs: [...ids].sort(), attempts, searchComplete: attempts.some((a) => a.status === 'searched') });

export const RegisteredCandidate = {
  name: 'ios-qim12-bilinear-v1',
  uniformBorder(image) {
    const d = image.data, r = d[0], g = d[1], b = d[2];
    let left = image.width, top = image.height, right = -1, bottom = -1;
    for (let y = 0; y < image.height; y++) for (let x = 0; x < image.width; x++) {
      const o = (y * image.width + x) * 4;
      if (d[o] !== r || d[o + 1] !== g || d[o + 2] !== b) {
        if (x < left) left = x; if (x > right) right = x; if (y < top) top = y; if (y > bottom) bottom = y;
      }
    }
    if (!(right >= left && (right - left + 1) * (bottom - top + 1) >= Math.floor(image.width * image.height / 4)) ||
        (left === 0 && top === 0 && right === image.width - 1 && bottom === image.height - 1)) return null;
    return [left, top, right + 1, bottom + 1];
  },
  extract(image) {
    const ids = new Set(), attempts = [];
    const view = (img, label, box) => {
      try {
        const id = DCTCore.extract(img); if (id) ids.add(id);
        attempts.push(attempt(label, img.width, img.height, box, 'searched', id));
      } catch (e) {
        if (e.code !== 'insufficientCapacity') throw e;
        attempts.push(attempt(label, img.width, img.height, box, 'insufficient_capacity'));
      }
    };
    const region = (img, label, box) => {
      view(img, label + ':native', box);
      if (Math.max(img.width, img.height) !== 1024) view(atLongEdge(img, 1024, true), label + ':edge1024', box);
    };
    region(image, 'whole', [0, 0, image.width, image.height]);
    const box = this.uniformBorder(image);
    if (box) region(cropped(image, box), 'uniform_border_trim', box);
    return recovery(this.name, ids, attempts);
  },
};

// MARK: TiledCandidate (v2)

const MARKER = Array.from({ length: 64 }, (_, i) => Number((0xd39a65c72e81b40fn >> BigInt(63 - i)) & 1n));
const TILE_W = 160, TILE_H = 144;
const HORIZONTAL = Array.from({ length: 8 }, (_, i) => Math.cos((2 * i + 1) * 2 * Math.PI / 16) * 0.5);
const VERTICAL = Array.from({ length: 8 }, (_, i) => Math.cos((2 * i + 1) * Math.PI / 16) * 0.5);
const DATA_POSITIONS = [3, 5, 6, 7, 9, 10, 11, 12];

function secded(byte) {
  const word = new Array(14).fill(0);
  DATA_POSITIONS.forEach((p, i) => { word[p] = (byte >> (7 - i)) & 1; });
  for (const p of [1, 2, 4, 8]) for (let i = 1; i <= 12; i++) if ((i & p) && i !== p) word[p] ^= word[i];
  word[13] = word.slice(1, 13).reduce((a, b) => a ^ b, 0);
  return word.slice(1, 14);
}

function unsecded(bits) {
  if (bits.length !== 13) return null;
  const word = [0, ...bits];
  let syndrome = 0;
  for (let i = 1; i <= 12; i++) if (word[i]) syndrome ^= i;
  const par = word.slice(1, 14).reduce((a, b) => a ^ b, 0);
  if (syndrome !== 0) {
    if (par !== 1 || syndrome > 12) return null;
    word[syndrome] ^= 1;
  }
  return DATA_POSITIONS.reduce((acc, p) => ((acc << 1) | word[p]) & 255, 0);
}

export function oriented(image, turns, mirrored) {
  if (!(turns >= 0 && turns < 4)) throw new ResearchError('invalidRectangle');
  const W = image.width, H = image.height;
  const w = turns % 2 === 0 ? W : H, h = turns % 2 === 0 ? H : W;
  const out = new Uint8ClampedArray(w * h * 4);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const mx = mirrored ? W - 1 - x : x;
    let tx, ty;
    switch (turns) {
      case 0: tx = mx; ty = y; break;
      case 1: tx = H - 1 - y; ty = mx; break;
      case 2: tx = W - 1 - mx; ty = H - 1 - y; break;
      default: tx = y; ty = W - 1 - mx;
    }
    const s = (y * W + x) * 4, o = (ty * w + tx) * 4;
    out[o] = image.data[s]; out[o + 1] = image.data[s + 1]; out[o + 2] = image.data[s + 2]; out[o + 3] = 255;
  }
  return makeImage(w, h, out);
}

/** Same-canvas bilinear deskew. Uncovered corners become black. */
export function rotated(image, degrees) {
  if (!(Number.isFinite(degrees) && Math.abs(degrees) <= 180)) throw new ResearchError('invalidRectangle');
  const { width: W, height: H, data } = image;
  const a = degrees * Math.PI / 180, c = Math.cos(a), s = Math.sin(a), cx = (W - 1) / 2, cy = (H - 1) / 2;
  const out = new Uint8ClampedArray(W * H * 4);
  for (let i = 3; i < out.length; i += 4) out[i] = 255;
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const dx = x - cx, dy = y - cy, sx = c * dx + s * dy + cx, sy = -s * dx + c * dy + cy;
    if (!(sx >= 0 && sy >= 0 && sx <= W - 1 && sy <= H - 1)) continue;
    const x0 = Math.floor(sx), y0 = Math.floor(sy), x1 = Math.min(W - 1, x0 + 1), y1 = Math.min(H - 1, y0 + 1);
    const fx = sx - x0, fy = sy - y0, o = (y * W + x) * 4;
    for (let k = 0; k < 3; k++) {
      const p = data[(y0 * W + x0) * 4 + k], q = data[(y0 * W + x1) * 4 + k];
      const r = data[(y1 * W + x0) * 4 + k], t = data[(y1 * W + x1) * 4 + k];
      out[o + k] = clamp255(roundEven((p * (1 - fx) + q * fx) * (1 - fy) + (r * (1 - fx) + t * fx) * fy));
    }
  }
  return makeImage(W, H, out);
}

/** Density-based crop for mostly solid viewer backgrounds; ignores small isolated controls. */
export function contentRectangle(image) {
  const { width: W, height: H, data } = image;
  const color = (i) => ((data[i] & 0xf0) << 16) | ((data[i + 1] & 0xf0) << 8) | (data[i + 2] & 0xf0);
  const counts = new Map();
  const add = (i) => { const k = color(i); counts.set(k, (counts.get(k) || 0) + 1); };
  for (let x = 0; x < W; x++) { add(x * 4); add(((H - 1) * W + x) * 4); }
  for (let y = 0; y < H; y++) { add(y * W * 4); add((y * W + W - 1) * 4); }
  let background = null;
  for (const key of [...counts.keys()].sort((a, b) => a - b))
    if (background === null || counts.get(key) > counts.get(background)) background = key;
  if (background === null) return null;
  const rows = new Array(H).fill(0), columns = new Array(W).fill(0);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++)
    if (color((y * W + x) * 4) !== background) { rows[y]++; columns[x]++; }
  const qw = Math.floor(W / 4), qh = Math.floor(H / 4);
  const top = rows.findIndex((v) => v > qw), bottom = rows.findLastIndex((v) => v > qw);
  const left = columns.findIndex((v) => v > qh), right = columns.findLastIndex((v) => v > qh);
  if (top < 0 || left < 0 || (right - left + 1) * (bottom - top + 1) < Math.floor(W * H / 4)) return null;
  const box = [left, top, right + 1, bottom + 1];
  return sameBox(box, [0, 0, W, H]) ? null : box;
}

function tiledCoefficients(image) {
  const w = image.width, h = image.height;
  const lum = new Float64Array(w * h), row = new Float64Array(w * h), result = new Float64Array(w * h);
  for (let i = 0; i < w * h; i++) lum[i] = luma(image.data, i * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w - 7; x++) {
    let v = 0; for (let d = 0; d < 8; d++) v += lum[y * w + x + d] * HORIZONTAL[d];
    row[y * w + x] = v;
  }
  for (let y = 0; y < h - 7; y++) for (let x = 0; x < w - 7; x++) {
    let v = 0; for (let d = 0; d < 8; d++) v += row[(y + d) * w + x] * VERTICAL[d];
    result[y * w + x] = v;
  }
  return result;
}

function tiledMarkerMatches(values, w, x, y) {
  let errors = 0;
  for (let i = 0; i < 64; i++) {
    const value = values[(y + Math.floor(i / 20) * 8) * w + x + (i % 20) * 8];
    if (Math.abs(value) < 3 || (value >= 0 ? 1 : 0) !== MARKER[i]) errors++;
    if ((i < 16 && errors > 2) || errors > 6) return false;
  }
  return true;
}

function tiledTiles(image) {
  if (image.width < TILE_W || image.height < TILE_H) return [];
  const values = tiledCoefficients(image), w = image.width, found = new Map();
  for (let y = 0; y <= image.height - TILE_H; y++) for (let x = 0; x <= w - TILE_W; x++) {
    if (!tiledMarkerMatches(values, w, x, y)) continue;
    const bytes = [];
    for (let index = 0; index < 22; index++) {
      const bits = [];
      for (let j = 0; j < 13; j++) {
        const i = 64 + index * 13 + j;
        bits.push(values[(y + Math.floor(i / 20) * 8) * w + x + (i % 20) * 8] >= 0 ? 1 : 0);
      }
      const byte = unsecded(bits);
      if (byte === null) break;
      bytes.push(byte);
    }
    if (bytes.length !== 22 || !crcMatches(bytes)) continue;
    const id = hex(bytes.slice(2, 18));
    if (!found.has(id)) found.set(id, [x, y, x + TILE_W, y + TILE_H]);
  }
  return [...found.keys()].sort().map((id) => [id, found.get(id)]);
}

function searchRegions(image) {
  const regions = [[image, 'whole', [0, 0, image.width, image.height]]];
  const border = RegisteredCandidate.uniformBorder(image);
  if (border) regions.push([cropped(image, border), 'uniform_border', border]);
  const content = contentRectangle(image);
  if (content && !regions.some((r) => sameBox(r[2], content))) regions.push([cropped(image, content), 'dominant_background', content]);
  return regions;
}

export const TiledCandidate = {
  name: 'ios-tiled-sign24-secded-v2',
  embed(image, id) {
    const fr = frame(id);
    if (image.width < TILE_W || image.height < TILE_H) throw new ResearchError('insufficientCapacity');
    const bits = [...MARKER, ...fr.flatMap(secded)], output = cloneImage(image);
    for (let ty = 0; ty <= image.height - TILE_H; ty += TILE_H) for (let tx = 0; tx <= image.width - TILE_W; tx += TILE_W) {
      bits.forEach((bit, i) => {
        const bx = tx + (i % 20) * 8, by = ty + Math.floor(i / 20) * 8;
        applyBlock(image, output, bx, by, 8, DCT_BASIS, (bit ? 24 : -24) - dctCoefficient(image, bx, by));
      });
    }
    return output;
  },
  extract(image, progress) {
    const attempts = [], ids = new Set();
    const record = (view, geometry, box, found) => {
      attempts.push(attempt(geometry, view.width, view.height, box, view.width < TILE_W || view.height < TILE_H ? 'insufficient_capacity' : 'searched'));
      for (const [id, tile] of found) {
        ids.add(id);
        attempts.push(attempt(geometry + ':tile_coordinates_in_transformed_view', view.width, view.height, tile, 'decoded', id));
      }
    };
    for (const [region, label, box] of searchRegions(image)) {
      const native = Math.max(region.width, region.height), seen = new Set();
      for (const edge of [native, 512, 768, 1024, native * 2, Math.max(1, Math.floor(native / 2))]) {
        if (seen.has(edge)) continue; seen.add(edge);
        if (edge > 1600) continue;
        const scaled = atLongEdge(region, edge, true);
        for (const mirror of [false, true]) for (let turn = 0; turn < 4; turn++) {
          const view = oriented(scaled, turn, mirror);
          record(view, `${label}:edge${edge}:turn${turn}:mirror${mirror}`, box, tiledTiles(view));
        }
        progress?.();
      }
    }
    const deskew = atLongEdge(image, Math.min(1024, Math.max(image.width, image.height)), false);
    for (let step = -15; step <= 15; step++) {
      if (step === 0) continue;
      const view = rotated(deskew, step);
      record(view, `whole:deskew${step.toFixed(1)}:native_capped1024`, [0, 0, image.width, image.height], tiledTiles(view));
      progress?.();
    }
    return recovery(this.name, ids, attempts);
  },
};

// MARK: AdaptiveCandidate (v3)

const ADAPTIVE_BASIS = Array.from({ length: 36 }, (_, i) =>
  (1 / 3) * Math.cos((2 * Math.floor(i / 6) + 1) * Math.PI / 12) * Math.cos((2 * (i % 6) + 1) * Math.PI / 12));

function encodedFrame(bytes) {
  const bits = bytes.flatMap((byte) => Array.from({ length: 8 }, (_, k) => (byte >> (7 - k)) & 1)).concat(new Array(6).fill(0));
  let state = 0; const out = [];
  for (const bit of bits) {
    const register = (state << 1) | bit;
    out.push(parity(register & 0o171), parity(register & 0o133));
    state = register & 63;
  }
  return out;
}

const TRELLIS = Array.from({ length: 128 }, (_, register) => [parity(register & 0o171), parity(register & 0o133)]);

/** Soft-decision Viterbi decoding of one 364-value frame. */
function viterbi(values) {
  if (values.length !== 364 || !values.every(Number.isFinite)) return null;
  let metrics = new Float64Array(64).fill(Infinity), ambiguous = new Uint8Array(64);
  metrics[0] = 0;
  const previous = new Uint8Array(182 * 64);
  for (let t = 0; t < 182; t++) {
    const next = new Float64Array(64).fill(Infinity), ties = new Uint8Array(64);
    const v0 = values[t * 2], v1 = values[t * 2 + 1], s0 = v0 >= 0 ? 1 : 0, s1 = v1 >= 0 ? 1 : 0;
    const a0 = Math.abs(v0), a1 = Math.abs(v1);
    for (let state = 0; state < 64; state++) {
      if (!Number.isFinite(metrics[state])) continue;
      for (let bit = 0; bit <= 1; bit++) {
        const register = (state << 1) | bit, target = register & 63, [a, b] = TRELLIS[register];
        const cost = metrics[state] + (s0 === a ? 0 : a0) + (s1 === b ? 0 : a1);
        if (cost < next[target]) { next[target] = cost; previous[t * 64 + target] = state; ties[target] = ambiguous[state]; }
        else if (cost === next[target]) ties[target] = 1;
      }
    }
    metrics = next; ambiguous = ties;
  }
  if (ambiguous[0] || !Number.isFinite(metrics[0])) return null;
  let state = 0; const bits = new Array(182).fill(0);
  for (let t = 181; t >= 0; t--) { bits[t] = state & 1; state = previous[t * 64 + state]; }
  if (state !== 0 || bits.slice(176).some((b) => b !== 0)) return null;
  const bytes = Array.from({ length: 22 }, (_, i) => bits.slice(i * 8, i * 8 + 8).reduce((acc, b) => (acc << 1) | b, 0));
  return crcMatches(bytes) ? hex(bytes.slice(2, 18)) : null;
}

function adaptiveTiles(plane, block = 6, allOrientations = false, coarse = 1, onSynchronization) {
  const w = plane.width, values = planeCoefficients(plane, block), found = new Map();
  for (const mirror of allOrientations ? [false, true] : [false]) for (let turn = 0; turn < (allOrientations ? 4 : 1); turn++) {
    const tw = (turn % 2 === 0 ? 22 : 20) * block, th = (turn % 2 === 0 ? 20 : 22) * block;
    if (w < tw || plane.height < th) continue;
    const sign = mirror !== (turn % 2 === 1) ? -1 : 1;
    const offsets = new Int32Array(428);
    for (let i = 0; i < 428; i++) {
      const x = mirror ? 21 - i % 22 : i % 22, y = Math.floor(i / 22);
      let px, py;
      switch (turn) {
        case 0: px = x; py = y; break;
        case 1: px = 19 - y; py = x; break;
        case 2: px = 21 - x; py = 19 - y; break;
        default: px = y; py = 21 - x;
      }
      offsets[i] = py * block * w + px * block;
    }
    const matches = (x, y, loose) => {
      const start = y * w + x;
      let errors = 0, energy = 0;
      for (let i = 0; i < 64; i++) {
        const value = values[start + offsets[i]] * sign;
        energy += Math.abs(value);
        if ((value >= 0 ? 1 : 0) !== MARKER[i]) errors++;
        if ((i < 16 && errors > (loose ? 4 : 3)) || errors > (loose ? 14 : 10)) return false;
      }
      if (energy >= 96 && !loose) onSynchronization?.(errors);
      return energy >= 96;
    };
    const visited = new Set();
    for (let y = 0; y <= plane.height - th; y += coarse) for (let x = 0; x <= w - tw; x += coarse) {
      if (!matches(x, y, coarse > 1)) continue;
      const radius = coarse - 1;
      for (let yy = Math.max(0, y - radius); yy <= Math.min(plane.height - th, y + radius); yy++)
        for (let xx = Math.max(0, x - radius); xx <= Math.min(w - tw, x + radius); xx++) {
          const start = yy * w + xx;
          if (visited.has(start)) continue;
          visited.add(start);
          if (!(coarse === 1 || matches(xx, yy, false))) continue;
          const payload = new Array(364);
          for (let i = 64; i < 428; i++) payload[i - 64] = values[start + offsets[i]] * sign;
          const id = viterbi(payload);
          if (id && !found.has(id)) found.set(id, [xx, yy, xx + tw, yy + th]);
        }
    }
  }
  return [...found.keys()].sort().map((id) => [id, found.get(id)]);
}

const fmtAngle = (a) => (Number.isInteger(a) ? a.toFixed(1) : String(a));

export const AdaptiveCandidate = {
  name: 'ios-tiled-adaptive-conv-v3',
  embed(image, id) {
    const bits = [...MARKER, ...encodedFrame(frame(id))];
    if (image.width < 132 || image.height < 120) throw new ResearchError('insufficientCapacity');
    const plane = grayPlane(image), coefficients = planeCoefficients(plane, 6), output = cloneImage(image), w = image.width;
    for (let ty = 0; ty <= image.height - 120; ty += 120) for (let tx = 0; tx <= w - 132; tx += 132) {
      bits.forEach((bit, i) => {
        const bx = tx + (i % 22) * 6, by = ty + Math.floor(i / 22) * 6, c = coefficients[by * w + bx];
        let sum = 0, squared = 0;
        for (let y = 0; y < 6; y++) for (let x = 0; x < 6; x++) { const v = plane.pixels[(by + y) * w + bx + x]; sum += v; squared += v * v; }
        const variance = Math.max(0, squared / 36 - (sum / 36) * (sum / 36));
        const strength = Math.max(12, Math.min(60, 12 + 2 * Math.max(0, Math.sqrt(variance) - 30)));
        const target = bit === 1 ? Math.max(strength, c) : Math.min(-strength, c);
        applyBlock(image, output, bx, by, 6, ADAPTIVE_BASIS, target - c);
      });
    }
    return output;
  },
  extract(image, progress) {
    const ids = new Set(), attempts = [];
    const search = (view, label, box, block, coarse = 1) => {
      let best = 65;
      const found = adaptiveTiles(view, block, true, coarse, (e) => { best = Math.min(best, e); });
      attempts.push(attempt(label, view.width, view.height, box, view.width < 22 * block || view.height < 20 * block ? 'insufficient_capacity' : 'searched'));
      for (const [id, tile] of found) {
        ids.add(id);
        attempts.push(attempt(label + ':tile_coordinates_in_transformed_view', view.width, view.height, tile, 'decoded', id));
      }
      return best;
    };
    for (const [region, label, box] of searchRegions(image)) {
      const plane = grayPlane(region), native = Math.max(region.width, region.height), seen = new Set();
      for (const edge of [native, 512, 768, 1024, native * 2, Math.max(1, Math.floor(native / 2))]) {
        if (!(edge <= 1600) || seen.has(edge)) continue;
        seen.add(edge);
        const scaled = planeResized(plane, edge);
        search(scaled, `${label}:edge${edge}:all_symmetries`, box, 6);
        if (edge === native) search(scaled, `${label}:native_half_pitch`, box, 3);
        progress?.();
      }
    }
    const whole = [0, 0, image.width, image.height];
    const small = planeResized(grayPlane(image), Math.min(512, Math.max(image.width, image.height)));
    const scores = new Map();
    for (let step = -90; step < 90; step++) {
      if (step === 0) continue;
      const angle = step / 2, view = planeTransformed(small, angle);
      for (const block of [3, 6]) {
        const score = search(view, `whole:angle${fmtAngle(angle)}:pitch${block}:all_symmetries`, whole, block, block === 3 ? 2 : 3);
        scores.set(angle, Math.min(scores.get(angle) ?? 65, score));
      }
      if (step % 6 === 0) progress?.();
    }
    const native = planeResized(grayPlane(image), Math.min(1024, Math.max(image.width, image.height)));
    const angles = [...scores.keys()].filter((a) => scores.get(a) <= 10).sort((a, b) => {
      if (scores.get(a) !== scores.get(b)) return scores.get(a) - scores.get(b);
      return Math.abs(a) === Math.abs(b) ? a - b : Math.abs(a) - Math.abs(b);
    });
    for (const angle of angles.slice(0, 4)) for (const delta of [-0.25, 0, 0.25])
      search(planeTransformed(native, angle + delta), `whole:refined_angle${fmtAngle(angle + delta)}:all_symmetries`, whole, 6, 3);
    return recovery(this.name, ids, attempts);
  },
};

export const candidates = {
  1: { name: RegisteredCandidate.name, embed: (img, id) => DCTCore.embed(img, id), extract: (img) => RegisteredCandidate.extract(img) },
  2: { name: TiledCandidate.name, embed: (img, id) => TiledCandidate.embed(img, id), extract: (img, p) => TiledCandidate.extract(img, p) },
  3: { name: AdaptiveCandidate.name, embed: (img, id) => AdaptiveCandidate.embed(img, id), extract: (img, p) => AdaptiveCandidate.extract(img, p) },
};
export const candidateByName = (name) => Object.values(candidates).find((c) => c.name === name);
