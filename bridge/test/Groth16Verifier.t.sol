// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Groth16Verifier } from "../src/generated/Groth16Verifier.sol";
import { UpdateTreeProofFixture } from "./UpdateTreeProofFixture.sol";

contract Groth16VerifierTest {
    function testVerifyProofAcceptsTheExampleProof() public {
        Groth16Verifier verifier = new Groth16Verifier("0.2");
        bool ok = verifier.verifyProof(
            UpdateTreeProofFixture.pA(),
            UpdateTreeProofFixture.pB(),
            UpdateTreeProofFixture.pC(),
            UpdateTreeProofFixture.pubSignals()
        );
        require(ok, "expected the updateTree example proof to verify");
    }

    function testVerifyProofRejectsTamperedPublicSignals() public {
        Groth16Verifier verifier = new Groth16Verifier("0.2");
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

    function testExposesCompatibleBackendVersion() public {
        Groth16Verifier verifier = new Groth16Verifier("0.2");
        require(
            keccak256(bytes(verifier.compatibleBackendVersion())) == keccak256(bytes("0.2")),
            "unexpected compatible backend version"
        );
    }
}
