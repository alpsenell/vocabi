import { pemToDer } from "./asn1";
import { APPLE_ROOT_CA_G3_PEM } from "./appleRoot";
import { DEFAULT_BUNDLE_ID, verifyStoreKitTransaction } from "./jws";

export type AuthResult = { ok: true; kind: "storekit" | "dev"; expiresAt: number } | { ok: false; reason: string };

export interface AuthConfig {
  bundleId?: string;
  devBypassToken?: string;
  trustedRoots?: Uint8Array[];
  now?: () => number;
}

const MAX_CACHE = 2000;
/** Failed verifications are re-checked after this long (in case of a clock/cert issue). */
const NEGATIVE_TTL_MS = 10 * 60 * 1000;

let appleRoots: Uint8Array[] | undefined;
const defaultRoots = () => (appleRoots ??= [pemToDer(APPLE_ROOT_CA_G3_PEM)]);

async function sha256Hex(s: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function timingSafeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  let diff = ea.length ^ eb.length;
  for (let i = 0; i < Math.max(ea.length, eb.length); i++) diff |= (ea[i] ?? 0) ^ (eb[i] ?? 0);
  return diff === 0;
}

/**
 * Checks `Authorization: Bearer <token>` and caches the verdict per token hash for the isolate lifetime.
 * Successful verdicts are re-evaluated against their expiry on every hit.
 */
export class Authenticator {
  private cache = new Map<string, { result: AuthResult; checkedAt: number }>();

  constructor(private readonly config: AuthConfig = {}) {}

  private now(): number {
    return this.config.now?.() ?? Date.now();
  }

  async authenticate(authorization: string | null): Promise<AuthResult> {
    const match = authorization?.match(/^Bearer\s+(.+)$/i);
    if (!match) return { ok: false, reason: "missing bearer token" };
    const token = match[1]!.trim();

    if (token.startsWith("dev:")) {
      const secret = this.config.devBypassToken;
      if (!secret) return { ok: false, reason: "dev bypass disabled" };
      return timingSafeEqual(token.slice(4), secret)
        ? { ok: true, kind: "dev", expiresAt: Number.MAX_SAFE_INTEGER }
        : { ok: false, reason: "invalid dev token" };
    }

    const key = await sha256Hex(token);
    const now = this.now();
    const cached = this.cache.get(key);
    if (cached) {
      const r = cached.result;
      if (r.ok) return r.expiresAt > now ? r : { ok: false, reason: "subscription expired" };
      if (now - cached.checkedAt < NEGATIVE_TTL_MS) return r;
    }

    const verdict = await verifyStoreKitTransaction(token, {
      trustedRoots: this.config.trustedRoots ?? defaultRoots(),
      bundleId: this.config.bundleId ?? DEFAULT_BUNDLE_ID,
      now: new Date(now),
    });
    const result: AuthResult = verdict.ok
      ? { ok: true, kind: "storekit", expiresAt: verdict.expiresAt }
      : { ok: false, reason: verdict.reason };

    if (this.cache.size >= MAX_CACHE) {
      const oldest = this.cache.keys().next().value;
      if (oldest !== undefined) this.cache.delete(oldest);
    }
    this.cache.set(key, { result, checkedAt: now });
    return result;
  }

  get cacheSize(): number {
    return this.cache.size;
  }
}
