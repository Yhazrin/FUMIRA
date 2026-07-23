import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { safeProxyDescriptor } from "../src/http/outboundFetch.js";

describe("outbound proxy helpers", () => {
  it("describes proxy as host:port without leaking credentials", () => {
    const safe = safeProxyDescriptor("http://user:secret@127.0.0.1:7990");
    assert.equal(safe, "http://127.0.0.1:7990");
    assert.equal(safe.includes("secret"), false);
    assert.equal(safe.includes("user"), false);
  });
});
