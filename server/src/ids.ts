import type { Category, Difficulty, Language } from "./types";

// Characters Swift's `Character.isWhitespace` treats as whitespace (Unicode White_Space).
// JS `\s` differs slightly (it includes U+FEFF and lacks U+0085), so list them explicitly.
const WS = "\\t\\n\\v\\f\\r \\u0085\\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000";
const WS_RUN = new RegExp(`[${WS}]+`, "gu");
const WS_EDGES = new RegExp(`^[${WS}]+|[${WS}]+$`, "gu");

/** Mirrors `UserSettings.normalizeTopic` in Settings.swift: trim, lowercase, collapse whitespace. */
export function normalizeTopic(topic: string): string {
  return topic.replace(WS_EDGES, "").toLowerCase().replace(WS_RUN, " ").replace(WS_EDGES, "");
}

/** Mirrors `WordPack.makeID`: `ai-<native>-<target>-<level>-<category | t_<topic>>-<page>`. */
export function makePackId(
  native: Language,
  target: Language,
  difficulty: Difficulty,
  category: Category,
  topic: string | null,
  page: number,
): string {
  const subject = topic !== null ? "t_" + normalizeTopic(topic).replaceAll(" ", "_") : category;
  return `ai-${native}-${target}-${difficulty}-${subject}-${page}`;
}

/** Entry ids are `<packId>-<2-digit 1-based index>`, e.g. `ai-tr-en-beginner-food-1-07`. */
export function makeEntryId(packId: string, index: number): string {
  return `${packId}-${String(index + 1).padStart(2, "0")}`;
}

/** ISO-8601 with second precision, e.g. `2026-10-16T09:30:00Z`. */
export function isoNow(now: Date = new Date()): string {
  return now.toISOString().replace(/\.\d{3}Z$/, "Z");
}
