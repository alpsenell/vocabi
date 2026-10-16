import { generatePack } from "./generator";
import { makePackId } from "./ids";
import type { MessageCreator } from "./llm";
import { checkTopicQuota, recordTopicGeneration } from "./ratelimit";
import type { PackRequest, WordPack } from "./types";

export const TOPIC_PACK_TTL_SECONDS = 90 * 24 * 60 * 60;

export class RateLimitedError extends Error {
  constructor(readonly retryAfterSeconds: number) {
    super("rate limited");
    this.name = "RateLimitedError";
  }
}

export interface PackDeps {
  kv: KVNamespace;
  /** Null when no API key is configured: cache hits still work, misses fail with 502. */
  create: MessageCreator | null;
  verify: boolean;
  now?: () => Date;
  log?: (msg: string, data?: unknown) => void;
}

export interface PackResult {
  source: "cache" | "generated";
  /** Serialized WordPack, returned verbatim to the client. */
  body: string;
}

/** Generations in flight in this isolate, so concurrent identical requests share one Claude call. */
const inFlight = new Map<string, Promise<string>>();

export const packIdFor = (req: PackRequest) =>
  makePackId(req.native, req.target, req.difficulty, req.category, req.topic, req.page);

/** English terms from earlier pages of the same set, read from KV. */
export async function previousPageTerms(kv: KVNamespace, req: PackRequest): Promise<string[]> {
  if (req.page <= 1) return [];
  const ids = Array.from({ length: req.page - 1 }, (_, i) => packIdFor({ ...req, page: i + 1 }));
  const packs = await Promise.all(ids.map((id) => kv.get<WordPack>(id, "json")));
  return packs.flatMap((p) => p?.entries.map((e) => e.terms.en) ?? []);
}

/** Generates a pack and stores it in KV (standard packs forever, topic packs for 90 days). */
export async function generateAndStore(req: PackRequest, deps: PackDeps): Promise<string> {
  const id = packIdFor(req);
  const existing = inFlight.get(id);
  if (existing) return existing;
  const run = (async () => {
    if (!deps.create) throw new Error("ANTHROPIC_API_KEY is not configured");
    const earlier = await previousPageTerms(deps.kv, req);
    const seen = new Set<string>();
    const avoidTerms = [...earlier, ...req.knownTerms].filter((t) => {
      const k = t.trim().toLowerCase();
      if (seen.has(k)) return false;
      seen.add(k);
      return true;
    });
    const pack = await generatePack(req, {
      create: deps.create,
      avoidTerms,
      verify: deps.verify,
      now: deps.now?.(),
      log: deps.log,
    });
    const body = JSON.stringify(pack);
    await deps.kv.put(id, body, req.topic !== null ? { expirationTtl: TOPIC_PACK_TTL_SECONDS } : undefined);
    deps.log?.(`generated ${id}`, { entries: pack.entries.length });
    return body;
  })();
  inFlight.set(id, run);
  try {
    return await run;
  } finally {
    inFlight.delete(id);
  }
}

/** Serves a pack from KV, or generates it on a miss (custom topics are rate limited per install). */
export async function getOrCreatePack(req: PackRequest, installId: string, deps: PackDeps): Promise<PackResult> {
  const id = packIdFor(req);
  const cached = await deps.kv.get(id, "text");
  if (cached !== null) return { source: "cache", body: cached };

  if (req.topic !== null) {
    if (inFlight.has(id)) return { source: "generated", body: await inFlight.get(id)! };
    const now = (deps.now?.() ?? new Date()).getTime();
    const quota = await checkTopicQuota(deps.kv, installId, now);
    if (!quota.allowed) throw new RateLimitedError(quota.retryAfterSeconds);
    const body = await generateAndStore(req, deps);
    await recordTopicGeneration(deps.kv, installId, now);
    return { source: "generated", body };
  }
  return { source: "generated", body: await generateAndStore(req, deps) };
}
