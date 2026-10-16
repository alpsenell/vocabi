import { describe, expect, it } from "vitest";
import { createApp } from "../src/index";
import type { Env, WordPack } from "../src/types";
import { makeChain, signTransaction, transactionPayload } from "./helpers/certs";
import { MemoryKV } from "./helpers/kv";
import { scriptedLlm } from "./helpers/llm";

const INSTALL = "6F1C3B0E-8A7D-4A51-9C2E-1D2F3A4B5C6D";

function setup(envOverrides: Partial<Env> = {}, llm = scriptedLlm()) {
  const chain = makeChain();
  const kv = new MemoryKV();
  const app = createApp({ createMessage: () => llm.create, auth: { trustedRoots: [chain.root] } });
  const env: Env = { PACKS: kv.asKV(), DEV_BYPASS_TOKEN: "devtoken", VERIFY_PACKS: "false", APPLE_BUNDLE_ID: "com.alpsenel.wordwidget", ...envOverrides };
  const waits: Promise<unknown>[] = [];
  const ctx = { waitUntil: (p: Promise<unknown>) => waits.push(p), passThroughOnException() {} } as unknown as ExecutionContext;
  const call = (path: string, init: RequestInit = {}) => app.fetch(new Request(`https://packs.test${path}`, init), env, ctx);
  const post = (body: unknown, headers: Record<string, string> = {}) =>
    call("/v1/packs", {
      method: "POST",
      headers: { authorization: "Bearer dev:devtoken", "x-vocabi-install": INSTALL, "content-type": "application/json", ...headers },
      body: typeof body === "string" ? body : JSON.stringify(body),
    });
  return { app, env, kv, llm, chain, call, post, waits };
}

const body = { native: "tr", target: "en", difficulty: "beginner", category: "travel", topic: "Sailing", page: 1 };

describe("HTTP API", () => {
  it("GET /v1/health", async () => {
    const { call } = setup();
    const res = await call("/v1/health");
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, version: "1.0.0" });
  });

  it("returns a WordPack matching the Swift contract", async () => {
    const { post, waits } = setup();
    const res = await post(body);
    expect(res.status).toBe(200);
    expect(res.headers.get("x-vocabi-cache")).toBe("miss");
    expect(waits).toHaveLength(1);
    const pack = (await res.json()) as WordPack;
    expect(Object.keys(pack)).toEqual(["id", "nativeLanguage", "targetLanguage", "difficulty", "category", "topic", "entries", "createdAt", "version"]);
    expect(pack).toMatchObject({
      id: "ai-tr-en-beginner-t_sailing-1", nativeLanguage: "tr", targetLanguage: "en", difficulty: "beginner",
      category: "travel", topic: "sailing", version: 1,
    });
    expect(pack.createdAt).toMatch(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
    expect(pack.entries).toHaveLength(40);
    expect(pack.entries[6]).toMatchObject({ id: "ai-tr-en-beginner-t_sailing-1-07", category: "travel", difficulty: "beginner", topic: "sailing" });
    expect(Object.keys(pack.entries[0]!.terms).sort()).toEqual(["en", "es", "fr", "tr"]);

    const again = await post(body);
    expect(again.headers.get("x-vocabi-cache")).toBe("hit");
  });

  it("returns topic null for standard packs", async () => {
    const { post } = setup();
    const pack = (await (await post({ ...body, topic: undefined })).json()) as WordPack;
    expect(pack.id).toBe("ai-tr-en-beginner-travel-1");
    expect(pack.topic).toBeNull();
  });

  it("accepts a valid StoreKit transaction", async () => {
    const { post, chain } = setup();
    const res = await post(body, { authorization: `Bearer ${signTransaction(chain, transactionPayload())}` });
    expect(res.status).toBe(200);
  });

  it("401 for missing, invalid, expired or disabled tokens", async () => {
    const { post, chain } = setup();
    const expired = signTransaction(chain, transactionPayload({ expiresDate: Date.now() - 2 * 86_400_000 }));
    for (const authorization of ["", "Bearer nope", "Bearer dev:wrong", `Bearer ${expired}`]) {
      const res = await post(body, { authorization });
      expect(res.status).toBe(401);
      expect(await res.json()).toMatchObject({ error: "unauthorized" });
    }
    const noDev = setup({ DEV_BYPASS_TOKEN: undefined });
    expect((await noDev.post(body)).status).toBe(401);
  });

  it("400 for bad install ids and bodies", async () => {
    const { post } = setup();
    expect((await post(body, { "x-vocabi-install": "abc" })).status).toBe(400);
    expect((await post("{not json")).status).toBe(400);
    const res = await post({ ...body, native: "en" });
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: "invalid_request", message: "native and target must differ." });
  });

  it("429 with Retry-After after 10 new custom topics", async () => {
    const { post } = setup();
    for (let i = 0; i < 10; i++) expect((await post({ ...body, topic: `topic ${i}` })).status).toBe(200);
    const res = await post({ ...body, topic: "eleventh" });
    expect(res.status).toBe(429);
    expect(Number(res.headers.get("retry-after"))).toBeGreaterThan(0);
    expect(await res.json()).toMatchObject({ error: "rate_limited" });
  });

  it("502 when generation fails twice", async () => {
    const failing = { create: async () => { throw new Error("overloaded"); }, calls: [] };
    const { post } = setup({}, failing as unknown as ReturnType<typeof scriptedLlm>);
    const res = await post(body);
    expect(res.status).toBe(502);
    expect(await res.json()).toMatchObject({ error: "generation_failed" });
  });

  it("404 / 405 for other routes and methods", async () => {
    const { call } = setup();
    expect((await call("/nope")).status).toBe(404);
    expect((await call("/v1/packs")).status).toBe(405);
  });

  it("runs verification when VERIFY_PACKS=true", async () => {
    const { post, llm } = setup({ VERIFY_PACKS: "true" });
    await post(body);
    expect(llm.calls.map((c) => c.model)).toEqual(["claude-opus-5-5", "claude-haiku-5-5"]);
  });
});
