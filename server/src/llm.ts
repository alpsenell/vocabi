import Anthropic from "@anthropic-ai/sdk";

export const GENERATION_MODEL = "claude-opus-5-5";
export const VERIFY_MODEL = "claude-haiku-5-5";
export const FALLBACK_BETA = "server-side-fallback-2026-07-01";

export type StreamParams = Parameters<Anthropic["beta"]["messages"]["stream"]>[0];

/** The parts of a Claude response the server reads. */
export interface LlmResult {
  stop_reason: string | null;
  content: Array<{ type: string; text?: string }>;
  model?: string;
}

/** Sends one request and resolves with the final message. Injected so tests never hit the API. */
export type MessageCreator = (params: StreamParams) => Promise<LlmResult>;

/** Production implementation: official SDK, streamed, collected with `.finalMessage()`. */
export function anthropicCreator(apiKey: string): MessageCreator {
  const client = new Anthropic({ apiKey, timeout: 170_000, maxRetries: 1 });
  return async (params) => {
    const stream = client.beta.messages.stream(params);
    const message = await stream.finalMessage();
    return message as unknown as LlmResult;
  };
}

/** Joins the text blocks of a response. */
export function responseText(result: LlmResult): string {
  return result.content
    .filter((b) => b.type === "text" && typeof b.text === "string")
    .map((b) => b.text as string)
    .join("");
}
