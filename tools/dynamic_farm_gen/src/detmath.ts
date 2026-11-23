/**
 * Platform-independent elementary functions. Math.sin/atan/exp/sinh/… come from the engine's C++
 * libm, whose last bit differs between builds (e.g. fused multiply-add on arm64), and Math.hypot
 * is implementation-defined. These ports of FreeBSD msun / fdlibm use only + − × ÷ and
 * Math.sqrt, which IEEE 754 and ECMAScript make bit-exact everywhere, so generated datasets are
 * identical on the author's Mac and on Linux CI. Accuracy is within a few ulp.
 */

const view = new DataView(new ArrayBuffer(8));
const highWord = (x: number) => { view.setFloat64(0, x); return view.getInt32(0); };
const withHighWord = (x: number, hi: number) => { view.setFloat64(0, x); view.setInt32(0, hi); return view.getFloat64(0); };

/** 2^k exactly, for -1022 ≤ k ≤ 1023. */
function pow2(k: number): number {
  view.setInt32(0, (k + 1023) << 20);
  view.setInt32(4, 0);
  return view.getFloat64(0);
}

const PIO2_1 = 1.57079632673412561417e+00;
const PIO2_1T = 6.07710050650619224932e-11;
const INV_PIO2 = 6.36619772367581382433e-01;

function kernelSin(x: number): number {
  const z = x * x;
  const r = 8.33333333332248946124e-03 + z * (-1.98412698298579493134e-04 + z * (2.75573137070700676789e-06
    + z * (-2.50507602534068634195e-08 + z * 1.58969099521155010221e-10)));
  return x + x * z * (-1.66666666666666324348e-01 + z * r);
}

function kernelCos(x: number): number {
  const z = x * x;
  const r = z * (4.16666666666666019037e-02 + z * (-1.38888888888741095749e-03 + z * (2.48015872894767294178e-05
    + z * (-2.75573143513906633035e-07 + z * (2.08757232129817482790e-09 + z * -1.13596475577881948265e-11)))));
  const hz = 0.5 * z;
  const w = 1 - hz;
  return w + (((1 - w) - hz) + z * r);
}

/** Cody–Waite reduction to [-π/4, π/4]; ample for the |x| < 1e5 used here. */
function reduce(x: number): [number, number] {
  const n = Math.round(x * INV_PIO2);
  return [(x - n * PIO2_1) - n * PIO2_1T, ((n % 4) + 4) % 4];
}

export function sin(x: number): number {
  const [r, q] = reduce(x);
  return q === 0 ? kernelSin(r) : q === 1 ? kernelCos(r) : q === 2 ? -kernelSin(r) : -kernelCos(r);
}

export function cos(x: number): number {
  const [r, q] = reduce(x);
  return q === 0 ? kernelCos(r) : q === 1 ? -kernelSin(r) : q === 2 ? -kernelCos(r) : kernelSin(r);
}

export function tan(x: number): number {
  return sin(x) / cos(x);
}

const ATAN_HI = [4.63647609000806093515e-01, 7.85398163397448278999e-01, 9.82793723247329054082e-01, 1.57079632679489655800e+00];
const ATAN_LO = [2.26987774529616870924e-17, 3.06161699786838301793e-17, 1.39033110312309984516e-17, 6.12323399573676603587e-17];
const AT = [3.33333333333329318027e-01, -1.99999999998764832476e-01, 1.42857142725034663711e-01, -1.11111104054623557880e-01,
  9.09088713343650656196e-02, -7.69187620504482999495e-02, 6.66107313738753120669e-02, -5.83357013379057348645e-02,
  4.97687799461593236017e-02, -3.65315727442169155270e-02, 1.62858201153657823623e-02];

export function atan(x: number): number {
  if (x !== x) return x;
  const sign = x < 0 ? -1 : 1;
  let a = Math.abs(x);
  if (a > 1e20) return sign * (ATAN_HI[3] + ATAN_LO[3]);
  let id = -1;
  if (a >= 0.4375) {
    if (a < 1.1875) {
      if (a < 0.6875) { id = 0; a = (2 * a - 1) / (2 + a); } else { id = 1; a = (a - 1) / (a + 1); }
    } else if (a < 2.4375) { id = 2; a = (a - 1.5) / (1 + 1.5 * a); } else { id = 3; a = -1 / a; }
  }
  const z = a * a;
  const w = z * z;
  const s1 = z * (AT[0] + w * (AT[2] + w * (AT[4] + w * (AT[6] + w * (AT[8] + w * AT[10])))));
  const s2 = w * (AT[1] + w * (AT[3] + w * (AT[5] + w * (AT[7] + w * AT[9]))));
  if (id < 0) return sign * (a - a * (s1 + s2));
  return sign * (ATAN_HI[id] - ((a * (s1 + s2) - ATAN_LO[id]) - a));
}

const PI = 3.1415926535897931160e+00;
const PI_LO = 1.2246467991473531772e-16;

export function atan2(y: number, x: number): number {
  if (x === 0) return y > 0 ? PI / 2 : y < 0 ? -PI / 2 : 0;
  const a = atan(Math.abs(y / x));
  const r = x > 0 ? a : PI - (a - PI_LO);
  return y < 0 ? -r : r;
}

const LN2_HI = 6.93147180369123816490e-01;
const LN2_LO = 1.90821492927058770002e-10;

export function exp(x: number): number {
  if (x > 709.78) return Infinity;
  if (x < -745.13) return 0;
  const k = Math.round(x * 1.44269504088896338700e+00);
  const hi = x - k * LN2_HI;
  const lo = k * LN2_LO;
  const r = hi - lo;
  const t = r * r;
  const c = r - t * (1.66666666666666019037e-01 + t * (-2.77777777770155933842e-03 + t * (6.61375632143793436117e-05
    + t * (-1.65339022054652515390e-06 + t * 4.13813679705723846039e-08))));
  const y = 1 - ((lo - (r * c) / (2 - c)) - hi);
  // Split the scaling so 2^k stays a normal number at both ends.
  return k > 1000 ? y * pow2(k - 1000) * pow2(1000) : k < -1000 ? y * pow2(k + 1000) * pow2(-1000) : y * pow2(k);
}

/** Natural log for positive normal x. */
export function log(x: number): number {
  if (!(x > 0)) return x === 0 ? -Infinity : NaN;
  if (x === Infinity) return x;
  let hx = highWord(x);
  let k = (hx >> 20) - 1023;
  hx &= 0x000fffff;
  const i = (hx + 0x95f64) & 0x100000;
  const m = withHighWord(x, hx | (i ^ 0x3ff00000));
  k += i >> 20;
  const f = m - 1;
  const s = f / (2 + f);
  const z = s * s;
  const w = z * z;
  const t1 = w * (3.999999999940941908e-01 + w * (2.222219843214978396e-01 + w * 1.531383769920937332e-01));
  const t2 = z * (6.666666666666735130e-01 + w * (2.857142874366239149e-01 + w * (1.818357216161805012e-01 + w * 1.479819860511658591e-01)));
  const hfsq = 0.5 * f * f;
  return k * LN2_HI - ((hfsq - (s * (hfsq + t1 + t2) + k * LN2_LO)) - f);
}

export function sinh(x: number): number {
  const e = exp(x);
  return (e - 1 / e) / 2;
}

export function cosh(x: number): number {
  const e = exp(x);
  return (e + 1 / e) / 2;
}

export function asinh(x: number): number {
  const a = Math.abs(x);
  const r = log(a + Math.sqrt(a * a + 1));
  return x < 0 ? -r : r;
}

export function atanh(x: number): number {
  return 0.5 * log((1 + x) / (1 - x));
}

export function hypot(x: number, y: number): number {
  return Math.sqrt(x * x + y * y);
}
