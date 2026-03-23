// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {TokamakVerifier} from "../TokamakVerifier.sol";

contract TokamakVerifierTest is Test {
    using stdJson for string;

    string internal constant PROOF_PATH = "./test/fixtures/mintNotes1-proof/resource/prove/output/proof.json";
    string internal constant PREPROCESS_PATH =
        "./test/fixtures/mintNotes1-proof/resource/preprocess/output/preprocess.json";
    string internal constant INSTANCE_PATH =
        "./test/fixtures/mintNotes1-proof/resource/synthesizer/output/instance.json";
    string internal constant SETUP_PARAMS_PATH =
        "../submodules/Tokamak-zk-EVM/dist/resource/qap-compiler/library/setupParams.json";

    TokamakVerifier internal verifier;

    function setUp() public {
        verifier = new TokamakVerifier();
    }

    function testVerifyMintNotes1Proof() public {
        string memory proofJson = vm.readFile(PROOF_PATH);
        string memory preprocessJson = vm.readFile(PREPROCESS_PATH);
        string memory instanceJson = vm.readFile(INSTANCE_PATH);
        string memory setupParamsJson = vm.readFile(SETUP_PARAMS_PATH);

        uint128[] memory proofPart1 = _toUint128Array(proofJson.readUintArray(".proof_entries_part1"));
        uint256[] memory proofPart2 = proofJson.readUintArray(".proof_entries_part2");
        uint128[] memory preprocessPart1 =
            _toUint128Array(preprocessJson.readUintArray(".preprocess_entries_part1"));
        uint256[] memory preprocessPart2 = preprocessJson.readUintArray(".preprocess_entries_part2");
        uint256[] memory publicInputs = _concatInstance(instanceJson);
        uint256 smax = abi.decode(vm.parseJson(setupParamsJson, ".s_max"), (uint256));

        uint256 gasBefore = gasleft();
        bool verified = verifier.verify(proofPart1, proofPart2, preprocessPart1, preprocessPart2, publicInputs, smax);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Tokamak verifier gas", gasUsed);
        assertTrue(verified, "expected verifier to accept the extracted proof bundle");
    }

    function testRejectsModifiedProof() public {
        string memory proofJson = vm.readFile(PROOF_PATH);
        string memory preprocessJson = vm.readFile(PREPROCESS_PATH);
        string memory instanceJson = vm.readFile(INSTANCE_PATH);
        string memory setupParamsJson = vm.readFile(SETUP_PARAMS_PATH);

        uint128[] memory proofPart1 = _toUint128Array(proofJson.readUintArray(".proof_entries_part1"));
        uint256[] memory proofPart2 = proofJson.readUintArray(".proof_entries_part2");
        uint128[] memory preprocessPart1 =
            _toUint128Array(preprocessJson.readUintArray(".preprocess_entries_part1"));
        uint256[] memory preprocessPart2 = preprocessJson.readUintArray(".preprocess_entries_part2");
        uint256[] memory publicInputs = _concatInstance(instanceJson);
        uint256 smax = abi.decode(vm.parseJson(setupParamsJson, ".s_max"), (uint256));

        proofPart2[0] += 1;

        vm.expectRevert();
        verifier.verify(proofPart1, proofPart2, preprocessPart1, preprocessPart2, publicInputs, smax);
    }

    function _concatInstance(string memory instanceJson) internal pure returns (uint256[] memory combined) {
        uint256[] memory user = instanceJson.readUintArray(".a_pub_user");
        uint256[] memory blockInputs = instanceJson.readUintArray(".a_pub_block");
        uint256[] memory functionInputs = instanceJson.readUintArray(".a_pub_function");

        combined = new uint256[](user.length + blockInputs.length + functionInputs.length);

        uint256 cursor = 0;
        cursor = _copyInto(combined, cursor, user);
        cursor = _copyInto(combined, cursor, blockInputs);
        _copyInto(combined, cursor, functionInputs);
    }

    function _copyInto(uint256[] memory dest, uint256 cursor, uint256[] memory src)
        internal
        pure
        returns (uint256 nextCursor)
    {
        for (uint256 index = 0; index < src.length; index += 1) {
            dest[cursor + index] = src[index];
        }
        return cursor + src.length;
    }

    function _toUint128Array(uint256[] memory input) internal pure returns (uint128[] memory output) {
        output = new uint128[](input.length);
        for (uint256 index = 0; index < input.length; index += 1) {
            output[index] = uint128(input[index]);
        }
    }
}
