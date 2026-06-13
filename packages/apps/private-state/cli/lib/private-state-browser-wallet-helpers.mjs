import {
  ethers,
  getAddress,
} from "ethers";

export function personalSignPayload(message) {
  if (typeof message === "string") {
    return ethers.hexlify(ethers.toUtf8Bytes(message));
  }
  return ethers.hexlify(message);
}

export function buildEip712Payload({ domain, types, value }) {
  return {
    types: {
      EIP712Domain: eip712DomainType(domain),
      ...types,
    },
    primaryType: Object.keys(types)[0],
    domain: normalizeTypedDataValue(domain),
    message: normalizeTypedDataValue(value),
  };
}

export function eip712DomainType(domain) {
  return [
    ["name", "string"],
    ["version", "string"],
    ["chainId", "uint256"],
    ["verifyingContract", "address"],
    ["salt", "bytes32"],
  ]
    .filter(([name]) => domain?.[name] !== undefined && domain?.[name] !== null)
    .map(([name, type]) => ({ name, type }));
}

export function normalizeTypedDataValue(value) {
  if (typeof value === "bigint") {
    return value.toString();
  }
  if (Array.isArray(value)) {
    return value.map((entry) => normalizeTypedDataValue(entry));
  }
  if (value instanceof Uint8Array) {
    return ethers.hexlify(value);
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .filter(([, entry]) => entry !== undefined)
        .map(([key, entry]) => [key, normalizeTypedDataValue(entry)]),
    );
  }
  return value;
}

export function normalizeBrowserTransaction(transaction) {
  const tx = {};
  for (const [sourceKey, targetKey] of [
    ["from", "from"],
    ["to", "to"],
    ["data", "data"],
  ]) {
    if (transaction[sourceKey] !== undefined && transaction[sourceKey] !== null) {
      tx[targetKey] = sourceKey === "data" ? ethers.hexlify(transaction[sourceKey]) : getAddress(transaction[sourceKey]);
    }
  }
  for (const [sourceKey, targetKey] of [
    ["value", "value"],
    ["gasLimit", "gas"],
    ["gasPrice", "gasPrice"],
    ["maxFeePerGas", "maxFeePerGas"],
    ["maxPriorityFeePerGas", "maxPriorityFeePerGas"],
    ["nonce", "nonce"],
    ["chainId", "chainId"],
  ]) {
    if (transaction[sourceKey] !== undefined && transaction[sourceKey] !== null) {
      tx[targetKey] = ethers.toQuantity(transaction[sourceKey]);
    }
  }
  return tx;
}

export function safeJsonForScript(value) {
  return JSON.stringify(value)
    .replaceAll("<", "\\u003c")
    .replaceAll(">", "\\u003e")
    .replaceAll("&", "\\u0026")
    .replaceAll("\u2028", "\\u2028")
    .replaceAll("\u2029", "\\u2029");
}
