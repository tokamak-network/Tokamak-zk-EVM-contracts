#!/usr/bin/env node

import fs from 'fs';
import pkg from 'js-sha3';
const { keccak256 } = pkg;

/**
 * Computes the block info hash from a JSON file containing block public inputs
 * This replicates the logic from BridgeProofManager._extractBlockInfoHashFromProof()
 * 
 * Note: The proof data contains block hashes for blocks n-1 through n-4,
 * while _computeBlockInfosHash uses blocks n-2 through n-5 (different range).
 * 
 * @param {string} jsonFilePath - Path to the JSON file (e.g., utils/instance.json)
 * @returns {string} - The computed keccak256 hash as a hex string
 */
function computeBlockInfoHash(jsonFilePath) {
    try {
        // Read and parse the JSON file
        const jsonData = JSON.parse(fs.readFileSync(jsonFilePath, 'utf8'));
        
        // Extract the a_pub_block array
        const blockInputs = jsonData.a_pub_block;
        
        if (!Array.isArray(blockInputs)) {
            throw new Error('Invalid JSON structure: a_pub_block should be an array');
        }
        
        // Block info should have 24 entries (12 variables × 2 for upper/lower 16 bytes)
        if (blockInputs.length < 24) {
            throw new Error('Block inputs too short - expected at least 24 entries');
        }
        
        console.log(`Total block inputs: ${blockInputs.length}`);
        console.log(`Block inputs (first 10 entries):`, blockInputs.slice(0, 10));
        
        // Extract block info from the array (replicating _extractBlockInfoHashFromProof logic)
        // Each block variable is stored as lower 16 bytes + upper 16 bytes
        // In _extractBlockInfoHashFromProof: for (uint256 i = 40; i < 64; i += 2)
        // 
        // Structure: COINBASE, TIMESTAMP, NUMBER, PREVRANDAO, GASLIMIT, CHAINID, SELFBALANCE, BASEFEE, 
        //           then 4 block hashes (n-1, n-2, n-3, n-4 in proof vs n-2, n-3, n-4, n-5 in _computeBlockInfosHash)
        let concatenatedData = '';
        
        for (let i = 0; i < 24; i += 2) {
            // Get lower and upper 16 bytes (matching the Solidity function)
            let lower = blockInputs[i];      // publicInputs[i] in Solidity
            let upper = blockInputs[i + 1];  // publicInputs[i + 1] in Solidity
            
            // Remove '0x' prefix if present
            if (lower.startsWith('0x')) {
                lower = lower.slice(2);
            }
            if (upper.startsWith('0x')) {
                upper = upper.slice(2);
            }
            
            // Convert to proper uint128 (16 bytes) - truncate if longer, pad if shorter
            // uint128 in Solidity is exactly 16 bytes (128 bits)
            if (lower.length > 32) lower = lower.slice(-32); // Take last 32 hex chars (16 bytes)
            if (upper.length > 32) upper = upper.slice(-32); // Take last 32 hex chars (16 bytes)
            
            lower = lower.padStart(32, '0');  // Pad to exactly 16 bytes
            upper = upper.padStart(32, '0');  // Pad to exactly 16 bytes
            
            // Combine as upper + lower (back to matching Solidity's: bytes16(uint128(upper)), bytes16(uint128(lower)))
            // This means upper comes first, then lower
            concatenatedData += upper + lower;
            
            console.log(`Variable ${Math.floor(i/2)}: lower=${blockInputs[i]}, upper=${blockInputs[i+1]} -> ${upper}${lower}`);
        }
        
        // Convert hex string to buffer for keccak256
        const dataBuffer = Buffer.from(concatenatedData, 'hex');
        
        // Compute keccak256 hash
        const hash = '0x' + keccak256(dataBuffer);
        
        console.log(`Concatenated data length: ${concatenatedData.length} hex chars (${concatenatedData.length/2} bytes)`);
        console.log(`Computed block info hash: ${hash}`);
        
        return hash;
        
    } catch (error) {
        console.error('Error computing block info hash:', error.message);
        throw error;
    }
}

/**
 * Main execution function
 */
function main() {
    console.log('=== Block Info Hash Computer ===');
    console.log('This script replicates the hash computation from BridgeProofManager._extractBlockInfoHashFromProof()');
    console.log('');
    
    // Get file path from command line arguments
    const args = process.argv.slice(2);
    
    if (args.length === 0) {
        console.log('Usage: node computeBlockInfoHash.js <path-to-json-file>');
        console.log('Example: node computeBlockInfoHash.js utils/instance.json');
        console.log('');
        console.log('Note: This script processes the a_pub_block array from the JSON file.');
        process.exit(1);
    }
    
    const jsonFilePath = args[0];
    
    try {
        const hash = computeBlockInfoHash(jsonFilePath);
        console.log('\n=== RESULT ===');
        console.log(`Block Info Hash: ${hash}`);
        console.log('');
        console.log('This hash represents the block information used in proof verification.');
    } catch (error) {
        console.error('Failed to compute hash:', error.message);
        process.exit(1);
    }
}

// Run main function if script is executed directly
if (import.meta.url === `file://${process.argv[1]}`) {
    main();
}

export { computeBlockInfoHash };