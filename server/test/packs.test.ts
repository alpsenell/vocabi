import { describe, expect, it } from "vitest";
import { RateLimitedError, TOPIC_PACK_TTL_SECONDS, getOrCreatePack, type PackDeps } from "../src/packs";
import { TOPIC_LIMIT, TOPIC_WINDOW_MS, checkTopicQuota } from "../src/ratelimit";
import type { PackRequest, WordPack } from "../src/types";
import { MemoryKV } from "./helpers/kv";
import { scriptedLlm } from "./helpers/llm";

const INSTALL = "6f1c3b0e-8a7d-4a51-9c2e-1d2f3a4b5c6d";
const std: PackRequest = { native: "fr", target: "es", difficulty: "intermediate", category: "health", topic: null, page: 1, knownTerms: [] };

function setup(nowMs = Date.parse("2026-10-16T10:00:00Z")) {
  const kv = new MemoryKV();
  const llm = scriptedLlm();
  let now = nowMs;
  const deps: PackDeps = { kv: kv.asKV(), create: llm.create, verify: false, now: () => new Date(now) };
  return { kv, llm, deps, advance: (ms: number) => (now += ms) };
}

describe("pack cache", () => {
  it("generates on miss, stores without expiry, then serves the cached bytes", async () => {
    const { kv, llm, deps } = setup();
    const first = await getOrCreatePack(std, INSTALL, deps);
    expect(first.source).toBe("generated");
    expect(kv.puts).toEqual([{ key: "ai-fr-es-intermediate-health-1", expirationTtl: undefined }]);
    const second = await getOrCreatePack(std, INSTALL, deps);
    expect(second).toEqual({ source: "cache", body: first.body });
    expect(llm.calls).toHaveLength(1);
  });

  it("stores topic packs for 90 days", async () => {
    const { kv, deps } = setup();
    await getOrCreatePack({ ...std, topic: "sailing" }, INSTALL, deps);
    expect(kv.puts.find((p) => p.key === "ai-fr-es-intermediate-t_sailing-1")?.expirationTtl).toBe(TOPIC_PACK_TTL_SECONDS);
  });

  it("passes earlier pages' English terms and client knownTerms as terms to avoid", async () => {
    const { llm, deps } = setup();
    const page1 = JSON.parse((await getOrCreatePack(std, INSTALL, deps)).body) as WordPack;
    await getOrCreatePack({ ...std, page: 2, knownTerms: ["stethoscope"] }, INSTALL, deps);
    const prompt = llm.calls[1]!.messages[0]!.content as string;
    expect(prompt).toContain(page1.entries[0]!.terms.en);
    expect(prompt).toContain(page1.entries[39]!.terms.en);
    expect(prompt).toContain("stethoscope");
  });

  it("shares one generation between concurrent identical requests", async () => {
    const { llm, deps } = setup();
    const [a, b] = await Promise.all([getOrCreatePack(std, INSTALL, deps), getOrCreatePack(std, INSTALL, deps)]);
    expect(a.body).toBe(b.body);
    expect(llm.calls).toHaveLength(1);
  });

  it("fails cleanly when no API key is configured", async () => {
    const { deps } = setup();
    await expect(getOrCreatePack(std, INSTALL, { ...deps, create: null })).rejects.toThrow("ANTHROPIC_API_KEY");
  });
});

describe("custom topic rate limit", () => {
  it("allows 10 topic generations per install per 7 days; cache hits and standard packs don't count", async () => {
    const { kv, llm, deps, advance } = setup();
    for (let i = 0; i < TOPIC_LIMIT; i++) await getOrCreatePack({ ...std, topic: `topic ${i}` }, INSTALL, deps);
    // Cache hit on an existing topic still works and doesn't count.
    expect((await getOrCreatePack({ ...std, topic: "topic 0" }, INSTALL, deps)).source).toBe("cache");
    // Standard packs are unlimited.
    expect((await getOrCreatePack({ ...std, page: 3 }, INSTALL, deps)).source).toBe("generated");

    const err = await getOrCreatePack({ ...std, topic: "one too many" }, INSTALL, deps).catch((e) => e);
    expect(err).toBeInstanceOf(RateLimitedError);
    expect((err as RateLimitedError).retryAfterSeconds).toBe(TOPIC_WINDOW_MS / 1000);
    expect(llm.calls).toHaveLength(TOPIC_LIMIT + 1);

    // Another install is unaffected.
    await getOrCreatePack({ ...std, topic: "one too many" }, "00000000-0000-4000-8000-000000000000", deps);

    // The window rolls.
    advance(TOPIC_WINDOW_MS + 1);
    expect(await checkTopicQuota(kv.asKV(), INSTALL, Date.parse("2026-10-16T10:00:00Z") + TOPIC_WINDOW_MS + 1)).toEqual({
      allowed: true,
      remaining: TOPIC_LIMIT,
    });
    await expect(getOrCreatePack({ ...std, topic: "later" }, INSTALL, deps)).resolves.toMatchObject({ source: "generated" });
  });

  it("does not count failed generations", async () => {
    const { kv, deps } = setup();
    const failing = { ...deps, create: async () => { throw new Error("boom"); } };
    await expect(getOrCreatePack({ ...std, topic: "sailing" }, INSTALL, failing)).rejects.toThrow();
    expect(await checkTopicQuota(kv.asKV(), INSTALL, Date.parse("2026-10-16T10:00:00Z"))).toEqual({ allowed: true, remaining: 10 });
  });
});
