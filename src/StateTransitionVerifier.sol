// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Verifier} from "./Verifier.sol";
import {IStateTransitionVerifier} from "./interface/IStateTransitionVerifier.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";

contract StateTransitionVerifier is IStateTransitionVerifier, Ownable {

    Verifier verifier;
    bytes32 public currentStateRoot;


    constructor(address _verifier) Ownable(msg.sender) {
        if(_verifier == address(0)) {
            revert Invalid__Verifier();
        }
        verifier = Verifier(_verifier);
        currentStateRoot = bytes32(0);

    }

    function verifyAndCommitStateUpdate(StateUpdate calldata update) external returns(bool) {
        // verify signatures
        

        // oldStateRoot matches the stored oldStateRoot
        if(update.oldStateRoot != currentStateRoot) {
            revert Invalid__OldStateRoot(update.oldStateRoot);
        }

        // proof verification
        if(!verifier.verify(update.proofPart1, update.proofPart2, update.publicInputs)) {
            revert Invalid__SnarkProof();
        }

        // store new state root
        currentStateRoot = update.newStateRoot;

        return true;
    }   

    function updateVerifier(address _verifier) external onlyOwner {
        if(_verifier == address(0)) {
            revert Invalid__Verifier();
        }
        verifier = Verifier(_verifier);
    }

}