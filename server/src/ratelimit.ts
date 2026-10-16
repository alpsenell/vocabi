export const TOPIC_LIMIT = 10;
export const TOPIC_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

const key = (installId: string) => `rl:topic:${installId.toLowerCase()}`;

interface Bucket {
  ts: number[];
}

async function load(kv: KVNamespace, installId: string, now: number): Promise<number[]> {
  const bucket = await kv.get<Bucket>(key(installId), "json");
  return (bucket?.ts ?? []).filter((t) => typeof t === "number" && now - t < TOPIC_WINDOW_MS);
}

export type QuotaResult = { allowed: true; remaining: number } | { allowed: false; retryAfterSeconds: number };

/** Custom-topic generations allowed per install: 10 per rolling 7 days. Cache hits never count. */
export async function checkTopicQuota(kv: KVNamespace, installId: string, now: number): Promise<QuotaResult> {
  const ts = await load(kv, installId, now);
  if (ts.length < TOPIC_LIMIT) return { allowed: true, remaining: TOPIC_LIMIT - ts.length };
  const oldest = Math.min(...ts);
  return { allowed: false, retryAfterSeconds: Math.max(1, Math.ceil((oldest + TOPIC_WINDOW_MS - now) / 1000)) };
}

export async function recordTopicGeneration(kv: KVNamespace, installId: string, now: number): Promise<void> {
  const ts = await load(kv, installId, now);
  ts.push(now);
  await kv.put(key(installId), JSON.stringify({ ts } satisfies Bucket), {
    expirationTtl: Math.ceil(TOPIC_WINDOW_MS / 1000) + 3600,
  });
}
