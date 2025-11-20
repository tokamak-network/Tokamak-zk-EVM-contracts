import { SimpleQuaternaryTree } from "./simpleQuaternaryTree.js";
import { computeLeaf } from "./merkleTree.js";

/**
 * Generate merkle proof for a specific user's withdrawal - SIMPLIFIED INTERFACE
 * 
 * Usage: node generateProofSimple.js <channelId> <userL2Address> <finalStateRoot>
 * 
 * This version uses a much simpler interface by hardcoding the test participant data.
 * For production, participant data would come from the contract or be passed differently.
 */

function generateWithdrawalProof() {
  const inputs = process.argv.slice(2);
  
  // Check if we're in quiet mode for FFI
  const isQuiet = process.env.FFI_MODE === 'true' || process.argv.includes('--ffi');

  if (inputs.length !== 3) {
    if (!isQuiet) {
      console.error(`Expected 3 arguments, got ${inputs.length}`);
      console.error('Usage: node generateProofSimple.js <channelId> <userL2Address> <finalStateRoot>');
      console.error('Example: node generateProofSimple.js 0 0xd69B7AaaE8C1c9F0546AfA4Fd8eD39741cE3f59F 0x123...');
    }
    process.exit(1);
  }

  // Parse inputs
  const channelId = inputs[0];
  const userL2Address = inputs[1];
  const finalStateRoot = inputs[2];

  // Hardcoded test participant data (in a real implementation, this would come from the contract)
  const participantsData = [
    {
      participantRoot: "0x8449acb4300b58b00e4852ab07d43f298eaa35688eaa3917ca205f20e6db73e8",
      l2Address: "0xd69B7AaaE8C1c9F0546AfA4Fd8eD39741cE3f59F", // participant1
      balance: "1000000000000000000"
    },
    {
      participantRoot: "0x3bec727653ae8d56ac6d9c103182ff799fe0a3b512e9840f397f0d21848373e8", 
      l2Address: "0xb18E7CdB6Aa28Cc645227041329896446A1478bd", // participant2
      balance: "1000000000000000000"
    },
    {
      participantRoot: "0x11e1e541a59fb2cd7fa4371d63103972695ee4bb4d1e646e72427cf6cdc16498",
      l2Address: "0x9D70617FF571Ac34516C610a51023EE1F28373e8", // participant3
      balance: "1000000000000000000"
    }
  ];

  if (!isQuiet) {
    console.log(`Generating withdrawal proof for:`);
    console.log(`- Channel ID: ${channelId}`);
    console.log(`- User L2 Address: ${userL2Address}`);
    console.log(`- Final State Root: ${finalStateRoot}`);
    console.log(`- Total participants: ${participantsData.length}`);
  }

  try {
    // Find user's index in participants data
    let userLeafIndex = -1;
    let userParticipantRoot = null;
    let userBalance = null;
    
    for (let i = 0; i < participantsData.length; i++) {
      const participant = participantsData[i];
      if (participant.l2Address.toLowerCase() === userL2Address.toLowerCase()) {
        userLeafIndex = i;
        userParticipantRoot = participant.participantRoot;
        userBalance = participant.balance;
        if (!isQuiet) console.log(`\nFound user at index ${i} with balance ${userBalance}`);
        break;
      }
    }
    
    if (userLeafIndex === -1) {
      throw new Error(`User's L2 address ${userL2Address} not found in participants data`);
    }

    // Build the final state tree with individual participant roots
    if (!isQuiet) console.log(`\nStep 1: Building tree with individual participant roots...`);
    
    const tree = new SimpleQuaternaryTree(3);
    const leaves = [];
    
    for (const { participantRoot, l2Address, balance } of participantsData) {
      const leaf = computeLeaf(participantRoot, l2Address, balance);
      leaves.push(leaf);
    }
    
    tree.insertAll(leaves);
    const computedTreeRoot = tree.root();
    
    if (!isQuiet) {
      console.log(`Computed tree root: ${computedTreeRoot}`);
      console.log(`Expected finalStateRoot: ${finalStateRoot}`);
      console.log(`Tree root matches finalStateRoot: ${computedTreeRoot === finalStateRoot ? 'YES' : 'NO'}`);
    }
    
    // Compute user's leaf exactly like the contract does during withdrawal  
    const userLeafValue = computeLeaf(userParticipantRoot, userL2Address, userBalance);
    if (!isQuiet) console.log(`\nUser's withdrawal leaf: ${userLeafValue} at index ${userLeafIndex}`);
    
    // Generate merkle proof for the user's specific leaf
    const proofData = tree.proof(userLeafIndex);
    if (!isQuiet) {
      console.log(`\nGenerating proof for user's leaf at index: ${userLeafIndex}`);
      console.log(`Merkle proof has ${proofData.pathElements.length} elements`);
    }
    
    // Verify our proof locally
    const isValid = tree.verifyProof(userLeafIndex, userLeafValue, proofData.pathElements);
    if (!isQuiet) console.log(`\n✓ Proof verification: ${isValid ? 'PASSED' : 'FAILED'}`);
    
    if (!isValid) {
      throw new Error('Generated proof failed local verification');
    }

    const result = {
      channelId,
      claimedBalance: userBalance, 
      leafIndex: userLeafIndex,
      merkleProof: proofData.pathElements,
      leafValue: userLeafValue,
      userL2Address,
      computedTreeRoot,
      expectedFinalRoot: finalStateRoot
    };

    return result;

  } catch (error) {
    if (!isQuiet) console.error('\n❌ Proof generation failed:', error);
    throw error;
  }
}

// Main execution
if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    const proofData = generateWithdrawalProof();
    
    // Check if we're running in FFI mode (suppress logs for Foundry)
    const isFFIMode = process.env.FFI_MODE === 'true' || process.argv.includes('--ffi');
    
    if (isFFIMode) {
      // Output simple format for FFI parsing: channelId,claimedBalance,leafIndex,proof1,proof2,...
      console.log(`${proofData.channelId},${proofData.claimedBalance},${proofData.leafIndex},${proofData.merkleProof.join(',')}`);
    } else {
      // Human-readable output
      console.log('\n✅ Withdrawal proof generated successfully!');
      console.log('\n📋 Proof Data for withdraw:');
      console.log(`channelId: ${proofData.channelId}`);
      console.log(`claimedBalance: ${proofData.claimedBalance}`);
      console.log(`leafIndex: ${proofData.leafIndex}`);
      console.log(`merkleProof: [${proofData.merkleProof.map(p => `"${p}"`).join(', ')}]`);
      
      console.log('\n🔧 Smart Contract Call:');
      console.log('withdraw(');
      console.log(`  ${proofData.channelId}, // channelId`);
      console.log(`  ${proofData.claimedBalance}, // claimedBalance`);
      console.log(`  ${proofData.leafIndex}, // leafIndex`);
      console.log(`  [${proofData.merkleProof.map(p => `"${p}"`).join(', ')}] // merkleProof`);
      console.log(')');
      
      // Also output as JSON for programmatic use
      console.log('\n📄 JSON Output:');
      console.log(JSON.stringify(proofData, null, 2));
    }
    
  } catch (error) {
    if (process.env.FFI_MODE === 'true' || process.argv.includes('--ffi')) {
      // In FFI mode, output error in a way that won't break parsing
      console.error(JSON.stringify({error: error.message}));
    } else {
      console.error('Script failed:', error);
    }
    process.exit(1);
  }
}

export default generateWithdrawalProof;