import { generateAndStore, packIdFor, type PackDeps } from "./packs";
import { CATEGORIES, DIFFICULTIES, LANGUAGES, type PackRequest } from "./types";

export const CRON_MAX_PACKS = 40;
export const CRON_CONCURRENCY = 6;
export const CRON_PAGES = [1, 2] as const;

/** Every standard pack the catalogue should contain: 12 pairs × 3 levels × 7 categories × pages 1–2. */
export function standardCatalogue(): PackRequest[] {
  const out: PackRequest[] = [];
  for (const page of CRON_PAGES)
    for (const native of LANGUAGES)
      for (const target of LANGUAGES) {
        if (native === target) continue;
        for (const difficulty of DIFFICULTIES)
          for (const category of CATEGORIES)
            out.push({ native, target, difficulty, category, topic: null, page, knownTerms: [] });
      }
  return out;
}

/**
 * Picks which packs to generate this run: missing page-1 packs first, then page-2 packs whose
 * page 1 already exists (page 2 needs page 1's terms to avoid repeats). At most `max` packs.
 */
export function selectMissing(existing: Set<string>, max = CRON_MAX_PACKS): PackRequest[] {
  const picked: PackRequest[] = [];
  for (const req of standardCatalogue()) {
    if (picked.length >= max) break;
    if (existing.has(packIdFor(req))) continue;
    if (req.page > 1 && !existing.has(packIdFor({ ...req, page: req.page - 1 }))) continue;
    picked.push(req);
  }
  return picked;
}

/** All pack ids currently in KV (paginated list over the `ai-` prefix). */
export async function listPackIds(kv: KVNamespace): Promise<Set<string>> {
  const ids = new Set<string>();
  let cursor: string | undefined;
  do {
    const res = await kv.list({ prefix: "ai-", cursor });
    for (const k of res.keys) ids.add(k.name);
    cursor = res.list_complete ? undefined : res.cursor;
  } while (cursor);
  return ids;
}

export interface CronReport {
  selected: string[];
  generated: string[];
  failed: string[];
}

export async function runCron(deps: PackDeps, max = CRON_MAX_PACKS, concurrency = CRON_CONCURRENCY): Promise<CronReport> {
  const selected = selectMissing(await listPackIds(deps.kv), max);
  const report: CronReport = { selected: selected.map(packIdFor), generated: [], failed: [] };
  const queue = [...selected];
  const worker = async () => {
    for (let req = queue.shift(); req; req = queue.shift()) {
      const id = packIdFor(req);
      try {
        await generateAndStore(req, deps);
        report.generated.push(id);
      } catch (err) {
        report.failed.push(id);
        deps.log?.(`cron: ${id} failed`, String(err));
      }
    }
  };
  await Promise.all(Array.from({ length: Math.min(concurrency, queue.length) }, worker));
  deps.log?.("cron: done", { selected: report.selected.length, generated: report.generated.length, failed: report.failed.length });
  return report;
}
