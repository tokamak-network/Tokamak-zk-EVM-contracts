#!/usr/bin/env node

import pkg from 'js-sha3';
const { keccak256 } = pkg;

/**
 * Computes the block info hash using actual block data from StateInitialized event
 * This should match what _computeBlockInfosHash produces
 */
function computeBlockHashFromEventData() {
    console.log('=== Computing Block Hash from StateInitialized Event Data ===');
    
    // Data from the StateInitialized event
    const blockData = {
        blockNumber: 10042082,
        timestamp: 1768395648,
        prevrandao: BigInt('61187585605546888283688024508636489663394840223037630789961933750249413663611'),
        gaslimit: 60000000,
        basefee: 1070733430,
        coinbase: '0x4dF6EB2EC570B58cC64f540247A8AdFA11F1Cf63',
        chainId: 11155111,
        selfbalance: 0,
        // Block hashes would be computed as blockhash(block.number - 1) through blockhash(block.number - 4)
        // For this example, let's assume they are from the a_pub_block data (blocks n-1 to n-4)
        blockHash1: BigInt('0x5124141fe4d8f8248ff8fb31c6a0b8a73a91c006398956bd1190e17d2ad63c11'),
        blockHash2: BigInt('0x472ed29235baa4d8b63f2c7eb229c5b4d08f571e5dcb0f26c5cf5eeac0765018'),
        blockHash3: BigInt('0x6b429d3883eb84a2ab0a430c65e53a19103958f3cdc5ddb02423c32c9f268d5e'),
        blockHash4: BigInt('0x827c474d2507f1152f1bb1cde00f54888f93977b2c571e2ea67377a9d0265bea')
    };
    
    let concatenatedData = '';
    
    // 1. COINBASE (32 bytes total - upper 16 + lower 16)
    const coinbaseValue = BigInt(blockData.coinbase);
    const coinbaseUpper = (coinbaseValue >> 128n).toString(16).padStart(32, '0');
    const coinbaseLower = (coinbaseValue & ((1n << 128n) - 1n)).toString(16).padStart(32, '0');
    concatenatedData += coinbaseUpper + coinbaseLower;
    console.log(`COINBASE: ${blockData.coinbase} -> ${coinbaseUpper}${coinbaseLower}`);
    
    // 2. TIMESTAMP (32 bytes total - upper 16 + lower 16)
    const timestamp = BigInt(blockData.timestamp);
    const timestampUpper = (timestamp >> 128n).toString(16).padStart(32, '0');
    const timestampLower = (timestamp & ((1n << 128n) - 1n)).toString(16).padStart(32, '0');
    concatenatedData += timestampUpper + timestampLower;
    console.log(`TIMESTAMP: ${blockData.timestamp} -> ${timestampUpper}${timestampLower}`);
    
    // 3. NUMBER (32 bytes total - upper 16 + lower 16)
    const number = BigInt(blockData.blockNumber);
    const numberUpper = (number >> 128n).toString(16).padStart(32, '0');
    const numberLower = (number & ((1n << 128n) - 1n)).toString(16).padStart(32, '0');
    concatenatedData += numberUpper + numberLower;
    console.log(`NUMBER: ${blockData.blockNumber} -> ${numberUpper}${numberLower}`);
    
    // 4. PREVRANDAO (32 bytes total - upper 16 + lower 16)
    const prevrandaoUpper = (blockData.prevrandao >> 128n).toString(16).padStart(32, '0');
    const prevrandaoLower = (blockData.prevrandao & ((1n << 128n) - 1n)).toString(16).padStart(32, '0');
    concatenatedData += prevrandaoUpper + prevrandaoLower;
    console.log(`PREVRANDAO: ${blockData.prevrandao.toString()} -> ${prevrandaoUpper}${prevrandaoLower}`);
    
    // 5. GASLIMIT (32 bytes total - upper 16 + lower 16)
    const gaslimit = BigInt(blockData.gaslimit);
    const gaslimitUpper = (gaslimit >> 128n).toString(16).padStart(32, '0');
    const gaslimitLower = (gaslimit & ((1n << 128n) - 1n)).toString(16).padStart(32, '0');
    concatenatedData += gaslimitUpper + gaslimitLower;
    console.log(`GASLIMIT: ${blockData.gaslimit} -> ${gaslimitUpper}${gaslimitLower}`);
    
    // 6. CHAINID (32 bytes total - upper 16 + lower 16)
    const chainId = BigInt(blockData.chainId);
    const chainIdUpper = (chainId >> 128n).toString(16).padStart(32, '0');
    const chainIdLower = (chainId & ((1n << 128n) - 1n)).toString(16).padStart(32, '0');
    concatenatedData += chainIdUpper + chainIdLower;
    console.log(`CHAINID: ${blockData.chainId} -> ${chainIdUpper}${chainIdLower}`);
    
    // 7. SELFBALANCE (32 bytes total - upper 16 + lower 16)
    const selfbalance = BigInt(blockData.selfbalance);
    const selfbalanceUpper = (selfbalance >> 128n).toString(16).padStart(32, '0');
    const selfbalanceLower = (selfbalance & ((1n << 128n) - 1n)).toString(16).padStart(32, '0');
    concatenatedData += selfbalanceUpper + selfbalanceLower;
    console.log(`SELFBALANCE: ${blockData.selfbalance} -> ${selfbalanceUpper}${selfbalanceLower}`);
    
    // 8. BASEFEE (32 bytes total - upper 16 + lower 16)
    const basefee = BigInt(blockData.basefee);
    const basefeeUpper = (basefee >> 128n).toString(16).padStart(32, '0');
    const basefeeLower = (basefee & ((1n << 128n) - 1n)).toString(16).padStart(32, '0');
    concatenatedData += basefeeUpper + basefeeLower;
    console.log(`BASEFEE: ${blockData.basefee} -> ${basefeeUpper}${basefeeLower}`);
    
    // 9-12. Block hashes 1-4 blocks ago
    const blockHashes = [blockData.blockHash1, blockData.blockHash2, blockData.blockHash3, blockData.blockHash4];
    for (let i = 0; i < blockHashes.length; i++) {
        const blockHash = blockHashes[i];
        const blockHashUpper = (blockHash >> 128n).toString(16).padStart(32, '0');
        const blockHashLower = (blockHash & ((1n << 128n) - 1n)).toString(16).padStart(32, '0');
        concatenatedData += blockHashUpper + blockHashLower;
        console.log(`BLOCKHASH${i+1}: 0x${blockHash.toString(16)} -> ${blockHashUpper}${blockHashLower}`);
    }
    
    // Compute hash
    const buffer = Buffer.from(concatenatedData, 'hex');
    const hash = '0x' + keccak256(buffer);
    
    console.log(`\nConcatenated data length: ${concatenatedData.length} hex chars`);
    console.log(`Computed hash: ${hash}`);
    console.log(`Expected _computeBlockInfosHash result: 0x99bb0c6be082fed8813c4488a6e24d6471787aa15f88a8fa6344ced5c68378ac`);
    console.log(`Match: ${hash === '0x99bb0c6be082fed8813c4488a6e24d6471787aa15f88a8fa6344ced5c68378ac'}`);
    
    return hash;
}

// Run the computation
computeBlockHashFromEventData();