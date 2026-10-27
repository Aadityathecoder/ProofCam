// Pixel work runs here so the camera and interface stay responsive.
import { makeImage, atLongEdge, cropped, ResearchError } from './core/image.js';
import { AdaptiveCandidate, candidates, candidateByName } from './core/watermark.js';
import { sha256Hex, randomIdentifier } from './core/proof.js';

async function decode(bytes) {
  if (bytes.length > 25 * 1024 * 1024) throw new ResearchError('invalidDimensions');
  const isJPEG = bytes[0] === 0xff && bytes[1] === 0xd8;
  const isPNG = bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47;
  if (!isJPEG && !isPNG) throw new ResearchError('invalidDimensions');
  const bitmap = await createImageBitmap(new Blob([bytes]), { imageOrientation: 'from-image', premultiplyAlpha: 'none' });
  const { width, height } = bitmap;
  if (!(width > 0 && height > 0 && width <= 16384 && height <= 16384 && width * height <= 20_000_000)) throw new ResearchError('invalidDimensions');
  const canvas = new OffscreenCanvas(width, height), context = canvas.getContext('2d', { willReadFrequently: true });
  context.drawImage(bitmap, 0, 0); bitmap.close();
  return makeImage(width, height, context.getImageData(0, 0, width, height).data);
}

async function jpeg(image, quality = 0.95) {
  const canvas = new OffscreenCanvas(image.width, image.height);
  canvas.getContext('2d').putImageData(new ImageData(image.data, image.width, image.height), 0, 0);
  return new Uint8Array(await (await canvas.convertToBlob({ type: 'image/jpeg', quality })).arrayBuffer());
}

const p95 = (values) => {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.ceil(values.length * 0.95) - 1];
};

const handlers = {
  /** Capture finalization: decode, normalize to a 1024-pixel long edge, embed v3, encode at 0.95. */
  async finalize({ bytes, id }) {
    const source = atLongEdge(await decode(bytes), 1024, true);
    return { jpeg: await jpeg(AdaptiveCandidate.embed(source, id)) };
  },
  async benchmark({ bytes, version }, progress) {
    const candidate = candidates[version], original = await decode(bytes);
    const input = atLongEdge(original, 1024, version !== 1), id = randomIdentifier();
    const samples = []; let output;
    for (let iteration = 0; iteration < 23; iteration++) {
      const start = performance.now();
      output = await jpeg(candidate.embed(input, id));
      const encoded = performance.now();
      const decoded = await decode(output);
      const extractStart = performance.now();
      const recovered = candidate.extract(decoded);
      const end = performance.now();
      if (iteration >= 3) samples.push({ embedJPEGMilliseconds: encoded - start, extractMilliseconds: end - extractStart, recovery: recovered });
      progress(iteration < 3 ? `Warmup ${iteration + 1}/3` : `Measured sample ${iteration - 2}/20`);
    }
    const report = {
      hardwareModel: navigator.userAgent, executableSHA256: null, inputWidth: input.width, inputHeight: input.height,
      candidate: candidate.name, createdAt: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'), operatingSystem: navigator.platform || 'unknown',
      runtime: 'web_browser', sourceSHA256: await sha256Hex(bytes), markedSHA256: await sha256Hex(output), expectedID: id,
      warmups: 3, samples, screenshots: [], memoryMeasurement: 'not_measured',
    };
    report.embedP95Milliseconds = p95(samples.map((s) => s.embedJPEGMilliseconds)) ?? 0;
    report.extractP95Milliseconds = p95(samples.map((s) => s.extractMilliseconds)) ?? 0;
    return { marked: output, report };
  },
  async screenshot({ bytes, candidate, rectangle, attested }, progress) {
    const original = await decode(bytes);
    const region = rectangle ? cropped(original, rectangle) : original;
    progress('Searching the screenshot…');
    const recovery = candidateByName(candidate).extract(region, () => progress('Searching the screenshot…'));
    return { result: { sha256: await sha256Hex(bytes), width: original.width, height: original.height, rectangle: rectangle || null,
      operatorAttestedOSCapture: attested, recovery } };
  },
  async decodable({ bytes }) { await decode(bytes); return {}; },
};

self.onmessage = async ({ data }) => {
  const { job, op, args } = data;
  try {
    const result = await handlers[op](args, (status) => self.postMessage({ job, progress: status }));
    self.postMessage({ job, result });
  } catch (error) {
    self.postMessage({ job, error: { message: error.message, code: error.code } });
  }
};
