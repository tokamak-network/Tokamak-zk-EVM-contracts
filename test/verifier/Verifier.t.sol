// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {TokamakVerifier} from "../../bridge/src/verifiers/TokamakVerifier.sol";

contract TokamakVerifierRootTest is Test {
    using stdJson for string;

    string internal constant PROOF_PATH = "./bridge/test/fixtures/mintNotes1-proof/resource/prove/fixture/proof.json";
    string internal constant PREPROCESS_PATH =
        "./bridge/test/fixtures/mintNotes1-proof/resource/preprocess/fixture/preprocess.json";
    string internal constant INSTANCE_PATH =
        "./bridge/test/fixtures/mintNotes1-proof/resource/synthesizer/fixture/instance.json";

    TokamakVerifier internal verifier;

    function setUp() public {
        verifier = new TokamakVerifier();
    }

    function testRejectsStaleMintNotes1Fixture() public {
        (
            uint128[] memory proofPart1,
            uint256[] memory proofPart2,
            uint128[] memory preprocessPart1,
            uint256[] memory preprocessPart2,
            uint256[] memory aPubUser,
            uint256[] memory aPubBlock
        ) = _loadFixtureBundle();

        vm.expectRevert(bytes("loadProof: Proof is invalid"));
        verifier.verify(proofPart1, proofPart2, preprocessPart1, preprocessPart2, aPubUser, aPubBlock);
    }

    function testRejectsModifiedProof() public {
        (
            uint128[] memory proofPart1,
            uint256[] memory proofPart2,
            uint128[] memory preprocessPart1,
            uint256[] memory preprocessPart2,
            uint256[] memory aPubUser,
            uint256[] memory aPubBlock
        ) = _loadFixtureBundle();

        proofPart2[0] += 1;

        vm.expectRevert();
        verifier.verify(proofPart1, proofPart2, preprocessPart1, preprocessPart2, aPubUser, aPubBlock);
    }

    function _loadFixtureBundle()
        internal
        view
        returns (
            uint128[] memory proofPart1,
            uint256[] memory proofPart2,
            uint128[] memory preprocessPart1,
            uint256[] memory preprocessPart2,
            uint256[] memory aPubUser,
            uint256[] memory aPubBlock
        )
    {
        string memory proofJson = vm.readFile(PROOF_PATH);
        string memory preprocessJson = vm.readFile(PREPROCESS_PATH);
        string memory instanceJson = vm.readFile(INSTANCE_PATH);

        proofPart1 = _toUint128Array(proofJson.readUintArray(".proof_entries_part1"));
        proofPart2 = proofJson.readUintArray(".proof_entries_part2");
        preprocessPart1 = _toUint128Array(preprocessJson.readUintArray(".preprocess_entries_part1"));
        preprocessPart2 = preprocessJson.readUintArray(".preprocess_entries_part2");
        aPubUser = instanceJson.readUintArray(".a_pub_user");
        aPubBlock = instanceJson.readUintArray(".a_pub_block");
    }

    function _toUint128Array(uint256[] memory input) internal pure returns (uint128[] memory output) {
        output = new uint128[](input.length);
        for (uint256 index = 0; index < input.length; index += 1) {
            output[index] = uint128(input[index]);
        }
    }
}
