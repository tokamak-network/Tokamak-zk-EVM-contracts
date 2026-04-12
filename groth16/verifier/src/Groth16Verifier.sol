// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x000000000000000000000000000000000eb023e0e9036b540983c47c6546b9b4;
    uint256 constant alphax_PART2 = 0xb626205581f49c3ba56b6f370da1cca07ead7f50ad709d40b131dda60d792fbd;
    uint256 constant alphay_PART1 = 0x00000000000000000000000000000000157e48eaf2b1e146770e94813f0f0ee6;
    uint256 constant alphay_PART2 = 0x8aeecf78b58b54bc418dae46929a222e624460e8760adfc77c2a069c963aff25;
    uint256 constant betax1_PART1 = 0x0000000000000000000000000000000008cc27787bbdc5fcaeb79826c6baad53;
    uint256 constant betax1_PART2 = 0x4620bdd847b4f47de3dee40b7166cb24a10b5554bee85b88478e3dba70d94743;
    uint256 constant betax2_PART1 = 0x00000000000000000000000000000000147e4f66386a47e9a09351bdb960a9db;
    uint256 constant betax2_PART2 = 0x806370f9e60afd1e9ae8d94c3665b160395398adf966b60976a168f4cf47543b;
    uint256 constant betay1_PART1 = 0x00000000000000000000000000000000109ed9d19d24191a6c35a126efd7de20;
    uint256 constant betay1_PART2 = 0x262e53495e7b2cb6f267d955c5c9782de160e9674ee875d2cc3c2a7f6285a46c;
    uint256 constant betay2_PART1 = 0x0000000000000000000000000000000009debbba6e2375e69144b9efeb6b097a;
    uint256 constant betay2_PART2 = 0xcebc6dd7703603bd2ee65d613cd4d04a07b49f153a55b6c7917575e0a64d6380;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x0000000000000000000000000000000001f64adfa9abbaebbaee4b3deb8ed0b3;
    uint256 constant deltax2_PART2 = 0xeccd7f3932c091046a196b4016ee2972868b349f20dd03927b66cd2eb8d48b51;
    uint256 constant deltax1_PART1 = 0x0000000000000000000000000000000011db43fc1c6d6f9d0967531268e67cf2;
    uint256 constant deltax1_PART2 = 0xac49eb3936840a413248294be460a2657c5e3986078521e426d31e53e9d0024b;
    uint256 constant deltay2_PART1 = 0x000000000000000000000000000000000d632504f5e87cd2bcb55613b7e1a010;
    uint256 constant deltay2_PART2 = 0xbeec959f15d11f5d1feabe86a0b2f4563d7bb7de39ea33a7196cc4827848dc0d;
    uint256 constant deltay1_PART1 = 0x0000000000000000000000000000000009529d9483021c360b37e61e36b41b00;
    uint256 constant deltay1_PART2 = 0x98a5f26d72ff8f3753559d5bf8a328971e2ddb5d319f86911e05f7460914bb4f;

    uint256 constant IC0x_PART1 = 0x000000000000000000000000000000000e80f77258ef75829572007988752ac7;
    uint256 constant IC0x_PART2 = 0x4118eda16bdf12c0769a3def490b3c493eff07d1247ec388c5157a5caead7ab0;
    uint256 constant IC0y_PART1 = 0x00000000000000000000000000000000195468312b594cb4f4cdb89960abe7ba;
    uint256 constant IC0y_PART2 = 0x55cd8dfec595a9a371410a6e921145d81162bc69a7ff31326e9b1267add8fc1f;

    uint256 constant IC1x_PART1 = 0x0000000000000000000000000000000015a0af7f8f6dfdcec3e7d2025086a84c;
    uint256 constant IC1x_PART2 = 0x535dce0b08d382feb7778857e79c6939ab3b22e8c6893f65c28677a9c3da5ac6;
    uint256 constant IC1y_PART1 = 0x0000000000000000000000000000000005400b7b72ddf2999b7a5d656c052f07;
    uint256 constant IC1y_PART2 = 0xab29bd06b08b52871766d22caf7635159815b0c499a6c5fa30c36f30cdb774cf;

    uint256 constant IC2x_PART1 = 0x0000000000000000000000000000000004e6ebac7194935f8d35d855471a6ce9;
    uint256 constant IC2x_PART2 = 0x13bfe2ab30e05ffdb4ceed6ff1fb9331fce0a72c05c076bf86b6dfe63617d59d;
    uint256 constant IC2y_PART1 = 0x00000000000000000000000000000000135e16f90dba0aba676e919871d55d90;
    uint256 constant IC2y_PART2 = 0x00c3fafa78b67bc30ca9f710f39555c87a9d9b253ebc801e62df485f1c740c5c;

    uint256 constant IC3x_PART1 = 0x0000000000000000000000000000000012a1d6b8b441a50ecc8c2e575550d097;
    uint256 constant IC3x_PART2 = 0xfd6a0ec130765e7e270b236cb116136a42bd82d12c46f448ea010f59aeb5499a;
    uint256 constant IC3y_PART1 = 0x00000000000000000000000000000000078de5b5401a81881e320280c0d861eb;
    uint256 constant IC3y_PART2 = 0xd24e06ee704d194557d92321b73abe905c3adb799d00456d83758f51e0ecef35;

    uint256 constant IC4x_PART1 = 0x000000000000000000000000000000000071483b26665817b4409ac9902a6b61;
    uint256 constant IC4x_PART2 = 0xdbb0d7f054fc4d6ea37f42ee4516483a05e076fb1f2f5995f67f012fd3d8745e;
    uint256 constant IC4y_PART1 = 0x0000000000000000000000000000000000d3f02424d03dfba33aa212b6775ccf;
    uint256 constant IC4y_PART2 = 0x14be1bcbb4ee2b5e51de66e1c4be1c76b5d386db691d74fb663a88286f07eb0a;

    uint256 constant IC5x_PART1 = 0x00000000000000000000000000000000141739bd35338cc71032d6aa8e44cd6e;
    uint256 constant IC5x_PART2 = 0x01dcce056eb81f19ed2878a17d824afd43666fe98222916786e963760e6a0608;
    uint256 constant IC5y_PART1 = 0x0000000000000000000000000000000010968e504fc0c1ea23c343467295b61a;
    uint256 constant IC5y_PART2 = 0xb3de69fe14e1719326bf64ebb1d5be0561ab9daa95d79b1eff696b56c7661fb1;

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
