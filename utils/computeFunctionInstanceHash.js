#!/usr/bin/env node

import fs from 'fs';
import pkg from 'js-sha3';
const { keccak256 } = pkg;

/**
 * Computes the function instance hash from a JSON file containing public inputs
 * This replicates the logic from BridgeProofManager._extractFunctionInstanceHashFromProof()
 * 
 * @param {string} jsonFilePath - Path to the JSON file (e.g., test/verifier/proof1/a_pub_function.json)
 * @returns {string} - The computed keccak256 hash as a hex string
 */
function computeFunctionInstanceHash(jsonFilePath) {
    try {
        // Read and parse the JSON file
        const jsonData = JSON.parse(fs.readFileSync(jsonFilePath, 'utf8'));
        
        // Extract the a_pub_function array
        const publicInputs = jsonData.a_pub_function;
        
        if (!Array.isArray(publicInputs)) {
            throw new Error('Invalid JSON structure: a_pub_function should be an array');
        }
        
        // Function instance data starts at index 66 (based on Solidity implementation)
        // User data: 0-41, Block data: 42-65, Function data: 66+
        if (publicInputs.length <= 66) {
            throw new Error('Public inputs too short for function instance data');
        }
        
        // Extract function instance data starting from index 66
        const functionInstanceData = publicInputs.slice(66);
        
        console.log(`Total public inputs: ${publicInputs.length}`);
        console.log(`Function instance data length: ${functionInstanceData.length}`);
        console.log(`Function instance data (first 10 entries):`, functionInstanceData.slice(0, 10));
        
        // Convert hex strings to bytes and concatenate for keccak256
        // Each hex string represents a uint256 (32 bytes)
        let concatenatedData = '';
        
        for (let i = 0; i < functionInstanceData.length; i++) {
            let hexValue = functionInstanceData[i];
            
            // Remove '0x' prefix if present
            if (hexValue.startsWith('0x')) {
                hexValue = hexValue.slice(2);
            }
            
            // Pad to 64 characters (32 bytes) for uint256
            hexValue = hexValue.padStart(64, '0');
            concatenatedData += hexValue;
        }
        
        // Convert hex string to buffer for keccak256
        const dataBuffer = Buffer.from(concatenatedData, 'hex');
        
        // Compute keccak256 hash
        const hash = '0x' + keccak256(dataBuffer);
        
        console.log(`Concatenated data length: ${concatenatedData.length} hex chars (${concatenatedData.length/2} bytes)`);
        console.log(`Computed function instance hash: ${hash}`);
        
        return hash;
        
    } catch (error) {
        console.error('Error computing function instance hash:', error.message);
        throw error;
    }
}

/**
 * Main execution function
 */
function main() {
    console.log('=== Function Instance Hash Computer ===');
    console.log('This script replicates the hash computation from BridgeProofManager.sol');
    console.log('');
    
    // Get file path from command line arguments
    const args = process.argv.slice(2);
    
    if (args.length === 0) {
        console.log('Usage: node computeFunctionInstanceHash.js <path-to-json-file>');
        console.log('Example: node computeFunctionInstanceHash.js test/verifier/proof1/a_pub_function.json');
        console.log('');
        console.log('Note: This script now uses proper keccak256 from js-sha3 package.');
        process.exit(1);
    }
    
    const jsonFilePath = args[0];
    
    try {
        const hash = computeFunctionInstanceHash(jsonFilePath);
        console.log('\n=== RESULT ===');
        console.log(`Function Instance Hash: ${hash}`);
        console.log('');
        console.log('This hash should match the instancesHash in the registered function');
        console.log('when used in submitProofAndSignature verification.');
    } catch (error) {
        console.error('Failed to compute hash:', error.message);
        process.exit(1);
    }
}

// Run main function if script is executed directly
if (import.meta.url === `file://${process.argv[1]}`) {
    main();
}

export { computeFunctionInstanceHash };