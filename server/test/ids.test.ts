import { describe, expect, it } from "vitest";
import { isoNow, makeEntryId, makePackId, normalizeTopic } from "../src/ids";

describe("normalizeTopic (mirrors UserSettings.normalizeTopic)", () => {
  it("trims, lowercases and collapses whitespace", () => {
    expect(normalizeTopic("  Job   Interviews\n")).toBe("job interviews");
    expect(normalizeTopic("Sailing")).toBe("sailing");
    expect(normalizeTopic("\tRock  Climbing　")).toBe("rock climbing");
    expect(normalizeTopic("   ")).toBe("");
  });
  it("lowercases non-ASCII like Swift's lowercased()", () => {
    expect(normalizeTopic("ÉCOLE Ünİ")).toBe("école üni̇");
  });
});

describe("makePackId (mirrors WordPack.makeID)", () => {
  it("uses the category for standard packs", () => {
    expect(makePackId("tr", "en", "beginner", "dailyLife", null, 1)).toBe("ai-tr-en-beginner-dailyLife-1");
  });
  it("uses t_<topic> with spaces as underscores for topic packs", () => {
    expect(makePackId("tr", "en", "beginner", "travel", "sailing", 1)).toBe("ai-tr-en-beginner-t_sailing-1");
    expect(makePackId("es", "fr", "advanced", "business", "  Job  Interviews ", 2)).toBe(
      "ai-es-fr-advanced-t_job_interviews-2",
    );
  });
});

describe("entry ids and dates", () => {
  it("formats entry ids as <packId>-<2-digit 1-based index>", () => {
    expect(makeEntryId("ai-tr-en-beginner-t_sailing-1", 6)).toBe("ai-tr-en-beginner-t_sailing-1-07");
    expect(makeEntryId("ai-tr-en-beginner-food-1", 0)).toBe("ai-tr-en-beginner-food-1-01");
    expect(makeEntryId("ai-tr-en-beginner-food-1", 39)).toBe("ai-tr-en-beginner-food-1-40");
  });
  it("emits ISO-8601 without fractional seconds (Swift .iso8601 compatible)", () => {
    expect(isoNow(new Date("2026-10-16T09:30:12.345Z"))).toBe("2026-10-16T09:30:12Z");
  });
});
