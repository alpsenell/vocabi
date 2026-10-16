import { X509Certificate, generateKeyPairSync } from "node:crypto";
import { beforeAll, describe, expect, it } from "vitest";
import { pemToDer } from "../src/asn1";
import { APPLE_ROOT_CA_G3_PEM } from "../src/appleRoot";
import { verifyStoreKitTransaction, type VerifyOptions } from "../src/jws";
import { makeChain, signTransaction, transactionPayload, type TestChain } from "./helpers/certs";

let chain: TestChain;
let opts: VerifyOptions;
const now = Date.now();

beforeAll(() => {
  chain = makeChain();
  opts = { trustedRoots: [chain.root], bundleId: "com.alpsenel.wordwidget", now: new Date(now) };
});

describe("test chain", () => {
  it("is well-formed X.509 that node can parse and verify", () => {
    const root = new X509Certificate(chain.root);
    const int = new X509Certificate(chain.intermediate);
    const leaf = new X509Certificate(chain.leaf);
    expect(int.verify(root.publicKey)).toBe(true);
    expect(leaf.verify(int.publicKey)).toBe(true);
    expect(int.ca).toBe(true);
  });
});

describe("verifyStoreKitTransaction", () => {
  it("accepts a valid Sandbox monthly transaction", async () => {
    const r = await verifyStoreKitTransaction(signTransaction(chain, transactionPayload({}, now)), opts);
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.payload.productId).toBe("com.alpsenel.wordwidget.pro.monthly");
  });

  it("accepts weekly Production transactions and chains without the root certificate", async () => {
    const jws = signTransaction(
      chain,
      transactionPayload({ productId: "com.alpsenel.wordwidget.pro.weekly", environment: "Production" }, now),
      { includeRoot: false },
    );
    expect((await verifyStoreKitTransaction(jws, opts)).ok).toBe(true);
  });

  it("allows one day of grace after expiresDate", async () => {
    const inGrace = signTransaction(chain, transactionPayload({ expiresDate: now - 23 * 3600 * 1000 }, now));
    expect((await verifyStoreKitTransaction(inGrace, opts)).ok).toBe(true);
  });

  it.each([
    ["expired subscription", { expiresDate: now - 25 * 3600 * 1000 }, "subscription expired"],
    ["wrong bundle", { bundleId: "com.example.other" }, "wrong bundle id"],
    ["wrong product", { productId: "com.alpsenel.wordwidget.coins" }, "wrong product"],
    ["Xcode environment", { environment: "Xcode" }, "wrong environment"],
    ["revoked", { revocationDate: now - 1000 }, "transaction revoked"],
    ["no expiry", { expiresDate: undefined }, "missing expiresDate"],
  ])("rejects %s", async (_label, overrides, reason) => {
    const r = await verifyStoreKitTransaction(signTransaction(chain, transactionPayload(overrides, now)), opts);
    expect(r).toEqual({ ok: false, reason });
  });

  it("rejects a bad signature", async () => {
    const otherKey = generateKeyPairSync("ec", { namedCurve: "P-256" }).privateKey;
    const forged = signTransaction(chain, transactionPayload({}, now), { signingKey: otherKey });
    expect(await verifyStoreKitTransaction(forged, opts)).toEqual({ ok: false, reason: "bad signature" });
  });

  it("rejects a tampered payload", async () => {
    const [h, , s] = signTransaction(chain, transactionPayload({}, now)).split(".");
    const p = Buffer.from(JSON.stringify(transactionPayload({ expiresDate: now + 10 ** 12 }, now))).toString("base64url");
    expect(await verifyStoreKitTransaction(`${h}.${p}.${s}`, opts)).toEqual({ ok: false, reason: "bad signature" });
  });

  it("rejects chains that do not lead to a trusted root", async () => {
    const jws = signTransaction(chain, transactionPayload({}, now));
    const apple = { ...opts, trustedRoots: [pemToDer(APPLE_ROOT_CA_G3_PEM)] };
    expect(await verifyStoreKitTransaction(jws, apple)).toEqual({ ok: false, reason: "chain does not lead to a trusted root" });
    const other = makeChain();
    const mixed = { ...opts, trustedRoots: [other.root] };
    expect((await verifyStoreKitTransaction(signTransaction(chain, transactionPayload({}, now), { includeRoot: false }), mixed)).ok).toBe(false);
  });

  it("rejects an expired leaf certificate and a leaf without Apple's marker", async () => {
    const expiredLeaf = makeChain({ leafNotAfter: new Date(now - 1000) });
    const r1 = await verifyStoreKitTransaction(signTransaction(expiredLeaf, transactionPayload({}, now)), {
      ...opts,
      trustedRoots: [expiredLeaf.root],
    });
    expect(r1).toEqual({ ok: false, reason: "certificate expired or not yet valid" });
    const noMarker = makeChain({ leafMarker: false });
    const r2 = await verifyStoreKitTransaction(signTransaction(noMarker, transactionPayload({}, now)), {
      ...opts,
      trustedRoots: [noMarker.root],
    });
    expect(r2.ok).toBe(false);
  });

  it("rejects malformed tokens", async () => {
    for (const t of ["", "a.b", "a.b.c", "eyJhbGciOiJIUzI1NiJ9.e30.sig"]) {
      expect((await verifyStoreKitTransaction(t, opts)).ok).toBe(false);
    }
  });

  it("parses the embedded Apple Root CA G3", () => {
    const cert = new X509Certificate(pemToDer(APPLE_ROOT_CA_G3_PEM));
    expect(cert.subject).toContain("Apple Root CA - G3");
    expect(cert.fingerprint256).toBe(
      "63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79",
    );
  });
});
