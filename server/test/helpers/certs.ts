// Builds a throwaway StoreKit-like certificate chain (root P-384 -> intermediate P-384 -> leaf P-256)
// with node:crypto and a tiny DER encoder, and signs JWS transactions with the leaf key.
import { generateKeyPairSync, sign, type KeyObject } from "node:crypto";

const concat = (...parts: Uint8Array[]) => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
};

function len(n: number): Uint8Array {
  if (n < 0x80) return Uint8Array.of(n);
  const bytes: number[] = [];
  while (n > 0) {
    bytes.unshift(n & 0xff);
    n >>= 8;
  }
  return Uint8Array.of(0x80 | bytes.length, ...bytes);
}

const tlv = (tag: number, ...content: Uint8Array[]) => {
  const body = concat(...content);
  return concat(Uint8Array.of(tag), len(body.length), body);
};
const seq = (...c: Uint8Array[]) => tlv(0x30, ...c);
const set = (...c: Uint8Array[]) => tlv(0x31, ...c);
const explicit = (n: number, ...c: Uint8Array[]) => tlv(0xa0 + n, ...c);
const int = (n: number) => {
  const bytes: number[] = [];
  do {
    bytes.unshift(n & 0xff);
    n = Math.floor(n / 256);
  } while (n > 0);
  if (bytes[0]! & 0x80) bytes.unshift(0);
  return tlv(0x02, Uint8Array.from(bytes));
};
const bool = (b: boolean) => tlv(0x01, Uint8Array.of(b ? 0xff : 0));
const octet = (c: Uint8Array) => tlv(0x04, c);
const bitString = (c: Uint8Array) => tlv(0x03, Uint8Array.of(0), c);
const utf8 = (s: string) => tlv(0x0c, new TextEncoder().encode(s));

function oid(dotted: string): Uint8Array {
  const parts = dotted.split(".").map(Number);
  const bytes = [parts[0]! * 40 + parts[1]!];
  for (const p of parts.slice(2)) {
    const enc: number[] = [p & 0x7f];
    let v = Math.floor(p / 128);
    while (v > 0) {
      enc.unshift((v & 0x7f) | 0x80);
      v = Math.floor(v / 128);
    }
    bytes.push(...enc);
  }
  return tlv(0x06, Uint8Array.from(bytes));
}

function utcTime(d: Date): Uint8Array {
  const p = (n: number) => String(n).padStart(2, "0");
  const s = `${p(d.getUTCFullYear() % 100)}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}${p(d.getUTCHours())}${p(d.getUTCMinutes())}${p(d.getUTCSeconds())}Z`;
  return tlv(0x17, new TextEncoder().encode(s));
}

const name = (cn: string) => seq(set(seq(oid("2.5.4.3"), utf8(cn))));

const SIG_ALG = { "P-256": "1.2.840.10045.4.3.2", "P-384": "1.2.840.10045.4.3.3" } as const;
const HASH = { "P-256": "sha256", "P-384": "sha384" } as const;
type Curve = keyof typeof SIG_ALG;

interface CertSpec {
  cn: string;
  issuerCn: string;
  publicKey: KeyObject;
  signerKey: KeyObject;
  signerCurve: Curve;
  ca: boolean;
  markerOid?: string;
  notBefore: Date;
  notAfter: Date;
  serial: number;
}

function buildCert(spec: CertSpec): Uint8Array {
  const exts: Uint8Array[] = [seq(oid("2.5.29.19"), bool(true), octet(spec.ca ? seq(bool(true)) : seq()))];
  if (spec.markerOid) exts.push(seq(oid(spec.markerOid), octet(Uint8Array.of(0x05, 0x00))));
  const sigAlg = seq(oid(SIG_ALG[spec.signerCurve]));
  const tbs = seq(
    explicit(0, int(2)),
    int(spec.serial),
    sigAlg,
    name(spec.issuerCn),
    seq(utcTime(spec.notBefore), utcTime(spec.notAfter)),
    name(spec.cn),
    new Uint8Array(spec.publicKey.export({ type: "spki", format: "der" })),
    explicit(3, seq(...exts)),
  );
  const signature = sign(HASH[spec.signerCurve], tbs, { key: spec.signerKey, dsaEncoding: "der" });
  return seq(tbs, sigAlg, bitString(new Uint8Array(signature)));
}

export interface TestChain {
  root: Uint8Array;
  intermediate: Uint8Array;
  leaf: Uint8Array;
  leafKey: KeyObject;
}

export function makeChain(
  opts: { leafNotAfter?: Date; leafMarker?: boolean; now?: Date } = {},
): TestChain {
  const now = opts.now ?? new Date();
  const year = 365 * 24 * 3600 * 1000;
  const nb = new Date(now.getTime() - year);
  const na = new Date(now.getTime() + 5 * year);
  const rootKeys = generateKeyPairSync("ec", { namedCurve: "P-384" });
  const intKeys = generateKeyPairSync("ec", { namedCurve: "P-384" });
  const leafKeys = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const root = buildCert({
    cn: "Test Root CA - G3", issuerCn: "Test Root CA - G3", publicKey: rootKeys.publicKey,
    signerKey: rootKeys.privateKey, signerCurve: "P-384", ca: true, notBefore: nb, notAfter: na, serial: 1,
  });
  const intermediate = buildCert({
    cn: "Test WWDR CA G6", issuerCn: "Test Root CA - G3", publicKey: intKeys.publicKey,
    signerKey: rootKeys.privateKey, signerCurve: "P-384", ca: true, markerOid: "1.2.840.113635.100.6.2.1",
    notBefore: nb, notAfter: na, serial: 2,
  });
  const leaf = buildCert({
    cn: "Test StoreKit Signing", issuerCn: "Test WWDR CA G6", publicKey: leafKeys.publicKey,
    signerKey: intKeys.privateKey, signerCurve: "P-384", ca: false,
    markerOid: opts.leafMarker === false ? undefined : "1.2.840.113635.100.6.11.1",
    notBefore: nb, notAfter: opts.leafNotAfter ?? na, serial: 3,
  });
  return { root, intermediate, leaf, leafKey: leafKeys.privateKey };
}

const b64 = (b: Uint8Array) => Buffer.from(b).toString("base64");
const b64url = (b: Uint8Array | string) => Buffer.from(b).toString("base64url");

export function signTransaction(
  chain: TestChain,
  payload: Record<string, unknown>,
  opts: { includeRoot?: boolean; signingKey?: KeyObject } = {},
): string {
  const x5c = [b64(chain.leaf), b64(chain.intermediate)];
  if (opts.includeRoot !== false) x5c.push(b64(chain.root));
  const header = b64url(JSON.stringify({ alg: "ES256", x5c }));
  const body = b64url(JSON.stringify(payload));
  const sig = sign("sha256", Buffer.from(`${header}.${body}`), {
    key: opts.signingKey ?? chain.leafKey,
    dsaEncoding: "ieee-p1363",
  });
  return `${header}.${body}.${b64url(new Uint8Array(sig))}`;
}

export function transactionPayload(overrides: Record<string, unknown> = {}, now = Date.now()): Record<string, unknown> {
  return {
    transactionId: "2000000123456789",
    originalTransactionId: "2000000123456789",
    bundleId: "com.alpsenel.wordwidget",
    productId: "com.alpsenel.wordwidget.pro.monthly",
    purchaseDate: now - 3 * 24 * 3600 * 1000,
    expiresDate: now + 27 * 24 * 3600 * 1000,
    type: "Auto-Renewable Subscription",
    environment: "Sandbox",
    signedDate: now,
    ...overrides,
  };
}
