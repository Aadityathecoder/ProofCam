// The ProofCam mark and wordmark, generated as SVG from the same geometry as RingMark and
// ProofCamWordmark in ProofCamLogo.swift. Colors come from CSS (`--front`, `--back`).

const TIERS = {
  sm: { rings: 4, strokeShare: 0.54, offsetShare: 0.42 },
  md: { rings: 6, strokeShare: 0.50, offsetShare: 0.40 },
  lg: { rings: 9, strokeShare: 0.46, offsetShare: 0.38 },
  xl: { rings: 18, strokeShare: 0.46, offsetShare: 0.34 },
};
let clipCount = 0;

export function tierFor(size) { return size >= 64 ? 'lg' : size >= 36 ? 'md' : 'sm'; }

/** Resting offset in ring steps, toward the upper right. */
export function resting(tier) {
  const v = TIERS[tier].offsetShare / Math.SQRT2;
  return [v, -v];
}

/**
 * Returns an <svg> string. The back ring set sits in `.ring-back`, translated by
 * `--dx`/`--dy` (ring steps) times `--step` (user units), so CSS can animate alignment.
 */
export function ringMark({ tier = 'lg', drift = null, className = 'ring-mark', label = '' } = {}) {
  const t = TIERS[tier], count = t.rings;
  const radius = 50 / (1 + t.strokeShare / (2 * count)), step = radius / count, width = step * t.strokeShare;
  const [dx, dy] = drift ?? resting(tier), id = `pc-lens-${++clipCount}`;
  const circles = (k) => `<circle cx="50" cy="50" r="${(step * k).toFixed(3)}"/>`;
  let back = '', front = '';
  for (let k = 1; k <= count + 1; k++) back += circles(k);
  for (let k = 1; k <= count; k++) front += circles(k);
  const a11y = label ? `role="img" aria-label="${label}"` : 'aria-hidden="true"';
  return `<svg class="${className}" viewBox="0 0 100 100" ${a11y} style="--step:${step.toFixed(4)};--dx:${dx};--dy:${dy}">
    <clipPath id="${id}"><circle cx="50" cy="50" r="${(radius + width / 2).toFixed(3)}"/></clipPath>
    <g clip-path="url(#${id})" fill="none" stroke-width="${width.toFixed(3)}">
      <g class="ring-back">${back}</g><g class="ring-front">${front}</g>
    </g></svg>`;
}

function arc(points, cx, cy, r, from, to, moveFirst = false) {
  const steps = Math.max(24, Math.floor(Math.abs(to - from) / 3));
  for (let i = 0; i <= steps; i++) {
    const t = (from + (to - from) * i / steps) * Math.PI / 180;
    points.push(`${i === 0 && moveFirst ? 'M' : 'L'}${(cx + r * Math.cos(t)).toFixed(2)} ${(cy + r * Math.sin(t)).toFixed(2)}`);
  }
}

let wordmarkPath;
function buildWordmark() {
  const w = 15, h = w / 2, ro = 50 - h, p = [];
  // P
  p.push(`M${h} 56L${h} 200`, `M${h} ${56 + h}L${h + 28} ${56 + h}`);
  arc(p, h + 28, 102, 46 - h, -90, 90);
  p.push(`L${h} ${148 - h}`);
  // r
  const r0 = 95.5;
  p.push(`M${r0 + h} 100L${r0 + h} 200`, `M${r0 + h} 150`);
  arc(p, r0 + h + ro, 150, ro, 180, 270);
  p.push(`L${r0 + h + ro + 6} ${100 + h}`);
  // f
  const f0 = 385.5;
  p.push(`M${f0 + 22} 200L${f0 + 22} ${56 + h + 20}`);
  arc(p, f0 + 42, 56 + h + 20, 20, 180, 270);
  p.push(`L${f0 + 52} ${56 + h}`, `M${f0 + 4} ${100 + h}L${f0 + 40} ${100 + h}`);
  // C
  arc(p, 533.5, 128, 72 - h, -38, -322, true);
  // a stem
  const ca = 654.2;
  p.push(`M${ca + ro} 100L${ca + ro} 200`);
  // m
  const m0 = 716.2;
  p.push(`M${m0 + h} 100L${m0 + h} 200`);
  for (let k = 0; k < 2; k++) {
    const ax = m0 + h + k * 58;
    p.push(`M${ax} 136.5`);
    arc(p, ax + 29, 136.5, 29, 180, 360);
    p.push(`L${ax + 58} 200`);
  }
  return { d: p.join(''), ro, rings: [213.5, 323.5, ca] };
}

/** Wordmark: only the second "o" is out of register. */
export function wordmark(height = 15) {
  wordmarkPath ??= buildWordmark();
  const { d, ro, rings } = wordmarkPath, width = (height * 847.2 / 144).toFixed(1);
  const ring = (cx, extra = '') => `<circle cx="${cx}" cy="150" r="${ro}" ${extra}/>`;
  return `<svg class="wordmark" viewBox="0 56 847.2 144" width="${width}" height="${height}" aria-hidden="true"
    fill="none" stroke-width="15" stroke-linejoin="miter">
    ${ring(323.5 + 6, 'class="ghost" transform="translate(0 -6)"')}
    <path d="${d}" class="ink"/>${rings.map((cx) => ring(cx, 'class="ink"')).join('')}</svg>`;
}

/** Ring mark beside the wordmark, as in the app's header. */
export function lockup() {
  return `<span class="lockup" role="img" aria-label="ProofCam">${ringMark({ tier: 'md', className: 'ring-mark lockup-mark' })}${wordmark(15)}</span>`;
}
