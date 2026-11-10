"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { QUOTE_URL, TOKENS, buildRequest, validateQuote, probeQuote } = require("./probe-quotes.cjs");

const OWNER = "0x888D768764A2E304215247F0bA3457cCb0f0ab4f";
const NOW = Date.parse("2026-11-10T10:44:00Z");
const options = { symbol: "WETH", grossSell: "1000000000000000000", owner: OWNER, receiver: OWNER };
function fixture(request = buildRequest(options)) {
  return {
    quote: {
      sellToken: request.sellToken.toLowerCase(),
      buyToken: request.buyToken.toLowerCase(),
      receiver: OWNER.toLowerCase(),
      sellAmount: "999000000000000000",
      feeAmount: "1000000000000000",
      buyAmount: "2000000000000000000000",
      validTo: NOW / 1000 + 300,
      appData: request.appData,
      kind: "sell",
      partiallyFillable: false,
      sellTokenBalance: "erc20",
      buyTokenBalance: "erc20",
      signingScheme: "eip1271",
    },
    from: OWNER.toLowerCase(),
    expiration: new Date(NOW + 600_000).toISOString(),
    id: 1234,
    verified: true,
    protocolFeeBps: "2",
  };
}

test("builds a verified, exact-budget ERC1271 quote, not an order", () => {
  const request = buildRequest(options);
  assert.equal(QUOTE_URL, "https://api.cow.fi/mainnet/api/v1/quote");
  assert.equal(request.priceQuality, "verified");
  assert.equal(request.signingScheme, "eip1271");
  assert.equal(request.onchainOrder, false);
  assert.equal(request.verificationGasLimit, 200_000);
  assert.equal(request.partiallyFillable, false);
  assert.equal(request.buyToken, TOKENS.BOLD);
  assert.equal(request.sellAmountBeforeFee, options.grossSell);
  assert.equal(request.validFor, 300);
  assert.equal(Object.hasOwn(request, "signature"), false);
});

test("supports rETH and presign research without an ERC1271 gas field", () => {
  const request = buildRequest({ ...options, symbol: "rETH", signingScheme: "presign" });
  assert.equal(request.sellToken, TOKENS.rETH);
  assert.equal(request.signingScheme, "presign");
  assert.equal(Object.hasOwn(request, "verificationGasLimit"), false);
});

test("rejects unsupported identities, budgets and signing schemes", () => {
  for (const invalid of [
    { symbol: "USDC" },
    { symbol: "BOLD" },
    { grossSell: "0" },
    { grossSell: "-1" },
    { grossSell: "1.2" },
    { grossSell: "1e18" },
    { grossSell: 1 },
    { grossSell: "01" },
    { owner: "bad" },
    { receiver: "0x0000000000000000000000000000000000000000" },
    { signingScheme: "eip712" },
  ])
    assert.throws(() => buildRequest({ ...options, ...invalid }));
});

test("validates net sell plus network fee against the exact gross budget", () => {
  const request = buildRequest(options);
  const response = fixture(request);
  const result = validateQuote(response, request, NOW);
  assert.equal(result.grossSell, options.grossSell);
  assert.equal(result.buyAmount, response.quote.buyAmount);
  assert.equal(result.protocolFeeBps, "2");
  assert.equal(result.verified, true);
});

test("rejects a wrong pair, owner, receiver or appData", () => {
  const request = buildRequest(options);
  for (const [field, value] of [
    ["sellToken", TOKENS.rETH],
    ["buyToken", TOKENS.WETH],
    ["receiver", "0x1111111111111111111111111111111111111111"],
    ["appData", "0x" + "11".repeat(32)],
  ]) {
    const response = fixture(request);
    response.quote[field] = value;
    assert.throws(() => validateQuote(response, request, NOW));
  }
  const response = fixture(request);
  response.from = "0x1111111111111111111111111111111111111111";
  assert.throws(() => validateQuote(response, request, NOW));
});

test("rejects unverified, absent, wrong-budget or nonpositive quotes", () => {
  const request = buildRequest(options);
  assert.throws(() => validateQuote(null, request, NOW));
  assert.throws(() => validateQuote({}, request, NOW));
  assert.throws(() => validateQuote({ ...fixture(request), verified: false }, request, NOW));
  for (const [field, value] of [
    ["sellAmount", "0"],
    ["feeAmount", "-1"],
    ["buyAmount", "0"],
    ["sellAmount", "999999999999999999"],
    ["buyAmount", "1e18"],
  ]) {
    const response = fixture(request);
    response.quote[field] = value;
    assert.throws(() => validateQuote(response, request, NOW));
  }
});

test("rejects changed trade semantics and internal token balances", () => {
  const request = buildRequest(options);
  for (const [field, value] of [
    ["kind", "buy"],
    ["partiallyFillable", true],
    ["sellTokenBalance", "internal"],
    ["buyTokenBalance", "internal"],
    ["signingScheme", "presign"],
  ]) {
    const response = fixture(request);
    response.quote[field] = value;
    assert.throws(() => validateQuote(response, request, NOW));
  }
});

test("rejects expired or excessively long validity and unusable fees/IDs", () => {
  const request = buildRequest(options);
  for (const invalid of [
    { expiration: "bad" },
    { expiration: new Date(NOW).toISOString() },
    { id: null },
    { id: -1 },
    { protocolFeeBps: "10001" },
    { protocolFeeBps: "NaN" },
  ])
    assert.throws(() => validateQuote({ ...fixture(request), ...invalid }, request, NOW));
  for (const validTo of [NOW / 1000, NOW / 1000 + 331, "1794307740", 1.5]) {
    const response = fixture(request);
    response.quote.validTo = validTo;
    assert.throws(() => validateQuote(response, request, NOW));
  }
  const response = fixture(request);
  delete response.protocolFeeBps;
  assert.equal(validateQuote(response, request, NOW).protocolFeeBps, null);
});

test("only POSTs to the fixed quote endpoint and preserves public evidence", async () => {
  const request = buildRequest(options);
  let calls = 0;
  const result = await probeQuote(
    options,
    async (url, init) => {
      calls++;
      assert.equal(url, QUOTE_URL);
      assert.equal(init.method, "POST");
      assert.equal(init.redirect, "error");
      assert.deepEqual(JSON.parse(init.body), request);
      return { ok: true, json: async () => fixture(request) };
    },
    () => NOW,
  );
  assert.equal(calls, 1);
  assert.deepEqual(result.request, request);
  assert.equal(result.response.id, 1234);
  assert.equal(result.observedUtc, new Date(NOW).toISOString());
});

test("HTTP errors and malformed/unverified responses cannot count as viable", async () => {
  await assert.rejects(
    () =>
      probeQuote(
        options,
        async () => ({ ok: false, status: 429 }),
        () => NOW,
      ),
    /HTTP 429/,
  );
  await assert.rejects(() =>
    probeQuote(
      options,
      async () => ({ ok: true, json: async () => ({}) }),
      () => NOW,
    ),
  );
});
