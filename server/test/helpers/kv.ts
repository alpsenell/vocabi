/** In-memory stand-in for a Workers KV namespace (the subset the server uses). */
export class MemoryKV {
  store = new Map<string, { value: string; expirationTtl?: number }>();
  puts: Array<{ key: string; expirationTtl?: number }> = [];

  async get(key: string, type?: "text" | "json" | { type: "text" | "json" }): Promise<any> {
    const entry = this.store.get(key);
    if (!entry) return null;
    const t = typeof type === "object" ? type.type : type;
    return t === "json" ? JSON.parse(entry.value) : entry.value;
  }

  async put(key: string, value: string, opts?: { expirationTtl?: number }): Promise<void> {
    this.store.set(key, { value, expirationTtl: opts?.expirationTtl });
    this.puts.push({ key, expirationTtl: opts?.expirationTtl });
  }

  async delete(key: string): Promise<void> {
    this.store.delete(key);
  }

  async list(opts: { prefix?: string; cursor?: string; limit?: number } = {}) {
    const limit = opts.limit ?? 1000;
    const names = [...this.store.keys()].filter((k) => k.startsWith(opts.prefix ?? "")).sort();
    const start = opts.cursor ? Number(opts.cursor) : 0;
    const page = names.slice(start, start + limit);
    const done = start + limit >= names.length;
    return { keys: page.map((name) => ({ name })), list_complete: done, cursor: done ? "" : String(start + limit) };
  }

  asKV(): KVNamespace {
    return this as unknown as KVNamespace;
  }
}
