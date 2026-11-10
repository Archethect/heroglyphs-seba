"use strict";
// SYNTHETIC test quote/orderbook. It binds only loopback :38546; never forwards a request to CoW.
const http = require("node:http");
const { TypedDataEncoder, id, concat, toBeHex } = require("ethers");
const SETTLEMENT = "0x9008D19f58AAbD9eD0D60971565AA8510560ab41";
const TYPES = {
  Order: [
    ...["sellToken", "buyToken", "receiver"].map((name) => ({ name, type: "address" })),
    { name: "sellAmount", type: "uint256" },
    { name: "buyAmount", type: "uint256" },
    { name: "validTo", type: "uint32" },
    { name: "appData", type: "bytes32" },
    { name: "feeAmount", type: "uint256" },
    { name: "kind", type: "string" },
    { name: "partiallyFillable", type: "bool" },
    { name: "sellTokenBalance", type: "string" },
    { name: "buyTokenBalance", type: "string" },
  ],
};
function orderUid(order) {
  const digest = TypedDataEncoder.hash(
    { name: "Gnosis Protocol", version: "v2", chainId: 1, verifyingContract: SETTLEMENT },
    TYPES,
    order,
  );
  return concat([digest, order.from, toBeHex(order.validTo, 4)]);
}
function quote(request, index) {
  const gross = BigInt(request.sellAmountBeforeFee);
  const fee = gross / 10000n;
  const { sellAmountBeforeFee, from, priceQuality, ...semantics } = request;
  return {
    from,
    id: index,
    verified: true,
    protocolFeeBps: "0",
    expiration: new Date(Date.now() + 60000).toISOString(),
    quote: {
      ...semantics,
      sellAmount: String(gross - fee),
      feeAmount: String(fee),
      buyAmount: String((gross - fee) * 2100n),
    },
  };
}
function start() {
  const orders = new Map();
  let sequence = 1;
  const server = http.createServer(async (req, res) => {
    res.setHeader("Content-Type", "application/json");
    try {
      let raw = "";
      for await (const chunk of req) {
        raw += chunk;
        if (raw.length > 16384) throw new Error("Too large");
      }
      const data = raw ? JSON.parse(raw) : null;
      if (req.url === "/api/v1/quote" && req.method === "POST") return res.end(JSON.stringify(quote(data, sequence++)));
      if (req.url === "/api/v1/orders" && req.method === "POST") {
        const uid = orderUid(data);
        if (orders.has(uid)) {
          res.statusCode = 400;
          return res.end(JSON.stringify({ errorType: "DuplicatedOrder" }));
        }
        orders.set(uid, { ...data, uid, owner: data.from });
        return res.end(JSON.stringify(uid));
      }
      const uid = req.url?.replace("/api/v1/orders/", "");
      if (req.method === "GET" && orders.has(uid)) return res.end(JSON.stringify(orders.get(uid)));
      res.statusCode = 404;
      res.end("{}");
    } catch {
      res.statusCode = 400;
      res.end("{}");
    }
  });
  server.listen(38546, "127.0.0.1", () => console.log("Synthetic local CoW stub on 127.0.0.1:38546; no live orders"));
  return server;
}
module.exports = { quote, orderUid, start };
if (require.main === module) start();
