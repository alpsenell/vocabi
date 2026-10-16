// Minimal DER reader and X.509 parser: just enough to verify Apple's StoreKit certificate chain
// with WebCrypto (no Node APIs, so it runs on Workers).

export interface Der {
  tag: number;
  /** Offset of the tag byte in the source buffer. */
  start: number;
  /** Offset of the first content byte. */
  contentStart: number;
  /** Offset just past the element. */
  end: number;
}

export class Asn1Error extends Error {}

export function readDer(buf: Uint8Array, offset: number): Der {
  if (offset + 2 > buf.length) throw new Asn1Error("truncated DER");
  const tag = buf[offset]!;
  let len = buf[offset + 1]!;
  let pos = offset + 2;
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n === 0 || n > 4) throw new Asn1Error("unsupported DER length");
    len = 0;
    for (let i = 0; i < n; i++) {
      if (pos >= buf.length) throw new Asn1Error("truncated DER length");
      len = len * 256 + buf[pos++]!;
    }
  }
  const end = pos + len;
  if (end > buf.length) throw new Asn1Error("DER element overruns buffer");
  return { tag, start: offset, contentStart: pos, end };
}

export function children(buf: Uint8Array, parent: Der): Der[] {
  const out: Der[] = [];
  let pos = parent.contentStart;
  while (pos < parent.end) {
    const el = readDer(buf, pos);
    out.push(el);
    pos = el.end;
  }
  return out;
}

export function decodeOid(bytes: Uint8Array): string {
  if (bytes.length === 0) throw new Asn1Error("empty OID");
  const parts: number[] = [];
  const first = bytes[0]!;
  parts.push(first < 80 ? Math.floor(first / 40) : 2, first < 80 ? first % 40 : first - 80);
  let value = 0;
  for (let i = 1; i < bytes.length; i++) {
    const b = bytes[i]!;
    value = value * 128 + (b & 0x7f);
    if (!(b & 0x80)) {
      parts.push(value);
      value = 0;
    }
  }
  return parts.join(".");
}

const TAG = { SEQUENCE: 0x30, OID: 0x06, BIT_STRING: 0x03, INTEGER: 0x02, UTC_TIME: 0x17, GEN_TIME: 0x18 } as const;

export const OID = {
  ecdsaWithSHA256: "1.2.840.10045.4.3.2",
  ecdsaWithSHA384: "1.2.840.10045.4.3.3",
  ecPublicKey: "1.2.840.10045.2.1",
  p256: "1.2.840.10045.3.1.7",
  p384: "1.3.132.0.34",
  basicConstraints: "2.5.29.19",
  /** Apple: present on the StoreKit signing (leaf) certificate. */
  appleReceiptSigning: "1.2.840.113635.100.6.11.1",
  /** Apple: present on the Apple Worldwide Developer Relations intermediate. */
  appleWwdrIntermediate: "1.2.840.113635.100.6.2.1",
} as const;

export interface Certificate {
  der: Uint8Array;
  tbs: Uint8Array;
  signatureAlgorithm: string;
  /** DER-encoded ECDSA signature (SEQUENCE { r, s }). */
  signature: Uint8Array;
  spki: Uint8Array;
  curve: "P-256" | "P-384";
  notBefore: Date;
  notAfter: Date;
  issuer: Uint8Array;
  subject: Uint8Array;
  extensionOids: Set<string>;
  isCA: boolean;
}

function parseTime(buf: Uint8Array, el: Der): Date {
  const s = new TextDecoder().decode(buf.subarray(el.contentStart, el.end));
  let m: RegExpMatchArray | null;
  if (el.tag === TAG.UTC_TIME && (m = s.match(/^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/))) {
    const yy = Number(m[1]);
    return new Date(Date.UTC(yy >= 50 ? 1900 + yy : 2000 + yy, Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6])));
  }
  if (el.tag === TAG.GEN_TIME && (m = s.match(/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/))) {
    return new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6])));
  }
  throw new Asn1Error("unsupported time format");
}

function expect(el: Der | undefined, tag: number, what: string): Der {
  if (!el || el.tag !== tag) throw new Asn1Error(`expected ${what}`);
  return el;
}

export function parseCertificate(der: Uint8Array): Certificate {
  const root = expect(readDer(der, 0), TAG.SEQUENCE, "certificate");
  if (root.end !== der.length) throw new Asn1Error("trailing bytes after certificate");
  const [tbsEl, algEl, sigEl] = children(der, root);
  expect(tbsEl, TAG.SEQUENCE, "tbsCertificate");
  expect(algEl, TAG.SEQUENCE, "signatureAlgorithm");
  expect(sigEl, TAG.BIT_STRING, "signature");

  const algOid = expect(children(der, algEl!)[0], TAG.OID, "algorithm OID");
  const signatureAlgorithm = decodeOid(der.subarray(algOid.contentStart, algOid.end));
  // BIT STRING: first content byte is the unused-bits count (0 for signatures).
  const signature = der.subarray(sigEl!.contentStart + 1, sigEl!.end);

  const tbsFields = children(der, tbsEl!);
  let i = 0;
  if (tbsFields[0]?.tag === 0xa0) i++; // [0] version
  i++; // serialNumber
  i++; // signature AlgorithmIdentifier
  const issuerEl = expect(tbsFields[i++], TAG.SEQUENCE, "issuer");
  const validityEl = expect(tbsFields[i++], TAG.SEQUENCE, "validity");
  const subjectEl = expect(tbsFields[i++], TAG.SEQUENCE, "subject");
  const spkiEl = expect(tbsFields[i++], TAG.SEQUENCE, "subjectPublicKeyInfo");

  const [nb, na] = children(der, validityEl);
  if (!nb || !na) throw new Asn1Error("bad validity");

  const spkiAlg = expect(children(der, spkiEl)[0], TAG.SEQUENCE, "spki algorithm");
  const [keyTypeEl, curveEl] = children(der, spkiAlg);
  const keyType = decodeOid(der.subarray(expect(keyTypeEl, TAG.OID, "key type").contentStart, keyTypeEl!.end));
  if (keyType !== OID.ecPublicKey) throw new Asn1Error("certificate key is not EC");
  const curveOid = decodeOid(der.subarray(expect(curveEl, TAG.OID, "curve").contentStart, curveEl!.end));
  const curve = curveOid === OID.p256 ? "P-256" : curveOid === OID.p384 ? "P-384" : null;
  if (!curve) throw new Asn1Error(`unsupported curve ${curveOid}`);

  const extensionOids = new Set<string>();
  let isCA = false;
  for (const f of tbsFields.slice(i)) {
    if (f.tag !== 0xa3) continue; // [3] extensions
    const extSeq = expect(children(der, f)[0], TAG.SEQUENCE, "extensions");
    for (const ext of children(der, extSeq)) {
      const parts = children(der, ext);
      const oidEl = expect(parts[0], TAG.OID, "extension OID");
      const oid = decodeOid(der.subarray(oidEl.contentStart, oidEl.end));
      extensionOids.add(oid);
      if (oid === OID.basicConstraints) {
        const octet = parts[parts.length - 1]!;
        const bc = readDer(der, octet.contentStart);
        const first = children(der, bc)[0];
        if (first && first.tag === 0x01 && der[first.contentStart] !== 0) isCA = true;
      }
    }
  }

  return {
    der,
    tbs: der.subarray(tbsEl!.start, tbsEl!.end),
    signatureAlgorithm,
    signature,
    spki: der.subarray(spkiEl.start, spkiEl.end),
    curve,
    notBefore: parseTime(der, nb),
    notAfter: parseTime(der, na),
    issuer: der.subarray(issuerEl.start, issuerEl.end),
    subject: der.subarray(subjectEl.start, subjectEl.end),
    extensionOids,
    isCA,
  };
}

/** Converts a DER ECDSA signature to the raw r||s form WebCrypto expects. */
export function derSignatureToRaw(sig: Uint8Array, size: number): Uint8Array {
  const seq = expect(readDer(sig, 0), TAG.SEQUENCE, "ECDSA signature");
  const [r, s] = children(sig, seq);
  const out = new Uint8Array(size * 2);
  [r, s].forEach((el, idx) => {
    expect(el, TAG.INTEGER, "ECDSA integer");
    let bytes = sig.subarray(el!.contentStart, el!.end);
    while (bytes.length > size && bytes[0] === 0) bytes = bytes.subarray(1);
    if (bytes.length > size) throw new Asn1Error("ECDSA integer too large");
    out.set(bytes, idx * size + (size - bytes.length));
  });
  return out;
}

export function pemToDer(pem: string): Uint8Array {
  const b64 = pem.replace(/-----(BEGIN|END) CERTIFICATE-----/g, "").replace(/\s+/g, "");
  return base64ToBytes(b64);
}

export function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function base64UrlToBytes(s: string): Uint8Array {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/");
  return base64ToBytes(b64 + "=".repeat((4 - (b64.length % 4)) % 4));
}

export function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}
