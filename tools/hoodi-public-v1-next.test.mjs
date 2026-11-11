import test from "node:test";
import assert from "node:assert/strict";
import { ethers } from "ethers";
import { encodeOwnerSafeExecution, requireBatchIndex } from "./hoodi-public-v1-next.mjs";
import { SAFE_MULTISEND } from "./hoodi-public-safe-plan.mjs";

const OWNER = "0x00008A88A21a1d34CDDAA7fC15A0E84ed7e42D8f";

test("owner Safe execution is zero-value MultiSend with one prevalidated signature", () => {
  const batchData = "0x8d80ff0a";
  const data = encodeOwnerSafeExecution(batchData, OWNER);
  const iface = new ethers.Interface([
    "function execTransaction(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,bytes signatures) returns(bool)",
  ]);
  const d = iface.decodeFunctionData("execTransaction", data);
  assert.equal(d.to, SAFE_MULTISEND);
  assert.equal(d.value, 0n);
  assert.equal(d.data, batchData);
  assert.equal(d.operation, 1n);
  assert.equal(d.safeTxGas, 0n);
  assert.equal(d.baseGas, 0n);
  assert.equal(d.gasPrice, 0n);
  assert.equal(d.gasToken, ethers.ZeroAddress);
  assert.equal(d.refundReceiver, ethers.ZeroAddress);
  assert.equal(ethers.dataLength(d.signatures), 65);
  assert.equal(d.signatures.slice(-2), "01");
  assert.equal(ethers.getAddress(`0x${d.signatures.slice(26, 66)}`), OWNER);
});

test("batch index must be explicitly selected in range", () => {
  assert.equal(requireBatchIndex("0"), 0);
  assert.equal(requireBatchIndex("4"), 4);
  for (const invalid of ["-1", "5", "1.5", "foo", "01"]) {
    assert.throws(() => requireBatchIndex(invalid), /batch index/);
  }
});
