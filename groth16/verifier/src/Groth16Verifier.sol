// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x0000000000000000000000000000000011529cfdd7beeae30ad2373eb1fc793a;
    uint256 constant alphax_PART2 = 0x7efdc1e80b1a1022d740cda3bf8d8fe68b0f24e484f06035bcbebc157a3d2130;
    uint256 constant alphay_PART1 = 0x00000000000000000000000000000000159f4989ccc6d8687f45fb6ce042c0e4;
    uint256 constant alphay_PART2 = 0xac8d8e7b72898507295dbde622a763e5919935958d923f54c0ad08623b9596da;
    uint256 constant betax1_PART1 = 0x000000000000000000000000000000000d6d28b057430a181259eb7d6225a01a;
    uint256 constant betax1_PART2 = 0x880b10f31654cc08c85e72912da3533fac50a1bd7eed4773af61795ef2a28fa2;
    uint256 constant betax2_PART1 = 0x000000000000000000000000000000000a054d2b80ff54d8956db708f931a1ae;
    uint256 constant betax2_PART2 = 0xac2f7d0d139cbd49bf9f408339026ac5edb2917009c4b52da925c29cc84a54c2;
    uint256 constant betay1_PART1 = 0x0000000000000000000000000000000007be280cde90c902c43e2a8c0e077d08;
    uint256 constant betay1_PART2 = 0x8339eb34ac933842ad8720034033d8b92a42f684fc042a5d355c1d40afa537c7;
    uint256 constant betay2_PART1 = 0x000000000000000000000000000000000d12eeb69869248e7df7210ff4ad7846;
    uint256 constant betay2_PART2 = 0x6d8f8091f51fc0707a9285396b7dd01dd2892fc6ce01871f664a72fce8717923;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x00000000000000000000000000000000008478c0b3a9b8a8330cc58d8c02f1a9;
    uint256 constant deltax2_PART2 = 0x2b39cd672391868485fcf33d584ff94efd040484908297a9e92cd9d8029be716;
    uint256 constant deltax1_PART1 = 0x000000000000000000000000000000001802245d0aab8405878ccad72e823d53;
    uint256 constant deltax1_PART2 = 0xbe744e4e1b60ff5b8c3f6e2004717e98b966390f46614e4e465e18cdeeddc213;
    uint256 constant deltay2_PART1 = 0x0000000000000000000000000000000018134c378fcec5e0ca54643f2d74ba59;
    uint256 constant deltay2_PART2 = 0x8f1699f1a06cbca0fe1907d877fcb2eda6082bc579d62dbd98832e71af580bee;
    uint256 constant deltay1_PART1 = 0x0000000000000000000000000000000008d0b63f2f69b95b471015101e66d86a;
    uint256 constant deltay1_PART2 = 0x1d8aa94d55d679c6226ef27dabb2797af60af8bf18486e39d32cf0fc1cdb6711;

    uint256 constant IC0x_PART1 = 0x0000000000000000000000000000000019ab7e37d6cbc5de5259d2d14eb81e50;
    uint256 constant IC0x_PART2 = 0xc611e8cc2664e2485207a073492fe1c9a5ab4610dd1e37dec269c4c4eb02054d;
    uint256 constant IC0y_PART1 = 0x0000000000000000000000000000000018bead69015a17541396ac565c24c9cb;
    uint256 constant IC0y_PART2 = 0xda3f4f87e327a68fc3b865b878cb012e938a1413699fa5142a4c9efda3546765;

    uint256 constant IC1x_PART1 = 0x0000000000000000000000000000000003eb9df8f9a08e868d82ba49159450b7;
    uint256 constant IC1x_PART2 = 0x8c1b600b83151c5b83934856576422632368cbd0af393bc3437a758fc48ba02f;
    uint256 constant IC1y_PART1 = 0x0000000000000000000000000000000003dc7ff4727a1c14e7ac34f2ebaa367d;
    uint256 constant IC1y_PART2 = 0x06fc545102ed847f4c760e877144e389ec22486a192289a560609bfd85c73618;

    uint256 constant IC2x_PART1 = 0x0000000000000000000000000000000015bf47ddbf046b84cc4085c8441481d2;
    uint256 constant IC2x_PART2 = 0x06d502f31acad47b619c9df99c0c55b280c45134f0687486d016a30fdd2dc5fd;
    uint256 constant IC2y_PART1 = 0x0000000000000000000000000000000005bb1db1b13a1d2d98011e7759d6a864;
    uint256 constant IC2y_PART2 = 0x6479eb7662cd96447beffcc9083d05ddb154ac16bcdaf8fdb7336a92d3a99087;

    uint256 constant IC3x_PART1 = 0x000000000000000000000000000000000a4208ce6371a55bf8ed60615888bbfd;
    uint256 constant IC3x_PART2 = 0x698678614549839913d59184a8e81b723c3f82318b73d14cd07be9aacfe35397;
    uint256 constant IC3y_PART1 = 0x0000000000000000000000000000000016ee9194aa7c0a86c5347baa02f143a6;
    uint256 constant IC3y_PART2 = 0x6a0f2ddbd2fe141b6c5cdd2582cc95d621a67b003c96d9d0b58ad5cd3872c201;

    uint256 constant IC4x_PART1 = 0x00000000000000000000000000000000086ba3aacd19303669fd3f6b0ebbb31c;
    uint256 constant IC4x_PART2 = 0x044ea8f014f4167af81074aa74c482f2d71a3c31f0c0d1d88fc5701db6130923;
    uint256 constant IC4y_PART1 = 0x00000000000000000000000000000000072b46a5e9f80498b4dc5f9455f5f3fa;
    uint256 constant IC4y_PART2 = 0xb7a37652170b6b99b4b27a7c5d16ed5d18cad65cd550decc4560b2a8206303cd;

    uint256 constant IC5x_PART1 = 0x000000000000000000000000000000000e54c7345ce2f0a081a045c786d57f0c;
    uint256 constant IC5x_PART2 = 0xfa9290cb2e9bc699096228c53da077093de8e94600fa2d2124e6731b7dc258d4;
    uint256 constant IC5y_PART1 = 0x000000000000000000000000000000001406a58228f66daa77934827b0ba74b5;
    uint256 constant IC5y_PART2 = 0xb64e445ef04837296df6d9e7a93cc69a18eb8e4c2ade9db847b55db6ea2b0e23;

    uint16 constant pVk = 0;
    uint16 constant pPairing = 128;
    uint16 constant pLastMem = 1664;

    function verifyProof(
        uint256[4] calldata _pA,
        uint256[8] calldata _pB,
        uint256[4] calldata _pC,
        uint256[5] calldata _pubSignals
    ) external view returns (bool) {
        assembly {
            function checkField(v) {
                if iszero(lt(v, R_MOD)) {
                    mstore(0, 0)
                    return(0, 0x20)
                }
            }

            function g1_mulAccC(pR, x0, x1, y0, y1, s) {
                let success
                let mIn := mload(0x40)
                mstore(mIn, x0)
                mstore(add(mIn, 32), x1)
                mstore(add(mIn, 64), y0)
                mstore(add(mIn, 96), y1)
                mstore(add(mIn, 128), s)

                success := staticcall(sub(gas(), 2000), 0x0c, mIn, 160, mIn, 128)
                if iszero(success) {
                    mstore(0, 0)
                    return(0, 0x20)
                }

                mstore(add(mIn, 128), mload(pR))
                mstore(add(mIn, 160), mload(add(pR, 32)))
                mstore(add(mIn, 192), mload(add(pR, 64)))
                mstore(add(mIn, 224), mload(add(pR, 96)))

                success := staticcall(sub(gas(), 2000), 0x0b, mIn, 256, pR, 128)
                if iszero(success) {
                    mstore(0, 0)
                    return(0, 0x20)
                }
            }

            function checkPairing(pA, pB, pC, pubSignals, pMem) -> isOk {
                let _pPairing := add(pMem, pPairing)
                let _pVk := add(pMem, pVk)

                mstore(_pVk, IC0x_PART1)
                mstore(add(_pVk, 32), IC0x_PART2)
                mstore(add(_pVk, 64), IC0y_PART1)
                mstore(add(_pVk, 96), IC0y_PART2)

                g1_mulAccC(_pVk, IC1x_PART1, IC1x_PART2, IC1y_PART1, IC1y_PART2, calldataload(add(pubSignals, 0)))

                g1_mulAccC(_pVk, IC2x_PART1, IC2x_PART2, IC2y_PART1, IC2y_PART2, calldataload(add(pubSignals, 32)))

                g1_mulAccC(_pVk, IC3x_PART1, IC3x_PART2, IC3y_PART1, IC3y_PART2, calldataload(add(pubSignals, 64)))

                g1_mulAccC(_pVk, IC4x_PART1, IC4x_PART2, IC4y_PART1, IC4y_PART2, calldataload(add(pubSignals, 96)))

                g1_mulAccC(_pVk, IC5x_PART1, IC5x_PART2, IC5y_PART1, IC5y_PART2, calldataload(add(pubSignals, 128)))

                mstore(_pPairing, calldataload(pA))
                mstore(add(_pPairing, 32), calldataload(add(pA, 32)))

                let y_high := calldataload(add(pA, 64))
                let y_low := calldataload(add(pA, 96))
                let neg_y_high
                let neg_y_low
                let borrow := 0

                switch lt(Q_MOD_PART2, y_low)
                case 1 {
                    neg_y_low := sub(Q_MOD_PART2, y_low)
                    neg_y_low := add(neg_y_low, not(0))
                    neg_y_low := add(neg_y_low, 1)
                    borrow := 1
                }
                default {
                    neg_y_low := sub(Q_MOD_PART2, y_low)
                }

                neg_y_high := sub(sub(Q_MOD_PART1, y_high), borrow)
                mstore(add(_pPairing, 64), neg_y_high)
                mstore(add(_pPairing, 96), neg_y_low)

                mstore(add(_pPairing, 128), calldataload(add(pB, 64)))
                mstore(add(_pPairing, 160), calldataload(add(pB, 96)))
                mstore(add(_pPairing, 192), calldataload(pB))
                mstore(add(_pPairing, 224), calldataload(add(pB, 32)))
                mstore(add(_pPairing, 256), calldataload(add(pB, 192)))
                mstore(add(_pPairing, 288), calldataload(add(pB, 224)))
                mstore(add(_pPairing, 320), calldataload(add(pB, 128)))
                mstore(add(_pPairing, 352), calldataload(add(pB, 160)))

                mstore(add(_pPairing, 384), alphax_PART1)
                mstore(add(_pPairing, 416), alphax_PART2)
                mstore(add(_pPairing, 448), alphay_PART1)
                mstore(add(_pPairing, 480), alphay_PART2)

                mstore(add(_pPairing, 512), betax2_PART1)
                mstore(add(_pPairing, 544), betax2_PART2)
                mstore(add(_pPairing, 576), betax1_PART1)
                mstore(add(_pPairing, 608), betax1_PART2)
                mstore(add(_pPairing, 640), betay2_PART1)
                mstore(add(_pPairing, 672), betay2_PART2)
                mstore(add(_pPairing, 704), betay1_PART1)
                mstore(add(_pPairing, 736), betay1_PART2)

                mstore(add(_pPairing, 768), mload(add(pMem, pVk)))
                mstore(add(_pPairing, 800), mload(add(pMem, add(pVk, 32))))
                mstore(add(_pPairing, 832), mload(add(pMem, add(pVk, 64))))
                mstore(add(_pPairing, 864), mload(add(pMem, add(pVk, 96))))

                mstore(add(_pPairing, 896), gammax2_PART1)
                mstore(add(_pPairing, 928), gammax2_PART2)
                mstore(add(_pPairing, 960), gammax1_PART1)
                mstore(add(_pPairing, 992), gammax1_PART2)
                mstore(add(_pPairing, 1024), gammay2_PART1)
                mstore(add(_pPairing, 1056), gammay2_PART2)
                mstore(add(_pPairing, 1088), gammay1_PART1)
                mstore(add(_pPairing, 1120), gammay1_PART2)

                mstore(add(_pPairing, 1152), calldataload(pC))
                mstore(add(_pPairing, 1184), calldataload(add(pC, 32)))
                mstore(add(_pPairing, 1216), calldataload(add(pC, 64)))
                mstore(add(_pPairing, 1248), calldataload(add(pC, 96)))

                mstore(add(_pPairing, 1280), deltax2_PART1)
                mstore(add(_pPairing, 1312), deltax2_PART2)
                mstore(add(_pPairing, 1344), deltax1_PART1)
                mstore(add(_pPairing, 1376), deltax1_PART2)
                mstore(add(_pPairing, 1408), deltay2_PART1)
                mstore(add(_pPairing, 1440), deltay2_PART2)
                mstore(add(_pPairing, 1472), deltay1_PART1)
                mstore(add(_pPairing, 1504), deltay1_PART2)

                let success := staticcall(sub(gas(), 2000), 0x0f, _pPairing, 1536, _pPairing, 0x20)
                isOk := and(success, mload(_pPairing))
            }

            let pMem := mload(0x40)
            mstore(0x40, add(pMem, pLastMem))

            checkField(calldataload(add(_pubSignals, 0)))

            checkField(calldataload(add(_pubSignals, 32)))

            checkField(calldataload(add(_pubSignals, 64)))

            checkField(calldataload(add(_pubSignals, 96)))

            checkField(calldataload(add(_pubSignals, 128)))

            let isValid := checkPairing(_pA, _pB, _pC, _pubSignals, pMem)
            mstore(0, isValid)
            return(0, 0x20)
        }
    }
}
