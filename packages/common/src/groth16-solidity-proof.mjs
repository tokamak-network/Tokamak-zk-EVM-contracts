export function toGroth16SolidityProof(proof) {
  assertSnarkjsGroth16Proof(proof);
  return {
    pA: [
      ...splitBls12381FieldElement(proof.pi_a[0]),
      ...splitBls12381FieldElement(proof.pi_a[1]),
    ],
    pB: [
      ...splitBls12381FieldElement(proof.pi_b[0][1]),
      ...splitBls12381FieldElement(proof.pi_b[0][0]),
      ...splitBls12381FieldElement(proof.pi_b[1][1]),
      ...splitBls12381FieldElement(proof.pi_b[1][0]),
    ],
    pC: [
      ...splitBls12381FieldElement(proof.pi_c[0]),
      ...splitBls12381FieldElement(proof.pi_c[1]),
    ],
  };
}

export function splitBls12381FieldElement(value) {
  const hexValue = BigInt(value).toString(16).padStart(96, "0");
  return [
    BigInt(`0x${hexValue.slice(0, 32)}`),
    BigInt(`0x${hexValue.slice(32)}`),
  ];
}

function assertSnarkjsGroth16Proof(proof) {
  if (!proof || typeof proof !== "object") {
    throw new Error("Groth16 proof must be an object.");
  }
  if (!Array.isArray(proof.pi_a) || proof.pi_a.length < 2) {
    throw new Error("Groth16 proof is missing pi_a.");
  }
  if (!Array.isArray(proof.pi_b) || proof.pi_b.length < 2) {
    throw new Error("Groth16 proof is missing pi_b.");
  }
  if (!Array.isArray(proof.pi_b[0]) || proof.pi_b[0].length < 2) {
    throw new Error("Groth16 proof is missing pi_b[0].");
  }
  if (!Array.isArray(proof.pi_b[1]) || proof.pi_b[1].length < 2) {
    throw new Error("Groth16 proof is missing pi_b[1].");
  }
  if (!Array.isArray(proof.pi_c) || proof.pi_c.length < 2) {
    throw new Error("Groth16 proof is missing pi_c.");
  }
}
