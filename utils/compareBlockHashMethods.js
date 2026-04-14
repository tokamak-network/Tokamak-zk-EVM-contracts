#!/usr/bin/env node

import fs from 'fs';
import pkg from 'js-sha3';
import { addHexPrefix, hexToBigInt } from '@ethereumjs/util';
const { keccak256 } = pkg;

/**
 * Method 1: Similar to _computeBlockInfosHash
 * Reconstructs 32-byte values from pairs and encodes as bytes16(upper), bytes16(lower)
 */
function computeBlockInfosHashStyle(blockInputs) {
    console.log('\n=== Method 1: _computeBlockInfosHash Style ===');
    
    let concatenatedData = '';
    
    // Process 12 block variables (24 values total)
    for (let i = 0; i < 24; i += 2) {
        let lower = blockInputs[i];
        let upper = blockInputs[i + 1];
        
        // Remove 0x prefix
        if (lower.startsWith('0x')) lower = lower.slice(2);
        if (upper.startsWith('0x')) upper = upper.slice(2);
        
        // Pad to 32 hex chars each (16 bytes)
        lower = lower.padStart(32, '0');
        upper = upper.padStart(32, '0');
        
        // Reconstruct the original 32-byte value
        // lower contains the lower 16 bytes, upper contains the upper 16 bytes
        const originalValue = upper + lower; // upper 16 bytes + lower 16 bytes
        
        // Now split it back for bytes16(uint128(value >> 128)), bytes16(uint128(value))
        const value = hexToBigInt(addHexPrefix(originalValue));
        const upperPart = (value >> 128n).toString(16).padStart(32, '0'); // bytes16(uint128(value >> 128))
        const lowerPart = (value & ((1n << 128n) - 1n)).toString(16).padStart(32, '0'); // bytes16(uint128(value))
        
        // Encode as bytes16(upper), bytes16(lower) - matching Solidity abi.encodePacked
        concatenatedData += upperPart + lowerPart;
        
        console.log(`Variable ${Math.floor(i/2)}: reconstructed=${originalValue} -> encoded=${upperPart}${lowerPart}`);
    }
    
    const buffer1 = Buffer.from(concatenatedData, 'hex');
    const hash1 = '0x' + keccak256(buffer1);
    
    console.log(`Method 1 concatenated data: ${concatenatedData.length} hex chars`);
    console.log(`Method 1 hash: ${hash1}`);
    
    return hash1;
}

/**
 * Method 2: Similar to _extractBlockInfoHashFromProof  
 * Treats pairs as (lower, upper) and encodes as bytes16(upper), bytes16(lower)
 */
function extractBlockInfoHashStyle(blockInputs) {
    console.log('\n=== Method 2: _extractBlockInfoHashFromProof Style ===');
    
    let concatenatedData = '';
    
    // Process pairs directly as lower/upper
    for (let i = 0; i < 24; i += 2) {
        let lower = blockInputs[i];      // publicInputs[i]
        let upper = blockInputs[i + 1];  // publicInputs[i + 1]
        
        // Remove 0x prefix
        if (lower.startsWith('0x')) lower = lower.slice(2);
        if (upper.startsWith('0x')) upper = upper.slice(2);
        
        // Pad to 32 hex chars (16 bytes) for uint128 truncation
        lower = lower.padStart(32, '0');
        upper = upper.padStart(32, '0');
        
        // Encode as bytes16(uint128(upper)), bytes16(uint128(lower))
        concatenatedData += upper + lower;
        
        console.log(`Pair ${Math.floor(i/2)}: lower=${blockInputs[i]}, upper=${blockInputs[i+1]} -> ${upper}${lower}`);
    }
    
    const buffer2 = Buffer.from(concatenatedData, 'hex');
    const hash2 = '0x' + keccak256(buffer2);
    
    console.log(`Method 2 concatenated data: ${concatenatedData.length} hex chars`);
    console.log(`Method 2 hash: ${hash2}`);
    
    return hash2;
}

/**
 * Main function
 */
function main() {
    console.log('=== Block Hash Method Comparison ===');
    
    const args = process.argv.slice(2);
    if (args.length === 0) {
        console.log('Usage: node compareBlockHashMethods.js <path-to-json-file>');
        process.exit(1);
    }
    
    try {
        const jsonData = JSON.parse(fs.readFileSync(args[0], 'utf8'));
        const blockInputs = jsonData.a_pub_block;
        
        if (!Array.isArray(blockInputs) || blockInputs.length < 24) {
            throw new Error('Invalid a_pub_block data');
        }
        
        console.log('Block inputs:', blockInputs.slice(0, 6), '... (24 total)');
        
        const hash1 = computeBlockInfosHashStyle(blockInputs);
        const hash2 = extractBlockInfoHashStyle(blockInputs);
        
        console.log('\n=== COMPARISON ===');
        console.log(`Method 1 (_computeBlockInfosHash style): ${hash1}`);
        console.log(`Method 2 (_extractBlockInfoHashFromProof style): ${hash2}`);
        console.log(`Hashes match: ${hash1 === hash2}`);
        
        console.log('\nExpected hash: 0xf296a7e2ea8f4a80e31abe6135d96a70563a691d77fd9a19d8fb4bacafbb7baa');
        console.log(`Method 1 matches expected: ${hash1 === '0xf296a7e2ea8f4a80e31abe6135d96a70563a691d77fd9a19d8fb4bacafbb7baa'}`);
        console.log(`Method 2 matches expected: ${hash2 === '0xf296a7e2ea8f4a80e31abe6135d96a70563a691d77fd9a19d8fb4bacafbb7baa'}`);
        
    } catch (error) {
        console.error('Error:', error.message);
        process.exit(1);
    }
}

if (import.meta.url === `file://${process.argv[1]}`) {
    main();
}
