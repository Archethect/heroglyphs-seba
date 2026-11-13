import test from "node:test";
import assert from "node:assert/strict";
import { ethers } from "ethers";
import { CREATE_CALL, create2Deployment, multiSendData, packSafeCall } from "./hoodi-safe-createcall.mjs";

test("CreateCall deployment is deterministic and encodes only zero-value CREATE2", () => {
  const bytecode = "0x60006000f3";
  const salt = ethers.id("seba-hoodi-v1-test");
  const result = create2Deployment(bytecode, salt);
  assert.equal(result.to, CREATE_CALL);
  assert.equal(result.expectedAddress, ethers.getCreate2Address(CREATE_CALL, salt, ethers.keccak256(bytecode)));
  const iface = new ethers.Interface([
    "function performCreate2(uint256 value,bytes deploymentData,bytes32 salt) returns(address)",
  ]);
  const decoded = iface.decodeFunctionData("performCreate2", result.data);
  assert.equal(decoded.value, 0n);
  assert.equal(decoded.deploymentData, bytecode);
  assert.equal(decoded.salt, salt);
  assert.throws(() => create2Deployment("0x", salt), /bytecode/);
  assert.throws(() => create2Deployment(bytecode, "0x01"), /salt/);
});

test("MultiSend packs only zero-value CALLs in order", () => {
  const a = { to: CREATE_CALL, data: "0x1234" };
  const b = { to: CREATE_CALL, data: "0xabcd00" };
  const packed = packSafeCall(a);
  assert.equal(packed.slice(0, 4), "0x00");
  assert.equal(ethers.getAddress(`0x${packed.slice(4, 44)}`), CREATE_CALL);
  assert.equal(BigInt(`0x${packed.slice(44, 108)}`), 0n);
  assert.equal(BigInt(`0x${packed.slice(108, 172)}`), 2n);
  assert.equal(packed.slice(172), "1234");
  const batch = multiSendData([a, b]);
  const iface = new ethers.Interface(["function multiSend(bytes transactions)"]);
  const decoded = iface.decodeFunctionData("multiSend", batch);
  assert.equal(decoded.transactions, ethers.concat([packSafeCall(a), packSafeCall(b)]));
  assert.throws(() => multiSendData([]), /empty/);
  assert.throws(() => packSafeCall({ to: ethers.ZeroAddress, data: "0x1234" }), /address/);
});
