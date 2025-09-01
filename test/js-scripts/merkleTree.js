import { ethers } from 'ethers';

function hashFour(a, b, c, d) {
  return ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(
    ['bytes32', 'bytes32', 'bytes32', 'bytes32'],
    [a, b, c, d]
  ));
}

function computeZeros(level) {
  let zero = ethers.ZeroHash;
  for (let i = 0; i < level; i++) {
    zero = hashFour(zero, zero, zero, zero);
  }
  return zero;
}

export class QuaternaryTree {
  constructor(depth) {
    this.depth = depth;
    this.storage = new Map();
    this.cachedSubtrees = new Map();
    this.nextLeafIndex = 0;
    this.roots = []; // Track all roots like the contract
    this.currentRootIndex = 0;
    
    // Pre-compute zero values for each level
    this.zeros = [];
    for (let level = 0; level <= depth; level++) {
      this.zeros[level] = computeZeros(level);
    }
  }

  init() {
    // Initialize empty tree with zero subtrees cached
    for (let level = 0; level <= this.depth; level++) {
      this.cachedSubtrees.set(this.levelToKey(level), this.zeros[level]);
    }
    
    // Set initial root (matching contract's initializeChannelState)
    const initialRoot = this.zeros[this.depth];
    this.roots.push(initialRoot);
    this.currentRootIndex = 0;
  }

  levelToKey(level) {
    return `level-${level}`;
  }

  static indexToKey(level, index) {
    return `${level}-${index}`;
  }

  getIndex(leaf) {
    for (const [key, value] of this.storage.entries()) {
      if (value === leaf && key.startsWith('0-')) {
        return parseInt(key.split('-')[1]);
      }
    }
    return -1;
  }

  root() {
    return this.roots[this.currentRootIndex] || this.zeros[this.depth];
  }
  
  getCurrentRoot() {
    return this.roots[this.currentRootIndex] || this.zeros[this.depth];
  }
  
  getLastRootInSequence() {
    return this.roots[this.roots.length - 1] || this.zeros[this.depth];
  }

  proof(index) {
    const leaf = this.storage.get(QuaternaryTree.indexToKey(0, index));
    if (!leaf) throw new Error("leaf not found");

    const pathElements = [];
    let currentIndex = index;

    for (let level = 0; level < this.depth; level++) {
      const childIndex = currentIndex % 4;
      
      // Get the 3 siblings needed for quaternary proof
      // We need to get actual stored values from the tree
      for (let i = 0; i < 4; i++) {
        if (i !== childIndex) {
          const siblingIndex = Math.floor(currentIndex / 4) * 4 + i;
          let sibling;
          
          // Check if this sibling exists in storage at level 0 (leaves)
          if (level === 0) {
            sibling = this.storage.get(QuaternaryTree.indexToKey(0, siblingIndex)) || this.zeros[level];
          } else {
            // For higher levels, we need to compute what the sibling would be
            // This is complex because the tree uses cached subtrees logic
            // For now, use zero as placeholder - this needs proper implementation
            sibling = this.zeros[level];
          }
          pathElements.push(sibling);
        }
      }
      
      currentIndex = Math.floor(currentIndex / 4);
    }

    return {
      root: this.root(),
      pathElements,
      childIndex: index % 4,
      leaf,
    };
  }

  insert(leaf) {
    const index = this.nextLeafIndex;
    this.update(index, leaf, true);
    this.nextLeafIndex++;
  }

  update(index, newLeaf, isInsert = false) {
    if (!isInsert && index >= this.nextLeafIndex) {
      throw Error("Use insert method for new elements.");
    } else if (isInsert && index < this.nextLeafIndex) {
      throw Error("Use update method for existing elements.");
    }

    // Check if tree is full
    const maxLeaves = 4 ** this.depth;
    if (index >= maxLeaves) {
      throw Error("MerkleTreeFull");
    }

    // Store the leaf
    this.storage.set(QuaternaryTree.indexToKey(0, index), newLeaf);

    // Update the cached subtrees and compute new root (matching contract exactly)
    let currentHash = newLeaf;
    let currentIndex = index;

    for (let level = 0; level < this.depth; level++) {
      if (currentIndex % 4 === 0) {
        // This is a leftmost node, cache it
        this.cachedSubtrees.set(this.levelToKey(level), currentHash);
        break;
      } else {
        // Compute parent hash using 4 children (matching contract _insertLeaf)
        const left = this.cachedSubtrees.get(this.levelToKey(level)) || this.zeros[level];
        const child2 = currentIndex % 4 >= 2 ? currentHash : ethers.ZeroHash;
        const child3 = currentIndex % 4 === 3 ? currentHash : ethers.ZeroHash;
        const child4 = ethers.ZeroHash;

        currentHash = hashFour(left, child2, child3, child4);
        currentIndex = Math.floor(currentIndex / 4);
      }
    }

    // Update tree state (matching contract)
    if (isInsert) {
      this.nextLeafIndex = index + 1;
    }

    // Store new root (matching contract)
    this.currentRootIndex += 1;
    this.roots.push(currentHash);
    this.storage.set(QuaternaryTree.indexToKey(this.depth, 0), currentHash);
  }

  traverse(index, fn) {
    let currentIndex = index;
    for (let level = 0; level < this.depth; level++) {
      fn(level, currentIndex);
      currentIndex = Math.floor(currentIndex / 4);
    }
  }
}


// Build tree exactly like contract does during initializeChannelState
export function buildInitialStateTree(channelId, participants) {
  const TREE_DEPTH = 3;
  const tree = new QuaternaryTree(TREE_DEPTH);
  tree.init();
  
  let nonce = 0;
  
  // Insert leaves sequentially like the contract does
  for (let i = 0; i < participants.length; i++) {
    const { l2Address, balance } = participants[i];
    
    // Compute prevRoot based on current nonce (matching contract logic)
    let prevRoot;
    if (nonce === 0) {
      prevRoot = ethers.zeroPadValue(ethers.toBeHex(BigInt(channelId)), 32);
    } else {
      prevRoot = tree.getLastRootInSequence();
    }
    
    // Compute leaf with current prevRoot
    const leaf = computeLeaf(prevRoot, l2Address, balance);
    
    // Insert leaf (this updates the tree and creates a new root)
    tree.insert(leaf);
    
    nonce++;
  }
  
  return tree;
}

// Build final state tree where all participants use the same prevRoot
export function buildFinalStateTree(finalStateRoot, participants) {
  const TREE_DEPTH = 3;
  const tree = new QuaternaryTree(TREE_DEPTH);
  tree.init();
  
  // In final state, ALL participants use the same prevRoot (finalStateRoot)
  const leaves = [];
  for (const { l2Address, balance } of participants) {
    const leaf = computeLeaf(finalStateRoot, l2Address, balance);
    leaves.push(leaf);
  }
  
  // Insert all leaves at once
  for (const leaf of leaves) {
    tree.insert(leaf);
  }
  
  return tree;
}

// Build final state tree where each participant uses their individual prevRoot
export function buildFinalStateTreeWithIndividualRoots(participants) {
  const TREE_DEPTH = 3;
  const tree = new QuaternaryTree(TREE_DEPTH);
  tree.init();
  
  // Each participant uses their specific prevRoot
  const leaves = [];
  for (const { participantRoot, l2Address, balance } of participants) {
    const leaf = computeLeaf(participantRoot, l2Address, balance);
    leaves.push(leaf);
  }
  
  // Insert all leaves at once
  for (const leaf of leaves) {
    tree.insert(leaf);
  }
  
  return tree;
}

// Legacy function for backward compatibility
export function merkleTree(leaves) {
  const TREE_DEPTH = 3;
  const tree = new QuaternaryTree(TREE_DEPTH);
  tree.init();
  
  for (const leaf of leaves) {
    tree.insert(leaf);
  }
  
  return tree;
}

// Helper function to compute leaf like the contract does
export function computeLeaf(prevRoot, l2Address, balance) {
  // RLC computation matching contract's _computeLeafPure
  // Use abi.encodePacked (like the contract) instead of abi.encode
  const l2AddressBytes32 = ethers.zeroPadValue(ethers.toBeHex(BigInt(l2Address)), 32);
  const packedData = ethers.concat([prevRoot, l2AddressBytes32]);
  const gamma = ethers.keccak256(packedData);
  
  // RLC formula: l2Address + gamma * balance
  const leafValue = (BigInt(l2Address) + BigInt(gamma) * BigInt(balance)) % (2n ** 256n);
  return ethers.zeroPadValue(ethers.toBeHex(leafValue), 32);
}
