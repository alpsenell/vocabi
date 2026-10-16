import { describe, expect, it } from "vitest";
import { parsePackRequest, validateGeneratedEntries } from "../src/validation";
import { fakeEntries, fakeEntry } from "./helpers/llm";

const base = { native: "tr", target: "en", difficulty: "beginner", category: "food" };

describe("parsePackRequest", () => {
  it("accepts a minimal body and defaults page/topic/knownTerms", () => {
    const r = parsePackRequest(base);
    expect(r).toEqual({ ok: true, value: { ...base, topic: null, page: 1, knownTerms: [] } });
  });
  it("normalizes the topic and treats blank topics as none", () => {
    const r = parsePackRequest({ ...base, topic: "  Sailing  Boats ", page: 2, knownTerms: [" boat ", ""] });
    expect(r.ok && r.value).toMatchObject({ topic: "sailing boats", page: 2, knownTerms: ["boat"] });
    const blank = parsePackRequest({ ...base, topic: "   " });
    expect(blank.ok && blank.value.topic).toBeNull();
  });
  it.each([
    [{ ...base, native: "de" }, "native"],
    [{ ...base, target: "tr" }, "differ"],
    [{ ...base, difficulty: "expert" }, "difficulty"],
    [{ ...base, category: "sports" }, "category"],
    [{ ...base, page: 0 }, "page"],
    [{ ...base, page: 1.5 }, "page"],
    [{ ...base, topic: 5 }, "topic"],
    [{ ...base, topic: "x".repeat(41) }, "topic"],
    [{ ...base, knownTerms: "boat" }, "knownTerms"],
    [{ ...base, knownTerms: [1] }, "knownTerms"],
    [[], "object"],
    [null, "object"],
  ])("rejects %j", (body, fragment) => {
    const r = parsePackRequest(body);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.message).toContain(fragment);
  });
});

describe("validateGeneratedEntries", () => {
  it("accepts 35-45 complete, unique entries", () => {
    expect(validateGeneratedEntries(fakeEntries(40))).toEqual([]);
    expect(validateGeneratedEntries(fakeEntries(35))).toEqual([]);
    expect(validateGeneratedEntries(fakeEntries(45))).toEqual([]);
  });
  it("rejects wrong counts", () => {
    expect(validateGeneratedEntries(fakeEntries(34))[0]).toContain("expected 35-45");
    expect(validateGeneratedEntries(fakeEntries(46))[0]).toContain("expected 35-45");
    expect(validateGeneratedEntries("nope")).toEqual(["entries is not an array"]);
  });
  it("rejects empty languages, long definitions and duplicate English terms", () => {
    const entries = fakeEntries(40);
    entries[3] = fakeEntry("blank", { terms: { en: "blank", tr: " ", fr: "x", es: "y" } });
    entries[4] = fakeEntry("long", {
      definitions: { en: "a".repeat(121), tr: "b", fr: "c", es: "d" },
    });
    entries[5] = fakeEntry("Word0");
    const problems = validateGeneratedEntries(entries);
    expect(problems).toContain("#3: terms.tr is empty");
    expect(problems).toContain("#4: definitions.en longer than 120 characters");
    expect(problems).toContain('#5: duplicate English term "Word0"');
  });
  it("counts characters, not UTF-16 units or bytes", () => {
    const entries = fakeEntries(40);
    entries[0] = fakeEntry("ok", { definitions: { en: "é".repeat(120), tr: "ğ".repeat(120), fr: "x", es: "y" } });
    expect(validateGeneratedEntries(entries)).toEqual([]);
  });
});
