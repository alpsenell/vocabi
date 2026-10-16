import { ENTRIES_PER_PACK, LANGUAGE_NAMES, LANGUAGES, type Difficulty, type PackRequest } from "./types";

export const CEFR: Record<Difficulty, string> = {
  beginner: "CEFR A1–A2",
  intermediate: "CEFR B1–B2",
  advanced: "CEFR C1",
};

const CATEGORY_DESCRIPTIONS: Record<string, string> = {
  business: "business and the workplace",
  school: "school, studying and education",
  dailyLife: "everyday life at home and around town",
  travel: "travel, transport and holidays",
  technology: "technology, computers and the internet",
  health: "health, the body and medical care",
  food: "food, cooking and eating out",
};

/**
 * Stable part of the system prompt. Identical bytes on every request so it can be prompt-cached;
 * keep anything request-specific out of this string.
 */
export const STATIC_SYSTEM_PROMPT = `You are a lexicographer writing vocabulary cards for Vocabi, a language-learning app that shows one word per home-screen widget. Every card contains the same concept in four languages: English (en), Turkish (tr), French (fr) and Spanish (es).

Each card has:
- terms: the word in each language. Use a single word or a short fixed phrase (at most 3 words) that a native speaker would actually use for this concept. Give nouns without articles unless the article is part of a fixed expression.
- definitions: a short, natural definition in each language, at most 110 characters. Write each definition as a native speaker of that language would explain the word in a learner's dictionary. Do NOT translate the English definition word for word; phrase it idiomatically in each language. Never use the term itself inside its own definition.
- examples: exactly one natural example sentence per language that uses the term in context. Each sentence is written natively for that language, not translated literally from English.

Quality rules:
- Use US English spelling (color, center, organize).
- No proper nouns, brand names, people, places or trademarks.
- Each English term appears only once in the set, and must not be any of the terms the learner already knows (listed in the request).
- Terms must be correct, current and common for the requested level; prefer words a learner will meet in real life.
- Keep the four terms aligned to the same meaning. If a language has no exact single-word equivalent, use its most natural short phrase.
- Use correct accents and characters (ç, ğ, ı, İ, ş, ö, ü, é, è, ê, à, ñ, á, í, ó, ú, ¿, ¡).
- Content must be suitable for all ages.
- Set "category" and "difficulty" on every card to the requested values.

Return only JSON matching the provided schema.`;

/** Request-specific system block: languages, level, subject. */
export function requestSystemPrompt(req: PackRequest): string {
  const subject =
    req.topic !== null
      ? `the custom topic "${req.topic}" (use category "${req.category}" on every card)`
      : `the category "${req.category}" (${CATEGORY_DESCRIPTIONS[req.category] ?? req.category})`;
  return [
    `The learner's native language is ${LANGUAGE_NAMES[req.native]} (${req.native}) and they are learning ${LANGUAGE_NAMES[req.target]} (${req.target}).`,
    `The widget shows the ${LANGUAGE_NAMES[req.target]} term with the ${LANGUAGE_NAMES[req.native]} definition, so take extra care that those two are natural and accurate. All four languages are still required on every card.`,
    `Level: ${req.difficulty} (${CEFR[req.difficulty]}).`,
    `Subject: ${subject}.`,
    `Difficulty value for every card: "${req.difficulty}". Category value for every card: "${req.category}".`,
  ].join("\n");
}

export function userPrompt(req: PackRequest, avoidTerms: string[]): string {
  const lines = [`Write ${ENTRIES_PER_PACK} vocabulary cards for page ${req.page} of this set.`];
  if (avoidTerms.length > 0) {
    lines.push(
      `The learner already knows these English terms (from earlier pages or their own list). Do not use any of them or close variants:`,
      avoidTerms.join(", "),
    );
  }
  return lines.join("\n");
}

const languageMapSchema = {
  type: "object",
  properties: Object.fromEntries(LANGUAGES.map((l) => [l, { type: "string" }])),
  required: [...LANGUAGES],
  additionalProperties: false,
} as const;

/** Structured-output schema for generation. The server adds ids and topic afterwards. */
export const PACK_SCHEMA = {
  type: "object",
  properties: {
    entries: {
      type: "array",
      items: {
        type: "object",
        properties: {
          category: { type: "string" },
          difficulty: { type: "string" },
          terms: languageMapSchema,
          definitions: languageMapSchema,
          examples: languageMapSchema,
        },
        required: ["category", "difficulty", "terms", "definitions", "examples"],
        additionalProperties: false,
      },
    },
  },
  required: ["entries"],
  additionalProperties: false,
} as const;

export const VERIFY_SYSTEM_PROMPT = `You review vocabulary cards for a language-learning app. Each card gives one concept in English (en), Turkish (tr), French (fr) and Spanish (es) with a term, a definition and an example sentence per language.

Flag only real problems: a term that does not mean the same as the English term, a definition that is wrong or describes a different meaning, an example that misuses the term, wrong language, or clearly unnatural/literal phrasing a native speaker would not use. Do not flag style preferences or minor wording choices.

For each problem report the card's index (0-based, as given), the field (for example "terms.tr", "definitions.fr", "examples.es") and a short description. Return an empty issues list when everything is correct.`;

export const VERIFY_SCHEMA = {
  type: "object",
  properties: {
    issues: {
      type: "array",
      items: {
        type: "object",
        properties: {
          index: { type: "integer" },
          field: { type: "string" },
          problem: { type: "string" },
        },
        required: ["index", "field", "problem"],
        additionalProperties: false,
      },
    },
  },
  required: ["issues"],
  additionalProperties: false,
} as const;
