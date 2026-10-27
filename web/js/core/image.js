// Port of RGBImage and GrayPlane (ProofCamCore). Images are { width, height, data } with
// opaque RGBA bytes. Rounding matches Swift's `.toNearestOrEven` so outputs agree pixel for pixel.

export class ResearchError extends Error {
  constructor(code) {
    const messages = {
      invalidDimensions: 'Image exceeds 20 megapixels/16384 pixels per side, or has invalid pixels.',
      insufficientCapacity: 'The image cannot hold three complete watermark frames.',
      invalidID: 'A complete lowercase 128-bit hexadecimal identifier is required.',
      invalidRectangle: 'Enter left,top,right,bottom within the decoded screenshot.',
    };
    super(messages[code] || code);
    this.code = code;
  }
}

export function roundEven(x) {
  const fraction = Math.abs(x % 1);
  return fraction === 0.5 ? 2 * Math.round(x / 2) : Math.round(x);
}

const clamp255 = (v) => (v < 0 ? 0 : v > 255 ? 255 : v);

export function makeImage(width, height, data) {
  if (!(width > 0 && height > 0 && width <= 16384 && height <= 16384 && width * height <= 20_000_000))
    throw new ResearchError('invalidDimensions');
  const pixels = data || new Uint8ClampedArray(width * height * 4).fill(255);
  if (pixels.length !== width * height * 4) throw new ResearchError('invalidDimensions');
  for (let i = 3; i < pixels.length; i += 4) if (pixels[i] !== 255) throw new ResearchError('invalidDimensions');
  return { width, height, data: pixels };
}

export function cloneImage(image) {
  return { width: image.width, height: image.height, data: new Uint8ClampedArray(image.data) };
}

export function cropped(image, box) {
  if (!(box.length === 4 && box[0] >= 0 && box[1] >= 0 && box[2] <= image.width && box[3] <= image.height &&
        box[2] > box[0] && box[3] > box[1])) throw new ResearchError('invalidRectangle');
  const w = box[2] - box[0], h = box[3] - box[1];
  const out = new Uint8ClampedArray(w * h * 4);
  for (let y = 0; y < h; y++) {
    const start = ((box[1] + y) * image.width + box[0]) * 4;
    out.set(image.data.subarray(start, start + w * 4), y * w * 4);
  }
  return makeImage(w, h, out);
}

/** Explicit pixel-center bilinear interpolation in 8-bit sRGB. */
export function resized(image, newWidth, newHeight) {
  if (!(newWidth > 0 && newHeight > 0 && newWidth <= 16384 && newHeight <= 16384 && newWidth * newHeight <= 20_000_000))
    throw new ResearchError('invalidDimensions');
  const { width, height, data } = image;
  if (newWidth === width && newHeight === height) return image;
  const out = new Uint8ClampedArray(newWidth * newHeight * 4);
  for (let y = 0; y < newHeight; y++) {
    const sy = Math.min(height - 1, Math.max(0, (y + 0.5) * height / newHeight - 0.5));
    const y0 = Math.floor(sy), y1 = Math.min(height - 1, y0 + 1), fy = sy - y0;
    for (let x = 0; x < newWidth; x++) {
      const sx = Math.min(width - 1, Math.max(0, (x + 0.5) * width / newWidth - 0.5));
      const x0 = Math.floor(sx), x1 = Math.min(width - 1, x0 + 1), fx = sx - x0;
      const a = (y0 * width + x0) * 4, b = (y0 * width + x1) * 4, c = (y1 * width + x0) * 4, d = (y1 * width + x1) * 4;
      const o = (y * newWidth + x) * 4;
      for (let k = 0; k < 3; k++) {
        const v = (data[a + k] * (1 - fx) + data[b + k] * fx) * (1 - fy) + (data[c + k] * (1 - fx) + data[d + k] * fx) * fy;
        out[o + k] = clamp255(roundEven(v));
      }
      out[o + 3] = 255;
    }
  }
  return makeImage(newWidth, newHeight, out);
}

export function atLongEdge(image, edge, upscale) {
  if (!(edge > 0 && edge <= 16384)) throw new ResearchError('invalidDimensions');
  const scale = edge / Math.max(image.width, image.height);
  if (!upscale && scale >= 1) return image;
  return resized(image, Math.max(1, roundEven(image.width * scale)), Math.max(1, roundEven(image.height * scale)));
}

export const luma = (d, i) => 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];

// MARK: GrayPlane — floating-point luma for geometry search.

export function grayPlane(image) {
  const n = image.width * image.height, pixels = new Float64Array(n);
  for (let i = 0; i < n; i++) pixels[i] = luma(image.data, i * 4);
  return { width: image.width, height: image.height, pixels };
}

function sample(plane, x, y) {
  const { width, pixels } = plane;
  const x0 = Math.floor(x), y0 = Math.floor(y), x1 = Math.min(width - 1, x0 + 1), y1 = Math.min(plane.height - 1, y0 + 1);
  const fx = x - x0, fy = y - y0;
  return (pixels[y0 * width + x0] * (1 - fx) + pixels[y0 * width + x1] * fx) * (1 - fy) +
         (pixels[y1 * width + x0] * (1 - fx) + pixels[y1 * width + x1] * fx) * fy;
}

export function planeResized(plane, edge) {
  const scale = edge / Math.max(plane.width, plane.height);
  const w = Math.max(1, roundEven(plane.width * scale)), h = Math.max(1, roundEven(plane.height * scale));
  if (w === plane.width && h === plane.height) return plane;
  const out = new Float64Array(w * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const sx = Math.min(plane.width - 1, Math.max(0, (x + 0.5) * plane.width / w - 0.5));
    const sy = Math.min(plane.height - 1, Math.max(0, (y + 0.5) * plane.height / h - 0.5));
    out[y * w + x] = sample(plane, sx, sy);
  }
  return { width: w, height: h, pixels: out };
}

export function planeTransformed(plane, degrees, mirrored = false) {
  const { width, height } = plane;
  const a = degrees * Math.PI / 180, c = Math.cos(a), s = Math.sin(a), cx = (width - 1) / 2, cy = (height - 1) / 2;
  const out = new Float64Array(plane.pixels.length);
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const dx = x - cx, dy = y - cy;
    let sx = c * dx + s * dy + cx;
    const sy = -s * dx + c * dy + cy;
    if (mirrored) sx = width - 1 - sx;
    if (sx >= 0 && sy >= 0 && sx <= width - 1 && sy <= height - 1) out[y * width + x] = sample(plane, sx, sy);
  }
  return { width, height, pixels: out };
}

/** Separable DCT(1,1), evaluated at every pixel in O(width*height) using a recurrence. */
export function planeCoefficients(plane, n) {
  const w = plane.width, h = plane.height, p = plane.pixels;
  const rows = new Float64Array(w * h), result = new Float64Array(w * h);
  if (w < n || h < n) return result;
  const basis = Array.from({ length: n }, (_, k) => Math.sqrt(2 / n) * Math.cos((2 * k + 1) * Math.PI / (2 * n)));
  const factor = 2 * Math.cos(Math.PI / n), boundary = basis[0];
  for (let y = 0; y < h; y++) {
    const r = y * w;
    for (let x = 0; x < Math.min(2, w - n + 1); x++) for (let k = 0; k < n; k++) rows[r + x] += p[r + x + k] * basis[k];
    if (w >= n + 2) for (let x = 0; x < w - n - 1; x++)
      rows[r + x + 2] = factor * rows[r + x + 1] - rows[r + x] + boundary * (p[r + x] - p[r + x + 1] + p[r + x + n] - p[r + x + n + 1]);
  }
  for (let x = 0; x < w - n + 1; x++) {
    for (let y = 0; y < Math.min(2, h - n + 1); y++) for (let k = 0; k < n; k++) result[y * w + x] += rows[(y + k) * w + x] * basis[k];
    if (h >= n + 2) for (let y = 0; y < h - n - 1; y++)
      result[(y + 2) * w + x] = factor * result[(y + 1) * w + x] - result[y * w + x] +
        boundary * (rows[y * w + x] - rows[(y + 1) * w + x] + rows[(y + n) * w + x] - rows[(y + n + 1) * w + x]);
  }
  return result;
}
