import { ethers } from "ethers";

// Simple quaternary tree implementation for proof generation
export class SimpleQuaternaryTree {
  constructor(depth = 3) {
    this.depth = depth;
    this.maxLeaves = 4 ** depth;
    this.leaves = new Array(this.maxLeaves).fill(ethers.ZeroHash);
    this.tree = {}; // Store all nodes: tree[level][index] = hash
    
    // Initialize tree structure
    for (let level = 0; level <= depth; level++) {
      this.tree[level] = {};
    }
  }

  insert(index, leaf) {
    if (index >= this.maxLeaves) throw new Error("Index out of bounds");
    
    this.leaves[index] = leaf;
    this.tree[0][index] = leaf;
    
    // Rebuild the entire tree (simple but correct approach)
    this.rebuild();
  }

  insertAll(leaves) {
    for (let i = 0; i < leaves.length; i++) {
      if (i >= this.maxLeaves) break;
      this.leaves[i] = leaves[i];
      this.tree[0][i] = leaves[i];
    }
    this.rebuild();
  }

  rebuild() {
    // Build tree level by level
    for (let level = 1; level <= this.depth; level++) {
      const nodesInLevel = 4 ** (this.depth - level);
      
      for (let nodeIndex = 0; nodeIndex < nodesInLevel; nodeIndex++) {
        // Each node at this level is computed from 4 children at previous level
        const childBaseIndex = nodeIndex * 4;
        const prevLevel = level - 1;
        
        const child0 = this.tree[prevLevel][childBaseIndex] || ethers.ZeroHash;
        const child1 = this.tree[prevLevel][childBaseIndex + 1] || ethers.ZeroHash;
        const child2 = this.tree[prevLevel][childBaseIndex + 2] || ethers.ZeroHash;
        const child3 = this.tree[prevLevel][childBaseIndex + 3] || ethers.ZeroHash;
        
        this.tree[level][nodeIndex] = this.hashFour(child0, child1, child2, child3);
      }
    }
  }

  hashFour(a, b, c, d) {
    const packed = ethers.solidityPacked(["bytes32", "bytes32", "bytes32", "bytes32"], [a, b, c, d]);
    return ethers.keccak256(packed);
  }

  root() {
    return this.tree[this.depth][0] || ethers.ZeroHash;
  }

  proof(leafIndex) {
    if (leafIndex >= this.maxLeaves) throw new Error("Leaf index out of bounds");
    
    const pathElements = [];
    let currentIndex = leafIndex;
    
    for (let level = 0; level < this.depth; level++) {
      const childIndex = currentIndex % 4;
      const siblingBaseIndex = Math.floor(currentIndex / 4) * 4;
      
      // Add the 3 siblings (in order, excluding the child)
      for (let i = 0; i < 4; i++) {
        if (i !== childIndex) {
          const sibling = this.tree[level][siblingBaseIndex + i] || ethers.ZeroHash;
          pathElements.push(sibling);
        }
      }
      
      currentIndex = Math.floor(currentIndex / 4);
    }

    return {
      pathElements,
      leafIndex,
      leaf: this.tree[0][leafIndex]
    };
  }

  // Verify proof manually (for testing)
  verifyProof(leafIndex, leaf, proof) {
    let computedHash = leaf;
    let index = leafIndex;
    let proofIndex = 0;

    for (let level = 0; level < this.depth; level++) {
      const childIndex = index % 4;

      if (childIndex === 0) {
        computedHash = this.hashFour(computedHash, proof[proofIndex], proof[proofIndex + 1], proof[proofIndex + 2]);
      } else if (childIndex === 1) {
        computedHash = this.hashFour(proof[proofIndex], computedHash, proof[proofIndex + 1], proof[proofIndex + 2]);
      } else if (childIndex === 2) {
        computedHash = this.hashFour(proof[proofIndex], proof[proofIndex + 1], computedHash, proof[proofIndex + 2]);
      } else {
        computedHash = this.hashFour(proof[proofIndex], proof[proofIndex + 1], proof[proofIndex + 2], computedHash);
      }

      proofIndex += 3;
      index = Math.floor(index / 4);
    }

    return computedHash === this.root();
  }
}