"use strict";

// Read-only research utility. Its only remote operation is POST /quote.
// Never imports a signer, creates/submits an order, approves, or sends a transaction.
const QUOTE_URL = "https://api.cow.fi/mainnet/api/v1/quote";
const TOKENS = Object.freeze({
  WETH: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
  rETH: "0xae78736Cd615f374D3085123A210448E74Fc6393",
  BOLD: "0x6440f144b7e50D6a8439336510312d2F54beB01D",
});
const APP_DATA = "0x" + "00".repeat(32);
const UINT256_MAX = (1n << 256n) - 1n;

function address(value) {
  if (typeof value !== "string" || !/^0x[0-9a-fA-F]{40}$/.test(value) || /^0x0{40}$/i.test(value))
    throw new Error("Invalid public address");
  return value.toLowerCase();
}
function atoms(value, allowZero = false) {
  if (typeof value !== "string" || !/^(0|[1-9][0-9]*)$/.test(value)) throw new Error("Invalid integer token amount");
  const amount = BigInt(value);
  if ((!allowZero && amount === 0n) || amount > UINT256_MAX) throw new Error("Amount outside uint256 bounds");
  return amount;
}

/** Build a quote request only; the gas limit is a research estimate, not approved configuration. */
function buildRequest({ symbol, grossSell, owner, receiver, signingScheme = "eip1271" }) {
  if (symbol !== "WETH" && symbol !== "rETH") throw new Error("Unsupported research pair");
  atoms(grossSell);
  address(owner);
  address(receiver);
  if (signingScheme !== "presign" && signingScheme !== "eip1271") throw new Error("Unsupported signing scheme");
  return {
    sellToken: TOKENS[symbol],
    buyToken: TOKENS.BOLD,
    from: owner,
    receiver,
    sellAmountBeforeFee: grossSell,
    kind: "sell",
    partiallyFillable: false,
    sellTokenBalance: "erc20",
    buyTokenBalance: "erc20",
    appData: APP_DATA,
    signingScheme,
    onchainOrder: false,
    ...(signingScheme === "eip1271" ? { verificationGasLimit: 200_000 } : {}),
    priceQuality: "verified",
    validFor: 300,
  };
}

/** Reject an untrusted/mismatched response rather than silently treating it as evidence of viability. */
function validateQuote(response, request, nowMs = Date.now()) {
  if (!response || !response.quote || response.verified !== true) throw new Error("Missing or unverified quote");
  const quote = response.quote;
  for (const [actual, expected] of [
    [quote.sellToken, request.sellToken],
    [quote.buyToken, request.buyToken],
    [quote.receiver, request.receiver],
    [response.from, request.from],
  ])
    if (address(actual) !== address(expected)) throw new Error("Quote identity mismatch");
  if (quote.appData !== request.appData) throw new Error("Quote appData mismatch");
  for (const field of ["kind", "partiallyFillable", "sellTokenBalance", "buyTokenBalance", "signingScheme"])
    if (quote[field] !== request[field]) throw new Error("Quote trade semantics mismatch");
  const sell = atoms(quote.sellAmount);
  const fee = atoms(quote.feeAmount, true);
  atoms(quote.buyAmount);
  if (sell + fee !== atoms(request.sellAmountBeforeFee)) throw new Error("Quote changes gross sell budget");
  const expiration = Date.parse(response.expiration);
  if (!Number.isFinite(expiration) || expiration <= nowMs) throw new Error("Quote expired");
  if (
    !Number.isInteger(quote.validTo) ||
    quote.validTo <= nowMs / 1000 ||
    quote.validTo > nowMs / 1000 + request.validFor + 30
  )
    throw new Error("Invalid quote validity");
  if (!Number.isSafeInteger(response.id) || response.id <= 0) throw new Error("Missing quote ID");
  const protocolFeeBps = response.protocolFeeBps ?? null;
  if (
    protocolFeeBps !== null &&
    (typeof protocolFeeBps !== "string" ||
      !/^[0-9]+(?:\.[0-9]+)?$/.test(protocolFeeBps) ||
      Number(protocolFeeBps) > 10_000)
  )
    throw new Error("Invalid protocol fee");
  return {
    grossSell: request.sellAmountBeforeFee,
    netSell: quote.sellAmount,
    networkFee: quote.feeAmount,
    buyAmount: quote.buyAmount,
    protocolFeeBps,
    validTo: quote.validTo,
    quoteExpiration: response.expiration,
    quoteId: response.id,
    verified: true,
  };
}

async function probeQuote(options, fetchImpl = globalThis.fetch, clock = Date.now) {
  const request = buildRequest(options);
  const response = await fetchImpl(QUOTE_URL, {
    method: "POST",
    redirect: "error",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(request),
    signal: AbortSignal.timeout(20_000),
  });
  if (!response.ok) throw new Error("CoW quote HTTP " + response.status);
  const body = await response.json();
  const nowMs = clock();
  return {
    observedUtc: new Date(nowMs).toISOString(),
    request,
    response: body,
    validation: validateQuote(body, request, nowMs),
  };
}

async function main() {
  const owner = process.env.COW_RESEARCH_OWNER || "0x888D768764A2E304215247F0bA3457cCb0f0ab4f";
  const receiver = process.env.COW_RESEARCH_RECEIVER || owner;
  const signingScheme = process.env.COW_RESEARCH_SIGNING_SCHEME || "eip1271";
  const cases = ["WETH", "rETH"].flatMap((symbol) =>
    ["10000000000000000", "1000000000000000000", "100000000000000000000"].map((grossSell) => ({
      symbol,
      grossSell,
      owner,
      receiver,
      signingScheme,
    })),
  );
  const results = await Promise.all(
    cases.map(async (options) => {
      try {
        return { input: options, ...(await probeQuote(options)) };
      } catch (error) {
        return { input: options, error: error.message };
      }
    }),
  );
  console.log(
    JSON.stringify(
      {
        endpoint: QUOTE_URL,
        operation: "quote only; no signature/order submission/transaction",
        caveat:
          "verified:true is provider simulation evidence, not actual escrow ERC1271 acceptance, live order fill, or a durable execution quote",
        results,
      },
      null,
      2,
    ),
  );
  if (results.some((result) => result.error)) process.exitCode = 1;
}

module.exports = { QUOTE_URL, TOKENS, buildRequest, validateQuote, probeQuote };
if (require.main === module)
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
