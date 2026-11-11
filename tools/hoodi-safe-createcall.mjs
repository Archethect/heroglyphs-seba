// Pure encoders for reviewed, zero-value Hoodi Safe contract deployments.
import { ethers } from "ethers";

export const CREATE_CALL = "0x9b35Af71d77eaf8d7e40252370304687390A1A52";
export const CREATE_CALL_CODE_HASH = "0x2b3060c55fcb8275653e99ad511a71f67ba76934ed66a7d74d6e68b52afff889";

const createCall = new ethers.Interface([
  "function performCreate2(uint256 value,bytes deploymentData,bytes32 salt) returns(address)",
]);
const multiSend = new ethers.Interface(["function multiSend(bytes transactions)"]);

export function create2Deployment(bytecode, salt) {
  if (!ethers.isHexString(bytecode) || bytecode === "0x") throw new Error("deployment bytecode required");
  if (!ethers.isHexString(salt, 32)) throw new Error("32-byte CREATE2 salt required");
  return {
    to: CREATE_CALL,
    data: createCall.encodeFunctionData("performCreate2", [0, bytecode, salt]),
    expectedAddress: ethers.getCreate2Address(CREATE_CALL, salt, ethers.keccak256(bytecode)),
  };
}

export function packSafeCall({ to, data }) {
  if (!ethers.isAddress(to) || to === ethers.ZeroAddress) throw new Error("nonzero call address required");
  if (!ethers.isHexString(data)) throw new Error("hex call data required");
  return ethers.solidityPacked(
    ["uint8", "address", "uint256", "uint256", "bytes"],
    [0, to, 0, ethers.dataLength(data), data],
  );
}

export function multiSendData(calls) {
  if (!Array.isArray(calls) || calls.length === 0) throw new Error("empty Safe batch");
  return multiSend.encodeFunctionData("multiSend", [ethers.concat(calls.map(packSafeCall))]);
}
