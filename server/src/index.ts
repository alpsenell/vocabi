import { Authenticator, type AuthConfig } from "./auth";
import { runCron } from "./cron";
import { GenerationError } from "./generator";
import { anthropicCreator, type MessageCreator } from "./llm";
import { RateLimitedError, getOrCreatePack, type PackDeps } from "./packs";
import { SERVER_VERSION, type Env } from "./types";
import { parsePackRequest } from "./validation";

const INSTALL_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_BODY_BYTES = 64 * 1024;

const log = (msg: string, data?: unknown) => console.log(JSON.stringify({ msg, data }));

function json(status: number, body: unknown, headers: Record<string, string> = {}): Response {
  return new Response(typeof body === "string" ? body : JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...headers },
  });
}

const error = (status: number, code: string, message: string, headers?: Record<string, string>) =>
  json(status, { error: code, message }, headers);

export interface AppOptions {
  /** Override the Claude client (tests). Default: official SDK with ANTHROPIC_API_KEY. */
  createMessage?: (env: Env) => MessageCreator | null;
  /** Override trusted roots / clock for StoreKit verification (tests). */
  auth?: Omit<AuthConfig, "bundleId" | "devBypassToken">;
  now?: () => Date;
}

export function createApp(options: AppOptions = {}) {
  let authenticator: Authenticator | undefined;
  let authKey = "";
  const getAuthenticator = (env: Env) => {
    // One authenticator (and verdict cache) per isolate; rebuilt only if config changes.
    const key = `${env.APPLE_BUNDLE_ID ?? ""}|${env.DEV_BYPASS_TOKEN ?? ""}`;
    if (!authenticator || key !== authKey) {
      authenticator = new Authenticator({
        ...options.auth,
        bundleId: env.APPLE_BUNDLE_ID || undefined,
        devBypassToken: env.DEV_BYPASS_TOKEN || undefined,
      });
      authKey = key;
    }
    return authenticator;
  };

  const deps = (env: Env): PackDeps => ({
    kv: env.PACKS,
    create: options.createMessage
      ? options.createMessage(env)
      : env.ANTHROPIC_API_KEY
        ? anthropicCreator(env.ANTHROPIC_API_KEY)
        : null,
    verify: env.VERIFY_PACKS === "true",
    now: options.now,
    log,
  });

  async function handlePacks(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const auth = await getAuthenticator(env).authenticate(request.headers.get("authorization"));
    if (!auth.ok) return error(401, "unauthorized", `Vocabi Pro subscription required (${auth.reason}).`);

    const installId = request.headers.get("x-vocabi-install")?.trim() ?? "";
    if (!INSTALL_ID.test(installId)) return error(400, "invalid_request", "X-Vocabi-Install must be a UUID.");

    const text = await request.text();
    if (text.length > MAX_BODY_BYTES) return error(400, "invalid_request", "Body too large.");
    let body: unknown;
    try {
      body = JSON.parse(text);
    } catch {
      return error(400, "invalid_request", "Body must be valid JSON.");
    }
    const parsed = parsePackRequest(body);
    if (!parsed.ok) return error(400, "invalid_request", parsed.message);

    const work = getOrCreatePack(parsed.value, installId, deps(env));
    // Let generation finish and land in KV even if the client disconnects; a retry then hits the cache.
    ctx.waitUntil(work.catch(() => undefined));
    try {
      const result = await work;
      return json(200, result.body, { "x-vocabi-cache": result.source === "cache" ? "hit" : "miss" });
    } catch (err) {
      if (err instanceof RateLimitedError) {
        return error(429, "rate_limited", "Custom topic limit reached (10 new topic packs per 7 days).", {
          "retry-after": String(err.retryAfterSeconds),
        });
      }
      log("pack generation failed", err instanceof GenerationError ? { message: err.message, problems: err.problems.slice(0, 10) } : String(err));
      return error(502, "generation_failed", "Could not generate this pack right now. Please try again later.");
    }
  }

  return {
    async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
      const { pathname } = new URL(request.url);
      if (pathname === "/v1/health") {
        if (request.method !== "GET") return error(405, "method_not_allowed", "Use GET.");
        return json(200, { ok: true, version: SERVER_VERSION });
      }
      if (pathname === "/v1/packs") {
        if (request.method !== "POST") return error(405, "method_not_allowed", "Use POST.");
        try {
          return await handlePacks(request, env, ctx);
        } catch (err) {
          log("unhandled error", String(err));
          return error(502, "generation_failed", "Unexpected server error.");
        }
      }
      return error(404, "not_found", "Unknown endpoint.");
    },

    async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
      ctx.waitUntil(runCron(deps(env)).then(() => undefined));
    },
  };
}

export default createApp();
