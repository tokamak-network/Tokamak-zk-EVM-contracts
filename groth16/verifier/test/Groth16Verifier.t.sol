// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/Groth16Verifier.sol";
import "./UpdateTreeProofFixture.sol";

contract Groth16VerifierTest {
    function testVerifyProofAcceptsTheExampleProof() public {
        Groth16Verifier verifier = new Groth16Verifier();
        bool ok = verifier.verifyProof(
            UpdateTreeProofFixture.pA(),
            UpdateTreeProofFixture.pB(),
            UpdateTreeProofFixture.pC(),
            UpdateTreeProofFixture.pubSignals()
        );
        require(ok, "expected the updateTree example proof to verify");
    }

    function testVerifyProofRejectsTamperedPublicSignals() public {
        Groth16Verifier verifier = new Groth16Verifier();
        uint256[5] memory pubSignals = UpdateTreeProofFixture.pubSignals();
        pubSignals[4] += 1;

        bool ok = verifier.verifyProof(
            UpdateTreeProofFixture.pA(),
            UpdateTreeProofFixture.pB(),
            UpdateTreeProofFixture.pC(),
            pubSignals
        );
        require(!ok, "expected verification to fail after tampering with public inputs");
    }
}
