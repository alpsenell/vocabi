import { describe, expect, it } from "vitest";
import { CRON_MAX_PACKS, listPackIds, runCron, selectMissing, standardCatalogue } from "../src/cron";
import { packIdFor } from "../src/packs";
import { MemoryKV } from "./helpers/kv";
import { scriptedLlm } from "./helpers/llm";

describe("standard catalogue", () => {
  it("covers 12 pairs × 3 levels × 7 categories × 2 pages = 504 unique packs", () => {
    const ids = standardCatalogue().map(packIdFor);
    expect(ids).toHaveLength(504);
    expect(new Set(ids).size).toBe(504);
    expect(ids).toContain("ai-tr-en-beginner-dailyLife-1");
    expect(ids).toContain("ai-es-fr-advanced-food-2");
    expect(ids.some((id) => /ai-(\w\w)-\1-/.test(id))).toBe(false);
  });
});

describe("selectMissing", () => {
  it("picks at most 40, page 1 first", () => {
    const picked = selectMissing(new Set());
    expect(picked).toHaveLength(CRON_MAX_PACKS);
    expect(picked.every((r) => r.page === 1)).toBe(true);
  });

  it("skips existing packs and only picks page 2 when page 1 exists", () => {
    const all = standardCatalogue();
    const page1 = all.filter((r) => r.page === 1).map(packIdFor);
    const existing = new Set(page1);
    existing.delete("ai-tr-en-beginner-food-1");
    const picked = selectMissing(existing).map(packIdFor);
    expect(picked[0]).toBe("ai-tr-en-beginner-food-1");
    expect(picked).not.toContain("ai-tr-en-beginner-food-2");
    expect(picked.slice(1).every((id) => id.endsWith("-2"))).toBe(true);
    expect(picked).toHaveLength(40);
  });

  it("returns nothing when the catalogue is complete", () => {
    expect(selectMissing(new Set(standardCatalogue().map(packIdFor)))).toEqual([]);
  });
});

describe("runCron", () => {
  it("generates the selected packs into KV and lists them across pages", async () => {
    const kv = new MemoryKV();
    await kv.put("rl:topic:abc", "{}");
    await kv.put("ai-tr-en-beginner-t_sailing-1", "{}");
    const llm = scriptedLlm();
    const report = await runCron({ kv: kv.asKV(), create: llm.create, verify: false }, 5, 2);
    expect(report.generated).toHaveLength(5);
    expect(report.failed).toEqual([]);
    expect(llm.calls).toHaveLength(5);
    const ids = await listPackIds(kv.asKV());
    expect(ids.size).toBe(6);
    expect(ids.has("rl:topic:abc")).toBe(false);
  });

  it("records failures without stopping the run", async () => {
    const kv = new MemoryKV();
    let n = 0;
    const llm = scriptedLlm();
    const flaky = async (p: Parameters<typeof llm.create>[0]) => {
      if (n++ < 2) throw new Error("overloaded");
      return llm.create(p);
    };
    const report = await runCron({ kv: kv.asKV(), create: flaky, verify: false }, 3, 1);
    expect(report.failed).toHaveLength(1); // first pack: both attempts failed
    expect(report.generated).toHaveLength(2);
  });
});
