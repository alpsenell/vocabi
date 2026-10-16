// Wire types shared with the iOS app. These must match VocabCore's Swift Codable types
// (Models.swift `VocabEntry`, PackStore.swift `WordPack`) exactly.

export const LANGUAGES = ["en", "tr", "fr", "es"] as const;
export type Language = (typeof LANGUAGES)[number];

export const DIFFICULTIES = ["beginner", "intermediate", "advanced"] as const;
export type Difficulty = (typeof DIFFICULTIES)[number];

export const CATEGORIES = ["business", "school", "dailyLife", "travel", "technology", "health", "food"] as const;
export type Category = (typeof CATEGORIES)[number];

export type LanguageMap = Record<Language, string>;

export interface VocabEntry {
  id: string;
  category: Category;
  difficulty: Difficulty;
  terms: LanguageMap;
  definitions: LanguageMap;
  examples: LanguageMap;
  /** Present only for custom-topic packs (Swift encodes it with encodeIfPresent). */
  topic?: string;
}

export interface WordPack {
  id: string;
  nativeLanguage: Language;
  targetLanguage: Language;
  difficulty: Difficulty;
  category: Category;
  topic: string | null;
  entries: VocabEntry[];
  /** ISO-8601 without fractional seconds (Swift `.iso8601` rejects milliseconds). */
  createdAt: string;
  version: number;
}

/** Generator version reported in packs; bump to make clients refresh. */
export const PACK_VERSION = 1;
export const SERVER_VERSION = "1.0.0";
export const ENTRIES_PER_PACK = 40;

/** A pack request after validation. */
export interface PackRequest {
  native: Language;
  target: Language;
  difficulty: Difficulty;
  category: Category;
  /** Normalized topic or null. */
  topic: string | null;
  page: number;
  knownTerms: string[];
}

export interface Env {
  PACKS: KVNamespace;
  ANTHROPIC_API_KEY?: string;
  DEV_BYPASS_TOKEN?: string;
  VERIFY_PACKS?: string;
  APPLE_BUNDLE_ID?: string;
}

export const LANGUAGE_NAMES: Record<Language, string> = {
  en: "English",
  tr: "Turkish",
  fr: "French",
  es: "Spanish",
};
