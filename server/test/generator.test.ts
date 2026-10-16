import { describe, expect, it } from "vitest";
import { GenerationError, buildGenerationParams, generatePack } from "../src/generator";
import { PACK_SCHEMA, STATIC_SYSTEM_PROMPT } from "../src/prompt";
import type { PackRequest } from "../src/types";
import { fakeEntries, fakeEntry, scriptedLlm, textResult } from "./helpers/llm";

const req: PackRequest = {
  native: "tr", target: "en", difficulty: "beginner", category: "travel", topic: "sailing", page: 1, knownTerms: [],
};
const NOW = new Date("2026-10-16T10:00:00.250Z");

describe("buildGenerationParams", () => {
  it("targets Opus 5.5 with structured output, medium effort, refusal fallbacks and no thinking params", () => {
    const p = buildGenerationParams(req, ["boat"]);
    expect(p.model).toBe("claude-opus-5-5");
    expect(p.max_tokens).toBe(16000);
    expect(p.betas).toEqual(["server-side-fallback-2026-07-01"]);
    expect(p.fallbacks).toBe("default");
    expect(p.output_config).toEqual({ effort: "medium", format: { type: "json_schema", schema: PACK_SCHEMA } });
    expect(p).not.toHaveProperty("thinking");
    expect(p).not.toHaveProperty("temperature");
  });
  it("puts the stable prompt first with a cache breakpoint and request details after it", () => {
    const p = buildGenerationParams(req, ["boat", "anchor"]);
    expect(p.system[0]).toEqual({ type: "text", text: STATIC_SYSTEM_PROMPT, cache_control: { type: "ephemeral" } });
    expect(p.system[1]!.text).toContain("native language is Turkish");
    expect(p.system[1]!.text).toContain("learning English");
    expect(p.system[1]!.text).toContain("CEFR A1–A2");
    expect(p.system[1]!.text).toContain('custom topic "sailing"');
    expect(p.messages[0]!.content).toContain("boat, anchor");
    expect(JSON.stringify(PACK_SCHEMA)).toContain('"additionalProperties":false');
  });
  it("maps levels to CEFR and categories when there is no topic", () => {
    const p = buildGenerationParams({ ...req, topic: null, difficulty: "advanced", category: "dailyLife" }, []);
    expect(p.system[1]!.text).toContain("CEFR C1");
    expect(p.system[1]!.text).toContain('category "dailyLife"');
    expect(p.messages[0]!.content).not.toContain("already knows");
  });
});

describe("generatePack", () => {
  it("assigns ids and topic, and overrides category/difficulty", async () => {
    const llm = scriptedLlm();
    const pack = await generatePack(req, { create: llm.create, avoidTerms: [], verify: false, now: NOW });
    expect(pack.id).toBe("ai-tr-en-beginner-t_sailing-1");
    expect(pack.topic).toBe("sailing");
    expect(pack.createdAt).toBe("2026-10-16T10:00:00Z");
    expect(pack.version).toBe(1);
    expect(pack.entries).toHaveLength(40);
    expect(pack.entries[6]!.id).toBe("ai-tr-en-beginner-t_sailing-1-07");
    for (const e of pack.entries) {
      expect(e.category).toBe("travel"); // fake output says "food"
      expect(e.difficulty).toBe("beginner"); // fake output says "advanced"
      expect(e.topic).toBe("sailing");
    }
    expect(Object.keys(pack.entries[0]!)).toEqual(["id", "category", "difficulty", "terms", "definitions", "examples", "topic"]);
    expect(llm.calls).toHaveLength(1);
  });

  it("omits entry topic for standard packs", async () => {
    const llm = scriptedLlm();
    const pack = await generatePack({ ...req, topic: null }, { create: llm.create, avoidTerms: [], verify: false });
    expect(pack.id).toBe("ai-tr-en-beginner-travel-1");
    expect(pack.topic).toBeNull();
    expect(pack.entries[0]).not.toHaveProperty("topic");
  });

  it("retries once after an invalid generation", async () => {
    const llm = scriptedLlm({ generations: [textResult({ entries: fakeEntries(10) })] });
    const pack = await generatePack(req, { create: llm.create, avoidTerms: [], verify: false });
    expect(pack.entries).toHaveLength(40);
    expect(llm.calls).toHaveLength(2);
  });

  it("fails after two invalid generations", async () => {
    const bad = textResult({ entries: fakeEntries(10) });
    const llm = scriptedLlm({ generations: [bad, bad] });
    await expect(generatePack(req, { create: llm.create, avoidTerms: [], verify: false })).rejects.toBeInstanceOf(GenerationError);
    expect(llm.calls).toHaveLength(2);
  });

  it("treats refusals, truncation, bad JSON and thrown API errors as failures", async () => {
    for (const first of [textResult("{}", "refusal"), textResult("{", "max_tokens"), textResult("not json")]) {
      const llm = scriptedLlm({ generations: [first, first] });
      await expect(generatePack(req, { create: llm.create, avoidTerms: [], verify: false })).rejects.toThrow();
    }
    const throwing = async () => {
      throw new Error("529 overloaded");
    };
    await expect(generatePack(req, { create: throwing, avoidTerms: [], verify: false })).rejects.toBeInstanceOf(GenerationError);
  });

  it("drops entries repeating earlier-page terms before validating", async () => {
    const entries = [...fakeEntries(38), fakeEntry("Anchor"), fakeEntry("sail")];
    const llm = scriptedLlm({ generations: [textResult({ entries })] });
    const pack = await generatePack(req, { create: llm.create, avoidTerms: ["anchor", "sail"], verify: false });
    expect(pack.entries.map((e) => e.terms.en)).not.toContain("Anchor");
    expect(pack.entries).toHaveLength(38);
  });

  it("drops entries flagged by the Haiku verification pass when at least 35 remain", async () => {
    const llm = scriptedLlm({
      verifications: [textResult({ issues: [{ index: 0, field: "terms.tr", problem: "wrong" }, { index: 5, field: "examples.fr", problem: "x" }] })],
    });
    const pack = await generatePack(req, { create: llm.create, avoidTerms: [], verify: true });
    expect(pack.entries).toHaveLength(38);
    expect(pack.entries[0]!.terms.en).toBe("gen1w1");
    expect(pack.entries[0]!.id).toBe("ai-tr-en-beginner-t_sailing-1-01");
    const verifyCall = llm.calls[1]!;
    expect(verifyCall.model).toBe("claude-haiku-5-5");
    expect(verifyCall.output_config?.format?.type).toBe("json_schema");
  });

  it("keeps everything when dropping flagged entries would leave fewer than 35", async () => {
    const issues = Array.from({ length: 6 }, (_, index) => ({ index, field: "terms.es", problem: "x" }));
    const llm = scriptedLlm({ verifications: [textResult({ issues })] });
    const pack = await generatePack(req, { create: llm.create, avoidTerms: [], verify: true });
    expect(pack.entries).toHaveLength(40);
  });

  it("keeps everything when verification itself fails", async () => {
    const llm = scriptedLlm({ verifications: [textResult("garbage")] });
    const pack = await generatePack(req, { create: llm.create, avoidTerms: [], verify: true });
    expect(pack.entries).toHaveLength(40);
  });

  it("skips verification when disabled", async () => {
    const llm = scriptedLlm();
    await generatePack(req, { create: llm.create, avoidTerms: [], verify: false });
    expect(llm.calls.every((c) => c.model === "claude-opus-5-5")).toBe(true);
  });
});
