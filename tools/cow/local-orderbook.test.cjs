"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { quote, orderUid } = require("./local-orderbook.cjs");
const { TypedDataEncoder, id, concat, toBeHex } = require("ethers");

test("synthetic local quotes preserve exact gross budget and request semantics", () => {
  const request = {
    sellAmountBeforeFee: "1000000000000000000",
    from: "0x" + "11".repeat(20),
    receiver: "0x" + "11".repeat(20),
    sellToken: "0x" + "22".repeat(20),
    buyToken: "0x" + "33".repeat(20),
    validTo: 2000000000,
    appData: "0x" + "00".repeat(32),
    kind: "sell",
    signingScheme: "presign",
    partiallyFillable: false,
    sellTokenBalance: "erc20",
    buyTokenBalance: "erc20",
    priceQuality: "verified",
  };
  const result = quote(request, 1);
  assert.equal(result.verified, true); // Explicitly synthetic; never an external CoW verification result.
  assert.equal(BigInt(result.quote.sellAmount) + BigInt(result.quote.feeAmount), 10n ** 18n);
  assert.equal(result.quote.receiver, request.receiver);
  assert.ok(BigInt(result.quote.buyAmount) > 0n);
});

test("stub UIDs use canonical CoW EIP712 bytes rather than arbitrary IDs", () => {
  const order = {
    sellToken: "0x" + "11".repeat(20),
    buyToken: "0x" + "22".repeat(20),
    receiver: "0x" + "33".repeat(20),
    from: "0x" + "33".repeat(20),
    sellAmount: "100",
    buyAmount: "200",
    validTo: 2000000000,
    appData: "0x" + "00".repeat(32),
    feeAmount: "0",
    kind: "sell",
    partiallyFillable: false,
    sellTokenBalance: "erc20",
    buyTokenBalance: "erc20",
  };
  const result = orderUid(order);
  assert.equal(result.length, 114);
  assert.notEqual(result, orderUid({ ...order, buyAmount: "201" }));
  assert.equal(result.slice(-8), toBeHex(order.validTo, 4).slice(2));
  assert.equal(result.slice(66, 106).toLowerCase(), order.from.slice(2));
});
