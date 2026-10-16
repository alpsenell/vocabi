import { describe, expect, it } from "vitest";
import { Authenticator } from "../src/auth";
import { makeChain, signTransaction, transactionPayload } from "./helpers/certs";

describe("Authenticator", () => {
  it("accepts the dev bypass token only when the secret is configured", async () => {
    const on = new Authenticator({ devBypassToken: "s3cret" });
    expect((await on.authenticate("Bearer dev:s3cret")).ok).toBe(true);
    expect(await on.authenticate("Bearer dev:wrong")).toEqual({ ok: false, reason: "invalid dev token" });
    const off = new Authenticator({});
    expect(await off.authenticate("Bearer dev:s3cret")).toEqual({ ok: false, reason: "dev bypass disabled" });
    expect(await off.authenticate("Bearer dev:")).toEqual({ ok: false, reason: "dev bypass disabled" });
  });

  it("requires a bearer token", async () => {
    const a = new Authenticator({});
    expect((await a.authenticate(null)).ok).toBe(false);
    expect((await a.authenticate("Basic abc")).ok).toBe(false);
  });

  it("verifies StoreKit tokens, caches verdicts per token and honours expiry on cache hits", async () => {
    const chain = makeChain();
    let now = Date.now();
    const a = new Authenticator({ trustedRoots: [chain.root], now: () => now });
    const token = signTransaction(chain, transactionPayload({ expiresDate: now + 60_000 }, now));
    expect(await a.authenticate(`Bearer ${token}`)).toMatchObject({ ok: true, kind: "storekit" });
    expect(a.cacheSize).toBe(1);
    expect((await a.authenticate(`Bearer ${token}`)).ok).toBe(true);
    expect(a.cacheSize).toBe(1);
    now += 60_000 + 24 * 3600 * 1000 + 1; // past expiry + grace
    expect(await a.authenticate(`Bearer ${token}`)).toEqual({ ok: false, reason: "subscription expired" });
  });

  it("uses the configured bundle id", async () => {
    const chain = makeChain();
    const a = new Authenticator({ trustedRoots: [chain.root], bundleId: "com.example.other" });
    const token = signTransaction(chain, transactionPayload());
    expect(await a.authenticate(`Bearer ${token}`)).toEqual({ ok: false, reason: "wrong bundle id" });
  });
});
