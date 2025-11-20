#!/usr/bin/env node

import snarkjs from "snarkjs";
import fs from "fs";
import path from "path";
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * Script to generate Groth16 proofs for testing the RollupBridge contract
 * Usage: node generateGroth16Proof.js [participant1_mpt_key] [participant1_balance] [participant2_mpt_key] [participant2_balance] [participant3_mpt_key] [participant3_balance]
 * Example: node generateGroth16Proof.js 1461501637330902918203684832716283019655932542976 1000000000000000000 1240746827509629851092253602051341618533 2000000000000000000 1033628234203421458715762354672 3000000000000000000
 */

async function generateProof() {
    const args = process.argv.slice(2);
    
    if (args.length < 6) {
        console.log("Usage: node generateGroth16Proof.js [mpt_key1] [balance1] [mpt_key2] [balance2] [mpt_key3] [balance3]");
        console.log("Example: node generateGroth16Proof.js 1461501637330902918203684832716283019655932542976 1000000000000000000 1240746827509629851092253602051341618533 2000000000000000000 1033628234203421458715762354672 3000000000000000000");
        process.exit(1);
    }

    // Parse arguments
    const participants = [];
    for (let i = 0; i < 6; i += 2) {
        participants.push({
            mptKey: args[i],
            balance: args[i + 1]
        });
    }

    // Build input for the circuit
    const input = {
        merkle_keys: new Array(50).fill("0"),
        storage_values: new Array(50).fill("0")
    };

    // Fill in the actual participant data
    for (let i = 0; i < participants.length; i++) {
        input.merkle_keys[i] = participants[i].mptKey;
        input.storage_values[i] = participants[i].balance;
    }

    // Paths to circuit files
    const circuitWasm = path.join(__dirname, "../../groth16/circuits/build/merkle_tree_circuit_js/merkle_tree_circuit.wasm");
    const circuitZkey = path.join(__dirname, "../../groth16/trusted-setup/merkle_tree_circuit_final.zkey");

    try {
        console.log("Generating witness...");
        console.log("Input:", JSON.stringify(input, null, 2));

        // Check if circuit files exist
        if (!fs.existsSync(circuitWasm)) {
            throw new Error(`Circuit WASM file not found at: ${circuitWasm}`);
        }
        if (!fs.existsSync(circuitZkey)) {
            throw new Error(`Circuit zkey file not found at: ${circuitZkey}`);
        }

        // Generate witness
        const { witness } = await snarkjs.wtns.calculate(input, circuitWasm);

        console.log("Generating proof...");
        
        // Generate the proof
        const { proof, publicSignals } = await snarkjs.groth16.prove(circuitZkey, witness);

        console.log("\\n=== GENERATED PROOF ===");
        console.log("Proof A:", [proof.pi_a[0], proof.pi_a[1]]);
        console.log("Proof B:", [[proof.pi_b[0][1], proof.pi_b[0][0]], [proof.pi_b[1][1], proof.pi_b[1][0]]]);
        console.log("Proof C:", [proof.pi_c[0], proof.pi_c[1]]);
        console.log("Public signals (first 10):", publicSignals.slice(0, 10));
        console.log("Merkle root (last signal):", publicSignals[publicSignals.length - 1]);

        // Format for Solidity test
        console.log("\\n=== SOLIDITY TEST FORMAT ===");
        console.log(`uint[2] memory pA = [uint(${proof.pi_a[0]}), uint(${proof.pi_a[1]})];`);
        console.log(`uint[2][2] memory pB = [[uint(${proof.pi_b[0][1]}), uint(${proof.pi_b[0][0]})], [uint(${proof.pi_b[1][1]}), uint(${proof.pi_b[1][0]})]];`);
        console.log(`uint[2] memory pC = [uint(${proof.pi_c[0]}), uint(${proof.pi_c[1]})];`);
        console.log(`bytes32 merkleRoot = bytes32(uint256(${publicSignals[publicSignals.length - 1]}));`);

        // Save to files
        const outputDir = path.join(__dirname, "../proof-outputs");
        if (!fs.existsSync(outputDir)) {
            fs.mkdirSync(outputDir, { recursive: true });
        }

        fs.writeFileSync(path.join(outputDir, "proof.json"), JSON.stringify(proof, null, 2));
        fs.writeFileSync(path.join(outputDir, "public.json"), JSON.stringify(publicSignals, null, 2));
        fs.writeFileSync(path.join(outputDir, "input.json"), JSON.stringify(input, null, 2));

        console.log(`\\nFiles saved to: ${outputDir}`);

        // Verify the proof
        const verificationKey = JSON.parse(fs.readFileSync(path.join(__dirname, "../../groth16/trusted-setup/verification_key.json")));
        const isValid = await snarkjs.groth16.verify(verificationKey, publicSignals, proof);
        console.log("\\nProof verification:", isValid ? "✓ VALID" : "✗ INVALID");

    } catch (error) {
        console.error("Error generating proof:", error);
        process.exit(1);
    }
}

// Run the script
generateProof().catch(console.error);