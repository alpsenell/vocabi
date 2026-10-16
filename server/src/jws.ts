import {
  OID,
  base64ToBytes,
  base64UrlToBytes,
  bytesEqual,
  derSignatureToRaw,
  parseCertificate,
  type Certificate,
} from "./asn1";

export const PRO_PRODUCT_IDS = ["com.alpsenel.wordwidget.pro.weekly", "com.alpsenel.wordwidget.pro.monthly"] as const;
export const DEFAULT_BUNDLE_ID = "com.alpsenel.wordwidget";
export const EXPIRY_GRACE_MS = 24 * 60 * 60 * 1000;
const ALLOWED_ENVIRONMENTS = new Set(["Sandbox", "Production"]);

/** The fields of Apple's JWSTransactionDecodedPayload the server checks. */
export interface TransactionPayload {
  bundleId?: string;
  productId?: string;
  expiresDate?: number;
  environment?: string;
  revocationDate?: number;
  originalTransactionId?: string;
  transactionId?: string;
  [key: string]: unknown;
}

export interface VerifyOptions {
  /** DER bytes of trusted root certificates (Apple Root CA G3 in production; a test root in tests). */
  trustedRoots: Uint8Array[];
  bundleId: string;
  productIds?: readonly string[];
  now?: Date;
  graceMs?: number;
  /** Require Apple's marker extensions on leaf/intermediate. Default true. */
  requireAppleOids?: boolean;
}

export type VerifyResult =
  | { ok: true; payload: TransactionPayload; expiresAt: number }
  | { ok: false; reason: string };

const fail = (reason: string): VerifyResult => ({ ok: false, reason });

const HASH_FOR_ALG: Record<string, string> = {
  [OID.ecdsaWithSHA256]: "SHA-256",
  [OID.ecdsaWithSHA384]: "SHA-384",
};

async function importKey(cert: Certificate): Promise<CryptoKey> {
  return crypto.subtle.importKey("spki", cert.spki, { name: "ECDSA", namedCurve: cert.curve }, false, ["verify"]);
}

/** True when `child` is signed by `parent`'s key and names it as issuer. */
async function isSignedBy(child: Certificate, parent: Certificate): Promise<boolean> {
  if (!bytesEqual(child.issuer, parent.subject)) return false;
  const hash = HASH_FOR_ALG[child.signatureAlgorithm];
  if (!hash) return false;
  try {
    const raw = derSignatureToRaw(child.signature, parent.curve === "P-256" ? 32 : 48);
    return await crypto.subtle.verify({ name: "ECDSA", hash }, await importKey(parent), raw, child.tbs);
  } catch {
    return false;
  }
}

const validAt = (c: Certificate, t: number) => c.notBefore.getTime() <= t && t <= c.notAfter.getTime();

/**
 * Verifies a StoreKit 2 signed transaction (`Transaction.jwsRepresentation`):
 * x5c chain to a trusted root, ES256 signature, bundle id, product id, expiry and environment.
 */
export async function verifyStoreKitTransaction(jws: string, opts: VerifyOptions): Promise<VerifyResult> {
  const now = (opts.now ?? new Date()).getTime();
  const parts = jws.split(".");
  if (parts.length !== 3) return fail("malformed JWS");
  const [h, p, s] = parts as [string, string, string];

  let header: { alg?: string; x5c?: unknown };
  let payload: TransactionPayload;
  try {
    header = JSON.parse(new TextDecoder().decode(base64UrlToBytes(h)));
    payload = JSON.parse(new TextDecoder().decode(base64UrlToBytes(p)));
  } catch {
    return fail("malformed JWS");
  }
  if (header.alg !== "ES256") return fail("unsupported alg");
  if (!Array.isArray(header.x5c) || header.x5c.length < 2 || header.x5c.length > 3) return fail("missing x5c chain");

  let chain: Certificate[];
  let roots: Certificate[];
  try {
    chain = (header.x5c as unknown[]).map((c) => {
      if (typeof c !== "string") throw new Error("x5c entry is not a string");
      return parseCertificate(base64ToBytes(c));
    });
    roots = opts.trustedRoots.map((r) => parseCertificate(r));
  } catch {
    return fail("invalid certificate");
  }

  const [leaf, intermediate] = chain as [Certificate, Certificate, ...Certificate[]];
  for (const c of chain) if (!validAt(c, now)) return fail("certificate expired or not yet valid");

  if (!intermediate.isCA) return fail("intermediate is not a CA");
  if (opts.requireAppleOids !== false) {
    if (!leaf.extensionOids.has(OID.appleReceiptSigning)) return fail("leaf is not a StoreKit signing certificate");
    if (!intermediate.extensionOids.has(OID.appleWwdrIntermediate)) return fail("intermediate is not Apple WWDR");
  }
  if (!(await isSignedBy(leaf, intermediate))) return fail("leaf not signed by intermediate");

  // Anchor: either the chain carries the trusted root itself, or the intermediate is signed by one.
  const top = chain[chain.length - 1]!;
  let anchored = false;
  if (chain.length === 3) {
    const root = roots.find((r) => bytesEqual(r.der, top.der));
    anchored = root !== undefined && validAt(root, now) && (await isSignedBy(intermediate, top));
  } else {
    for (const root of roots) {
      if (validAt(root, now) && (await isSignedBy(intermediate, root))) {
        anchored = true;
        break;
      }
    }
  }
  if (!anchored) return fail("chain does not lead to a trusted root");

  try {
    const sig = base64UrlToBytes(s);
    if (sig.length !== 64) return fail("bad signature");
    const ok = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      await importKey(leaf),
      sig,
      new TextEncoder().encode(`${h}.${p}`),
    );
    if (!ok) return fail("bad signature");
  } catch {
    return fail("bad signature");
  }

  if (payload.bundleId !== opts.bundleId) return fail("wrong bundle id");
  const products = opts.productIds ?? PRO_PRODUCT_IDS;
  if (typeof payload.productId !== "string" || !products.includes(payload.productId)) return fail("wrong product");
  if (typeof payload.environment !== "string" || !ALLOWED_ENVIRONMENTS.has(payload.environment)) {
    return fail("wrong environment");
  }
  if (payload.revocationDate !== undefined && payload.revocationDate !== null) return fail("transaction revoked");
  if (typeof payload.expiresDate !== "number") return fail("missing expiresDate");
  const expiresAt = payload.expiresDate + (opts.graceMs ?? EXPIRY_GRACE_MS);
  if (expiresAt <= now) return fail("subscription expired");

  return { ok: true, payload, expiresAt };
}
