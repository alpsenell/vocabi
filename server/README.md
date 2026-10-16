# vocabi-packs: Vocabi Pro word pack server

A Cloudflare Worker that generates AI word packs with Claude, caches them in Workers KV, and serves them only to Vocabi Pro subscribers (StoreKit 2 signed transactions).

- `POST /v1/packs`: returns a `WordPack` JSON that decodes directly into VocabCore's `WordPack` struct.
- `GET /v1/health`: returns `{ "ok": true, "version": "1.0.0" }`.
- A daily cron pre-generates pages 1–2 of the standard catalogue (12 language pairs × 3 levels × 7 categories = 504 packs), at most 40 packs per run.

## How it works

| Piece | File |
|---|---|
| Routing, error responses, cron entry | `src/index.ts` |
| StoreKit JWS verification (x5c → Apple Root CA G3, ES256, bundle/product/expiry/environment) | `src/jws.ts`, `src/asn1.ts`, `src/appleRoot.ts` |
| Bearer token handling, dev bypass, per-isolate verdict cache | `src/auth.ts` |
| Pack id / entry id rules (mirror `WordPack.makeID`, `UserSettings.normalizeTopic`) | `src/ids.ts` |
| Request validation and generated pack validation | `src/validation.ts` |
| Prompts and JSON schemas | `src/prompt.ts` |
| Claude calls (Opus 5.5 generation, Haiku 5.5 verification) | `src/generator.ts`, `src/llm.ts` |
| KV cache, previous-page de-duplication, in-flight de-duplication | `src/packs.ts` |
| Custom-topic rate limit (10 per install per 7 days) | `src/ratelimit.ts` |
| Cron selection | `src/cron.ts` |

Generation uses `claude-opus-5-5` with structured output (`output_config.format` JSON schema), `effort: "medium"`, adaptive thinking (the model default), and server-side refusal fallbacks (`fallbacks: "default"`, beta `server-side-fallback-2026-07-01`). The stable part of the system prompt comes first, with a cache breakpoint. Each pack is validated: 35–45 entries, all four languages present, definitions of 120 characters or fewer, unique English terms. A failed pack is retried once, then the request returns 502. When `VERIFY_PACKS=true`, `claude-haiku-5-5` reviews the pack and flagged entries are dropped, but only if at least 35 entries remain.

KV layout: `<packId>` holds the pack JSON (standard packs never expire, topic packs expire after 90 days). `rl:topic:<installId>` holds the rate-limit timestamps.

## Deploy (owner steps)

Prerequisites: Node 20+, a Cloudflare account, and an Anthropic API key.

```bash
cd server
npm install

# 1. Log in to Cloudflare
npx wrangler login

# 2. Create the KV namespace, then paste the printed id into wrangler.toml ([[kv_namespaces]] id)
npx wrangler kv namespace create PACKS

# 3. Set secrets
npx wrangler secret put ANTHROPIC_API_KEY      # paste the Claude API key
npx wrangler secret put DEV_BYPASS_TOKEN       # optional: a long random string, e.g. `openssl rand -hex 32`

# 4. Check and deploy
npm test
npx tsc --noEmit
npm run deploy
```

The Worker is then served at `https://vocabi-packs.<your-subdomain>.workers.dev`. You can add a custom domain (for example `packs.vocabi.app`) under Workers → Settings → Domains & Routes.

**Use the Workers Paid plan ($5/month).** Waiting on Claude does not count as CPU time, but the free plan's CPU and subrequest limits are tight for JWS verification plus the cron, which runs 40 generations with several KV calls each. The paid plan also allows the cron's longer wall-clock time.

Variables in `wrangler.toml`:
- `VERIFY_PACKS`: `"true"` runs the Haiku verification pass; set it to `"false"` to save the extra call.
- `APPLE_BUNDLE_ID`: `com.alpsenel.wordwidget`.

Local development: put the secrets in `server/.dev.vars` (gitignored) and run `npm run dev`:

```
ANTHROPIC_API_KEY=sk-ant-...
DEV_BYPASS_TOKEN=local-dev-token
```

## curl examples

```bash
BASE=https://vocabi-packs.<your-subdomain>.workers.dev
DEV=<your DEV_BYPASS_TOKEN>

curl -s $BASE/v1/health
# {"ok":true,"version":"1.0.0"}

curl -s -X POST $BASE/v1/packs \
  -H "Authorization: Bearer dev:$DEV" \
  -H "X-Vocabi-Install: $(uuidgen)" \
  -H "Content-Type: application/json" \
  --max-time 120 \
  -d '{"native":"tr","target":"en","difficulty":"beginner","category":"travel","topic":"Sailing","page":1}'
```

Response (shortened):

```json
{
  "id": "ai-tr-en-beginner-t_sailing-1",
  "nativeLanguage": "tr",
  "targetLanguage": "en",
  "difficulty": "beginner",
  "category": "travel",
  "topic": "sailing",
  "entries": [
    {
      "id": "ai-tr-en-beginner-t_sailing-1-01",
      "category": "travel",
      "difficulty": "beginner",
      "terms": { "en": "sail", "tr": "yelken", "fr": "voile", "es": "vela" },
      "definitions": { "en": "...", "tr": "...", "fr": "...", "es": "..." },
      "examples": { "en": "...", "tr": "...", "fr": "...", "es": "..." },
      "topic": "sailing"
    }
  ],
  "createdAt": "2026-10-16T10:00:00Z",
  "version": 1
}
```

The `X-Vocabi-Cache: hit|miss` response header shows whether the pack came from KV.

Errors always look like `{"error":"<code>","message":"..."}`:

| Status | `error` | When |
|---|---|---|
| 400 | `invalid_request` | Bad JSON or body field, or a missing or non-UUID `X-Vocabi-Install` |
| 401 | `unauthorized` | Missing or invalid token, or the subscription expired more than 1 day ago |
| 429 | `rate_limited` | More than 10 new custom-topic packs in 7 days for this install. The `Retry-After` header gives the wait in seconds |
| 502 | `generation_failed` | Claude failed twice, the pack failed validation twice, or no API key is set |

## Rotating the dev token

```bash
npx wrangler secret put DEV_BYPASS_TOKEN   # enter the new value; takes effect immediately
# or disable the bypass entirely:
npx wrangler secret delete DEV_BYPASS_TOKEN
```

Then update the token in the simulator / StoreKit-test build configuration. Never ship the dev token in a release build: anyone who extracts it gets free packs until you rotate it.

## Pre-generating the catalogue

The cron runs daily at 03:17 UTC and generates up to 40 missing standard packs, 6 at a time. It does page 1 packs first. A page 2 pack is generated only after its page 1 exists, so that page 2 can avoid repeating page 1's words. Filling all 504 packs takes about 13 daily runs. To speed this up, temporarily change `crons` in `wrangler.toml` to something like `["*/20 * * * *"]`, redeploy, and switch it back once the catalogue is full.

## Costs

See `docs/PRICING.md` for the full model. The short version:
- One 40-word Opus 5.5 pack costs about $0.13. The Haiku verification pass adds about $0.004.
- The full standard catalogue (504 packs) costs about $65 one-time. Every subscriber shares it through KV.
- Custom topics are the only per-user cost: at most 10 generations per install per week, so at most about $1.30 per install per week.
- Cache hits cost only KV reads (fractions of a cent per thousand).
- Cloudflare Workers Paid costs $5/month flat.

## Tests

```bash
npm test          # vitest: ids, validation, generator (mocked Claude), cache/rate limit (in-memory KV), JWS, auth, cron, HTTP
npx tsc --noEmit  # type check
```

The JWS tests build a throwaway P-384 root → intermediate → P-256 leaf chain with `node:crypto`, including Apple's marker extensions, and inject that root as the trusted root. No test calls the real Claude API.
