// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {TokamakVerifier} from "../../src/verifier/TokamakVerifier.sol";

import "forge-std/console.sol";

contract testTokamakVerifier is Test {
    using stdJson for string;

    TokamakVerifier verifier;

    uint128[] public serializedProofPart1;
    uint256[] public serializedProofPart2;
    uint128[] public preprocessedPart1;
    uint256[] public preprocessedPart2;
    uint256[] public publicInputs;
    uint256 public smax;

    function setUp() public virtual {
        verifier = new TokamakVerifier();

        string memory inputDir = string.concat(vm.projectRoot(), "/test/verifier/input/");
        string memory proofPath = string.concat(inputDir, "proof.json");
        string memory preprocessPath = string.concat(inputDir, "preprocess.json");
        string memory instancePath = string.concat(inputDir, "instance.json");

        string memory proofJson = vm.readFile(proofPath);
        string memory preprocessJson = vm.readFile(preprocessPath);
        string memory instanceJson = vm.readFile(instancePath);

        serializedProofPart1 = _decodeUint128Array(proofJson, ".proof_entries_part1");
        serializedProofPart2 = _decodeUint256Array(proofJson, ".proof_entries_part2");
        preprocessedPart1 = _decodeUint128Array(preprocessJson, ".preprocess_entries_part1");
        preprocessedPart2 = _decodeUint256Array(preprocessJson, ".preprocess_entries_part2");
        publicInputs = _decodePublicInputs(instanceJson);

        smax = 256;
    }

    function _decodeUint256Array(string memory json, string memory key) internal returns (uint256[] memory values) {
        string[] memory rawValues = json.readStringArray(key);
        values = new uint256[](rawValues.length);

        for (uint256 i = 0; i < rawValues.length; i++) {
            values[i] = vm.parseUint(rawValues[i]);
        }
    }

    function _decodeUint128Array(string memory json, string memory key) internal returns (uint128[] memory values) {
        uint256[] memory parsedValues = _decodeUint256Array(json, key);
        values = new uint128[](parsedValues.length);

        for (uint256 i = 0; i < parsedValues.length; i++) {
            require(parsedValues[i] <= type(uint128).max, "input value exceeds uint128");
            values[i] = uint128(parsedValues[i]);
        }
    }

    function _decodePublicInputs(string memory instanceJson) internal returns (uint256[] memory values) {
        uint256[] memory user = _decodeUint256Array(instanceJson, ".a_pub_user");
        uint256[] memory blockInputs = _decodeUint256Array(instanceJson, ".a_pub_block");
        uint256[] memory functionInputs = _decodeUint256Array(instanceJson, ".a_pub_function");

        values = new uint256[](user.length + blockInputs.length + functionInputs.length);

        uint256 index = 0;
        for (uint256 i = 0; i < user.length; i++) {
            values[index] = user[i];
            index++;
        }

        for (uint256 i = 0; i < blockInputs.length; i++) {
            values[index] = blockInputs[i];
            index++;
        }

        for (uint256 i = 0; i < functionInputs.length; i++) {
            values[index] = functionInputs[i];
            index++;
        }
    }

    function testVerifier() public {
        uint256 gasBefore = gasleft();

        (bool success, bytes memory returnData) = address(verifier).call(
            abi.encodeWithSignature(
                "verify(uint128[],uint256[],uint128[],uint256[],uint256[],uint256)",
                serializedProofPart1,
                serializedProofPart2,
                preprocessedPart1,
                preprocessedPart2,
                publicInputs,
                smax
            )
        );

        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        console.log("Gas used:", gasUsed);
        assert(success == true);
        returnData;
    }

    function testWrongProof_shouldRevert() public {
        serializedProofPart1[4] = 0x0cf3e4f4ddb78781cd5740f3f2a1a3db;
        serializedProofPart1[5] = 0x0f4b46798d566e5f6653c4fe4df20e83;

        serializedProofPart2[4] = 0xd3e45812526acc1d689ce05e186d3a8b9e921ad3a4701013336f3f00c654c908;
        serializedProofPart2[5] = 0x76983b4b6af2d6a17be232aeeb9fdd374990fdcbd9b1a4654bfbbc5f4bba7e13;
        vm.expectRevert(bytes("finalPairing: pairing failure"));
        verifier.verify(
            serializedProofPart1, serializedProofPart2, preprocessedPart1, preprocessedPart2, publicInputs, smax
        );
    }

    function testEmptyPublicInput_shouldRevert() public {
        uint256[] memory newPublicInputs;
        vm.expectRevert(bytes("finalPairing: pairing failure"));
        verifier.verify(
            serializedProofPart1, serializedProofPart2, preprocessedPart1, preprocessedPart2, newPublicInputs, smax
        );
    }

    function testWrongSizeProof_shouldRevert() public {
        serializedProofPart1.push(0x0d8838cc826baa7ccd8cfe0692e8a13d);
        serializedProofPart1.push(0x103aeb959c53fdd5f13b70a350363881);
        serializedProofPart2.push(0xbbae56c781b300594dac0753e75154a00b83cc4e6849ef3f07bb56610a02c828);
        serializedProofPart2.push(0xf3447285889202e7e24cd08a058a758a76ee4c8440131be202ad8bc0cc91ee70);

        vm.expectRevert(bytes("loadProof: Proof is invalid"));
        verifier.verify(
            serializedProofPart1, serializedProofPart2, preprocessedPart1, preprocessedPart2, publicInputs, smax
        );
    }

    function testEmptyProof_shouldRevert() public {
        uint128[] memory newserializedProofPart1;
        uint256[] memory newserializedProofPart2;

        vm.expectRevert(bytes("loadProof: Proof is invalid"));
        verifier.verify(
            newserializedProofPart1, newserializedProofPart2, preprocessedPart1, preprocessedPart2, publicInputs, smax
        );
    }
}
