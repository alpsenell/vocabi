import type { LlmResult, MessageCreator, StreamParams } from "../../src/llm";
import type { GeneratedEntry } from "../../src/validation";

export function fakeEntry(term: string, overrides: Partial<GeneratedEntry> = {}): GeneratedEntry {
  return {
    category: "food",
    difficulty: "advanced",
    terms: { en: term, tr: `${term}-tr`, fr: `${term}-fr`, es: `${term}-es` },
    definitions: { en: `Meaning of ${term}.`, tr: `${term} anlamı.`, fr: `Sens de ${term}.`, es: `Significado de ${term}.` },
    examples: { en: `I use ${term}.`, tr: `${term} kullanırım.`, fr: `J'utilise ${term}.`, es: `Uso ${term}.` },
    ...overrides,
  };
}

export function fakeEntries(n: number, prefix = "word"): GeneratedEntry[] {
  return Array.from({ length: n }, (_, i) => fakeEntry(`${prefix}${i}`));
}

export const textResult = (payload: unknown, stop_reason = "end_turn"): LlmResult => ({
  stop_reason,
  content: [{ type: "text", text: typeof payload === "string" ? payload : JSON.stringify(payload) }],
});

/**
 * Scripted fake Claude: generation calls (Opus) pop from `generations`, verification calls (Haiku)
 * pop from `verifications`. Every request is recorded in `calls`.
 */
export function scriptedLlm(opts: { generations?: LlmResult[]; verifications?: LlmResult[]; defaultEntries?: number } = {}) {
  const calls: StreamParams[] = [];
  const generations = [...(opts.generations ?? [])];
  const verifications = [...(opts.verifications ?? [])];
  let counter = 0;
  const create: MessageCreator = async (params) => {
    calls.push(params);
    if (params.model.startsWith("claude-haiku")) return verifications.shift() ?? textResult({ issues: [] });
    const next = generations.shift();
    if (next) return next;
    counter++;
    return textResult({ entries: fakeEntries(opts.defaultEntries ?? 40, `gen${counter}w`) });
  };
  return { create, calls };
}
