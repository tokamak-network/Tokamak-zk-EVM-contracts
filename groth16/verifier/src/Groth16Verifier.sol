// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x00000000000000000000000000000000177f6192f65f27b7abb093efdd7aa9f1;
    uint256 constant alphax_PART2 = 0x5e3f28e810540817ee6608fe2f313dc2f960ae35c8b36e006925bd989be6bf67;
    uint256 constant alphay_PART1 = 0x0000000000000000000000000000000018ddc47b14ee7c951a5ca899573bd68d;
    uint256 constant alphay_PART2 = 0x471010e88a6a1be22029828e6535811b5478d5ba7a543a059ce55a71f81a02ff;
    uint256 constant betax1_PART1 = 0x00000000000000000000000000000000095c9829d81cf7de32621a7ee178c1d0;
    uint256 constant betax1_PART2 = 0x7dc437b63befc8686a70c0aa39d0031467f67154cae6289e3d981e04e96b94c7;
    uint256 constant betax2_PART1 = 0x0000000000000000000000000000000003dcb4d6b287bb889caa2e12160c1d1b;
    uint256 constant betax2_PART2 = 0x56531f2a6be8e2d7d24a3b5ef4c89d56e6941c9add1105dd841d7b6fcc10cd9a;
    uint256 constant betay1_PART1 = 0x000000000000000000000000000000000a1540cd116e4ca026c77a40557625b9;
    uint256 constant betay1_PART2 = 0x8547789b6e24f582cd1f770704661f5ffcb5c2bfd56dc3d5b278d015041104ca;
    uint256 constant betay2_PART1 = 0x000000000000000000000000000000000406472595ca2b525bf92def4975817c;
    uint256 constant betay2_PART2 = 0x3a4806953a7b205f7e0e9b2516fa6518c6583ee3949c248784a508940cf75b5d;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x000000000000000000000000000000000ee46caa5bc4da2753b1bf278a8ca42b;
    uint256 constant deltax2_PART2 = 0x1d811e752b5757593d4bd788661d64ce488900b935ff574b9209187601fdd1a3;
    uint256 constant deltax1_PART1 = 0x000000000000000000000000000000000f0ba02250948409863c77fff3155a69;
    uint256 constant deltax1_PART2 = 0xbffb5c2616788b605ba1f7c82990d75edee841c53c036f0f8231e3822991ebec;
    uint256 constant deltay2_PART1 = 0x000000000000000000000000000000001948bda67137f33be3b11811da533095;
    uint256 constant deltay2_PART2 = 0xa0fac5ae144f22c110a00177c5d2c440dd1b8787eaa07d400a7b547f771959e3;
    uint256 constant deltay1_PART1 = 0x000000000000000000000000000000000ca3b56894c12dd28d0317d21457a23b;
    uint256 constant deltay1_PART2 = 0x6c479f2dc240f655c23ee783f85c703d59b0a49f17a4a6f2dd310df85f470774;

    uint256 constant IC0x_PART1 = 0x0000000000000000000000000000000016865101bd3776c95d9f66785437518e;
    uint256 constant IC0x_PART2 = 0xd1ccd26d08a43f30f7bb13b9132a2235f3e97f9fb3f02c749da6b54b8c1c0b5d;
    uint256 constant IC0y_PART1 = 0x000000000000000000000000000000000e1c6f955291621f6a53228eda51ea38;
    uint256 constant IC0y_PART2 = 0x812e0467a8e593c79c04080884a0ec644e4a88c3064a99a615847d140b3fd8c8;

    uint256 constant IC1x_PART1 = 0x000000000000000000000000000000000bee4e2c21b22a06cbee622831029b9e;
    uint256 constant IC1x_PART2 = 0x487a7851d2cbab87a7eb7ef119f42f81205dff88de3da2d027f7e94371754476;
    uint256 constant IC1y_PART1 = 0x0000000000000000000000000000000005c697a393dc8ffd174f9c5c0a2daf0d;
    uint256 constant IC1y_PART2 = 0xc4c3efb7f67cf58d49e50a77f37826aa8415e0ed20e4a8264b9b27871a5f21a9;

    uint256 constant IC2x_PART1 = 0x0000000000000000000000000000000006d4aa2bdffa042212d36c14e09f3604;
    uint256 constant IC2x_PART2 = 0x20cf9feef48dee98e91cc92e47886bcbbe2c22bc05bf23d03365dde5a15b48c9;
    uint256 constant IC2y_PART1 = 0x0000000000000000000000000000000015c6942a858c90e9dd148ba402c5a274;
    uint256 constant IC2y_PART2 = 0xa8a296c9194656d5dbe3c3b60502f4fd5691af1aa1e5a8d7c046aacbf1ee0bef;

    uint256 constant IC3x_PART1 = 0x00000000000000000000000000000000092e006768118a20f18268e9df59ee93;
    uint256 constant IC3x_PART2 = 0xa0032d183f109b14559bd1f9d3e052a78e28152f0b572e4632b81cf67b0f6695;
    uint256 constant IC3y_PART1 = 0x00000000000000000000000000000000151d02a986f3b9f3756c0fda7d63322d;
    uint256 constant IC3y_PART2 = 0x8a9c80712167c33bb3fdc852e2a4a7ef7eedeebd9d56b191014cd71a17ef8651;

    uint256 constant IC4x_PART1 = 0x0000000000000000000000000000000013b8296ff23966b68d72487d00c02a1b;
    uint256 constant IC4x_PART2 = 0x0235c3586a65d4c2806e812013b08b8b9dc48ed2800603710d8ed1f3b93a8455;
    uint256 constant IC4y_PART1 = 0x000000000000000000000000000000000421d291c0435253e1ef416468b3a7e8;
    uint256 constant IC4y_PART2 = 0x3e5f5aa6a52e82a4b07cdef82d063f1ac41bcc1ee0dcc1d619c0a3326a42c446;

    uint256 constant IC5x_PART1 = 0x0000000000000000000000000000000001b7c8d733ee804295abe4af8b544292;
    uint256 constant IC5x_PART2 = 0x7eaf6eade8488dac069ab40ee5d23679737b3c80d61b17ccda303fe83f2f9f8a;
    uint256 constant IC5y_PART1 = 0x000000000000000000000000000000001681ccff7e357b2951ccd1b675f1630f;
    uint256 constant IC5y_PART2 = 0x3d843905a9a1bbb928a01a2320f09cba3e6ab7aec466deda5f8a284080ad7c4e;

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
