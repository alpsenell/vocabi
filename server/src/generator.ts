import { isoNow, makeEntryId, makePackId } from "./ids";
import { FALLBACK_BETA, GENERATION_MODEL, VERIFY_MODEL, responseText, type MessageCreator } from "./llm";
import {
  PACK_SCHEMA,
  STATIC_SYSTEM_PROMPT,
  VERIFY_SCHEMA,
  VERIFY_SYSTEM_PROMPT,
  requestSystemPrompt,
  userPrompt,
} from "./prompt";
import { ENTRIES_PER_PACK, LANGUAGES, PACK_VERSION, type PackRequest, type VocabEntry, type WordPack } from "./types";
import { ENTRY_TOLERANCE, termKey, validateGeneratedEntries, type GeneratedEntry } from "./validation";

export class GenerationError extends Error {
  constructor(message: string, readonly problems: string[] = []) {
    super(message);
    this.name = "GenerationError";
  }
}

export interface GenerateOptions {
  create: MessageCreator;
  /** English terms to avoid (earlier pages + client knownTerms). */
  avoidTerms: string[];
  verify: boolean;
  now?: Date;
  log?: (msg: string, data?: unknown) => void;
}

const MAX_AVOID_TERMS = 600;
const MIN_ENTRIES = ENTRIES_PER_PACK - ENTRY_TOLERANCE;

/** Builds the Claude request for one pack. Stable content first so the prefix is cacheable. */
export function buildGenerationParams(req: PackRequest, avoidTerms: string[]) {
  return {
    model: GENERATION_MODEL,
    max_tokens: 16000,
    betas: [FALLBACK_BETA],
    fallbacks: "default" as const,
    system: [
      { type: "text" as const, text: STATIC_SYSTEM_PROMPT, cache_control: { type: "ephemeral" as const } },
      { type: "text" as const, text: requestSystemPrompt(req) },
    ],
    output_config: {
      effort: "medium" as const,
      format: { type: "json_schema" as const, schema: PACK_SCHEMA as unknown as Record<string, unknown> },
    },
    messages: [{ role: "user" as const, content: userPrompt(req, avoidTerms.slice(0, MAX_AVOID_TERMS)) }],
  };
}

async function generateOnce(req: PackRequest, opts: GenerateOptions): Promise<GeneratedEntry[]> {
  const result = await opts.create(buildGenerationParams(req, opts.avoidTerms));
  if (result.stop_reason === "refusal") throw new GenerationError("model refused the request");
  if (result.stop_reason === "max_tokens") throw new GenerationError("model output was truncated");
  let parsed: { entries?: unknown };
  try {
    parsed = JSON.parse(responseText(result));
  } catch {
    throw new GenerationError("model output was not valid JSON");
  }
  // Drop cards that repeat terms the server already served on earlier pages, then validate.
  const avoid = new Set(opts.avoidTerms.map(termKey));
  const entries = Array.isArray(parsed.entries)
    ? (parsed.entries as GeneratedEntry[]).filter(
        (e) => !(typeof e?.terms?.en === "string" && avoid.has(termKey(e.terms.en))),
      )
    : parsed.entries;
  const problems = validateGeneratedEntries(entries);
  if (problems.length > 0) throw new GenerationError("generated pack failed validation", problems);
  return entries as GeneratedEntry[];
}

/** Cheap second opinion from Haiku. Returns the indexes of flagged entries (never throws). */
export async function verifyEntries(
  entries: GeneratedEntry[],
  create: MessageCreator,
  log: (msg: string, data?: unknown) => void = () => {},
): Promise<Set<number>> {
  const cards = entries.map((e, index) => ({ index, terms: e.terms, definitions: e.definitions, examples: e.examples }));
  try {
    const result = await create({
      model: VERIFY_MODEL,
      max_tokens: 16000,
      system: VERIFY_SYSTEM_PROMPT,
      output_config: {
        effort: "low",
        format: { type: "json_schema", schema: VERIFY_SCHEMA as unknown as Record<string, unknown> },
      },
      messages: [{ role: "user", content: `Review these cards:\n${JSON.stringify(cards)}` }],
    });
    if (result.stop_reason !== "end_turn") {
      log("verify: unexpected stop_reason, keeping all entries", { stop_reason: result.stop_reason });
      return new Set();
    }
    const parsed = JSON.parse(responseText(result)) as { issues?: Array<{ index: number; field: string; problem: string }> };
    const flagged = new Set<number>();
    for (const issue of parsed.issues ?? []) {
      if (Number.isInteger(issue.index) && issue.index >= 0 && issue.index < entries.length) flagged.add(issue.index);
    }
    if (flagged.size > 0) log("verify: flagged entries", parsed.issues);
    return flagged;
  } catch (err) {
    log("verify: failed, keeping all entries", String(err));
    return new Set();
  }
}

/** Turns validated model output into a WordPack: assigns ids/topic and forces the requested category/difficulty. */
export function assemblePack(req: PackRequest, entries: GeneratedEntry[], now: Date = new Date()): WordPack {
  const id = makePackId(req.native, req.target, req.difficulty, req.category, req.topic, req.page);
  const clean = (m: Record<string, string>) =>
    Object.fromEntries(LANGUAGES.map((l) => [l, (m[l] ?? "").trim()])) as VocabEntry["terms"];
  return {
    id,
    nativeLanguage: req.native,
    targetLanguage: req.target,
    difficulty: req.difficulty,
    category: req.category,
    topic: req.topic,
    entries: entries.map((e, i) => {
      const entry: VocabEntry = {
        id: makeEntryId(id, i),
        category: req.category,
        difficulty: req.difficulty,
        terms: clean(e.terms),
        definitions: clean(e.definitions),
        examples: clean(e.examples),
      };
      if (req.topic !== null) entry.topic = req.topic;
      return entry;
    }),
    createdAt: isoNow(now),
    version: PACK_VERSION,
  };
}

/** Generates one pack: generation with one retry, optional verification pass, assembly. */
export async function generatePack(req: PackRequest, opts: GenerateOptions): Promise<WordPack> {
  const log = opts.log ?? (() => {});
  let entries: GeneratedEntry[] | undefined;
  let lastError: unknown;
  for (let attempt = 1; attempt <= 2 && !entries; attempt++) {
    try {
      entries = await generateOnce(req, opts);
    } catch (err) {
      lastError = err;
      log(`generate: attempt ${attempt} failed`, err instanceof GenerationError ? { message: err.message, problems: err.problems.slice(0, 20) } : String(err));
    }
  }
  if (!entries) {
    if (lastError instanceof GenerationError) throw lastError;
    throw new GenerationError(`generation failed: ${String(lastError)}`);
  }

  if (opts.verify) {
    const flagged = await verifyEntries(entries, opts.create, log);
    if (flagged.size > 0) {
      const kept = entries.filter((_, i) => !flagged.has(i));
      if (kept.length >= MIN_ENTRIES) entries = kept;
      else log(`verify: ${flagged.size} flagged but only ${kept.length} would remain; keeping all`);
    }
  }
  return assemblePack(req, entries, opts.now);
}
