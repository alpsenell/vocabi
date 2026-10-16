import { normalizeTopic } from "./ids";
import {
  CATEGORIES,
  DIFFICULTIES,
  ENTRIES_PER_PACK,
  LANGUAGES,
  type Category,
  type Difficulty,
  type Language,
  type LanguageMap,
  type PackRequest,
} from "./types";

export const MAX_PAGE = 50;
export const MAX_TOPIC_LENGTH = 40;
export const MAX_KNOWN_TERMS = 1000;
export const MAX_KNOWN_TERM_LENGTH = 64;
export const ENTRY_TOLERANCE = 5;
export const MAX_DEFINITION_CHARS = 120;

export type ParseResult<T> = { ok: true; value: T } | { ok: false; message: string };

const isLanguage = (v: unknown): v is Language => typeof v === "string" && (LANGUAGES as readonly string[]).includes(v);
const isDifficulty = (v: unknown): v is Difficulty =>
  typeof v === "string" && (DIFFICULTIES as readonly string[]).includes(v);
const isCategory = (v: unknown): v is Category => typeof v === "string" && (CATEGORIES as readonly string[]).includes(v);

const charCount = (s: string) => [...s].length;

/** Validates the `POST /v1/packs` body. */
export function parsePackRequest(body: unknown): ParseResult<PackRequest> {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { ok: false, message: "Body must be a JSON object." };
  }
  const b = body as Record<string, unknown>;
  if (!isLanguage(b.native)) return { ok: false, message: `native must be one of ${LANGUAGES.join(", ")}.` };
  if (!isLanguage(b.target)) return { ok: false, message: `target must be one of ${LANGUAGES.join(", ")}.` };
  if (b.native === b.target) return { ok: false, message: "native and target must differ." };
  if (!isDifficulty(b.difficulty)) {
    return { ok: false, message: `difficulty must be one of ${DIFFICULTIES.join(", ")}.` };
  }
  if (!isCategory(b.category)) return { ok: false, message: `category must be one of ${CATEGORIES.join(", ")}.` };

  let topic: string | null = null;
  if (b.topic !== undefined && b.topic !== null) {
    if (typeof b.topic !== "string") return { ok: false, message: "topic must be a string." };
    const normalized = normalizeTopic(b.topic);
    if (normalized.length > 0) {
      if (charCount(normalized) > MAX_TOPIC_LENGTH) {
        return { ok: false, message: `topic must be at most ${MAX_TOPIC_LENGTH} characters.` };
      }
      if (/[\p{Cc}\p{Cf}]/u.test(normalized)) {
        return { ok: false, message: "topic contains unsupported characters." };
      }
      topic = normalized;
    }
  }

  const page = b.page === undefined ? 1 : b.page;
  if (typeof page !== "number" || !Number.isInteger(page) || page < 1 || page > MAX_PAGE) {
    return { ok: false, message: `page must be an integer between 1 and ${MAX_PAGE}.` };
  }

  let knownTerms: string[] = [];
  if (b.knownTerms !== undefined && b.knownTerms !== null) {
    if (!Array.isArray(b.knownTerms)) return { ok: false, message: "knownTerms must be an array of strings." };
    if (b.knownTerms.length > MAX_KNOWN_TERMS) {
      return { ok: false, message: `knownTerms may contain at most ${MAX_KNOWN_TERMS} items.` };
    }
    for (const t of b.knownTerms) {
      if (typeof t !== "string") return { ok: false, message: "knownTerms must be an array of strings." };
    }
    knownTerms = (b.knownTerms as string[])
      .map((t) => t.trim())
      .filter((t) => t.length > 0 && charCount(t) <= MAX_KNOWN_TERM_LENGTH);
  }

  return {
    ok: true,
    value: { native: b.native, target: b.target, difficulty: b.difficulty, category: b.category, topic, page, knownTerms },
  };
}

/** The shape the model returns (before the server assigns ids and topic). */
export interface GeneratedEntry {
  category: string;
  difficulty: string;
  terms: LanguageMap;
  definitions: LanguageMap;
  examples: LanguageMap;
}

export const termKey = (term: string) => term.trim().toLowerCase();

/**
 * Checks a generated pack against the quality rules. Returns a list of problems (empty = valid).
 * Rules: 40 ± 5 entries, every language non-empty in terms/definitions/examples,
 * definitions ≤ 120 characters, unique English terms.
 */
export function validateGeneratedEntries(entries: unknown): string[] {
  const problems: string[] = [];
  if (!Array.isArray(entries)) return ["entries is not an array"];
  const min = ENTRIES_PER_PACK - ENTRY_TOLERANCE;
  const max = ENTRIES_PER_PACK + ENTRY_TOLERANCE;
  if (entries.length < min || entries.length > max) {
    problems.push(`expected ${min}-${max} entries, got ${entries.length}`);
  }
  const seen = new Set<string>();
  entries.forEach((raw, i) => {
    const e = raw as Partial<GeneratedEntry> | null;
    if (typeof e !== "object" || e === null) {
      problems.push(`#${i}: not an object`);
      return;
    }
    for (const field of ["terms", "definitions", "examples"] as const) {
      const map = e[field] as Record<string, unknown> | undefined;
      for (const lang of LANGUAGES) {
        const v = map?.[lang];
        if (typeof v !== "string" || v.trim().length === 0) problems.push(`#${i}: ${field}.${lang} is empty`);
        else if (field === "definitions" && charCount(v) > MAX_DEFINITION_CHARS) {
          problems.push(`#${i}: definitions.${lang} longer than ${MAX_DEFINITION_CHARS} characters`);
        }
      }
    }
    const en = e.terms?.en;
    if (typeof en === "string" && en.trim().length > 0) {
      const key = termKey(en);
      if (seen.has(key)) problems.push(`#${i}: duplicate English term "${en}"`);
      seen.add(key);
    }
  });
  return problems;
}
