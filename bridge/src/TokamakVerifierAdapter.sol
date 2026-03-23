// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {BridgeAdminManager} from "./BridgeAdminManager.sol";
import {BridgeStructs} from "./BridgeStructs.sol";
import {ITokamakVerifier as IBridgeTokamakVerifier} from "./interfaces/ITokamakVerifier.sol";
import {ITokamakVerifier as IRootTokamakVerifier} from "tokamak-zkp/ITokamakVerifier.sol";

contract TokamakVerifierAdapter is IBridgeTokamakVerifier {
    error TokamakPublicInputLengthMismatch(uint256 actualLength, uint256 expectedLength);
    error FunctionInstanceHashMismatch(bytes32 expectedHash, bytes32 actualHash);
    error FunctionPreprocessHashMismatch(bytes32 expectedHash, bytes32 actualHash);

    IRootTokamakVerifier public immutable rootVerifier;
    BridgeAdminManager public immutable adminManager;

    constructor(IRootTokamakVerifier rootVerifier_, BridgeAdminManager adminManager_) {
        rootVerifier = rootVerifier_;
        adminManager = adminManager_;
    }

    function verifyTokamakProof(
        bytes calldata proof,
        BridgeStructs.TokamakTransactionInstance calldata,
        bytes32,
        bytes32 functionInstanceHash,
        bytes32 functionPreprocessHash
    ) external override returns (bool) {
        BridgeStructs.TokamakProofPayload memory payload = abi.decode(proof, (BridgeStructs.TokamakProofPayload));

        uint256 expectedPublicInputs = adminManager.nTokamakPublicInputs();
        if (expectedPublicInputs != 0 && payload.publicInputs.length != expectedPublicInputs) {
            revert TokamakPublicInputLengthMismatch(payload.publicInputs.length, expectedPublicInputs);
        }

        if (functionInstanceHash != bytes32(0)) {
            bytes32 actualInstanceHash =
                computePointEncodingHash(payload.functionInstancePart1, payload.functionInstancePart2);
            if (actualInstanceHash != functionInstanceHash) {
                revert FunctionInstanceHashMismatch(functionInstanceHash, actualInstanceHash);
            }
        }

        if (functionPreprocessHash != bytes32(0)) {
            bytes32 actualPreprocessHash =
                computePointEncodingHash(payload.functionPreprocessPart1, payload.functionPreprocessPart2);
            if (actualPreprocessHash != functionPreprocessHash) {
                revert FunctionPreprocessHashMismatch(functionPreprocessHash, actualPreprocessHash);
            }
        }

        return rootVerifier.verify(
            payload.proofPart1,
            payload.proofPart2,
            payload.functionPreprocessPart1,
            payload.functionPreprocessPart2,
            payload.publicInputs,
            payload.smax
        );
    }

    function computePointEncodingHash(uint128[] memory part1, uint256[] memory part2)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(part1, part2));
    }
}
