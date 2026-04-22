// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x00000000000000000000000000000000082d77dd11bba87ecd9b9446d369a1ad;
    uint256 constant alphax_PART2 = 0x1b5b3c5af903ba700dc64f08db3260009c19c750e7ba5ff15a37df758b6aebc8;
    uint256 constant alphay_PART1 = 0x000000000000000000000000000000001210092120a8ebf2a4e1c998887ae494;
    uint256 constant alphay_PART2 = 0x0090fb0841cf4db6d1b4e3f855aef0d8d4a4c7a8f25af5808834bec0875f6425;
    uint256 constant betax1_PART1 = 0x00000000000000000000000000000000185d7f392a8f99e9c0f91c7355ea6328;
    uint256 constant betax1_PART2 = 0xf6b37cf7aefb61c575a17a408f6d50dfeb4a12d841a1f7770c4d927908b17056;
    uint256 constant betax2_PART1 = 0x0000000000000000000000000000000002ad10f47b75de8ae4b1ee8275b5dde8;
    uint256 constant betax2_PART2 = 0x6aacb8410fd75cac6056c8c33f29ef2426a3ad953648931fd04cf0782912cf1d;
    uint256 constant betay1_PART1 = 0x0000000000000000000000000000000011855bb893ddabace10c59a78639e8d6;
    uint256 constant betay1_PART2 = 0x495d4ba7e9168c0513317777caa2a3ebb3954c3448c30f7ebad80c2bc3d7c318;
    uint256 constant betay2_PART1 = 0x0000000000000000000000000000000016df38b537e70b84918476883c06abbc;
    uint256 constant betay2_PART2 = 0xb468b40d7f7162b63f93a05a20e056140c654482c4fb7d61815629fcbd5b4800;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x00000000000000000000000000000000132c7bf0165f95f5f9b87bd4eeb6a3bc;
    uint256 constant deltax2_PART2 = 0xb0f1585c663699d3dbb3db0698757d0639d9a5a506c665f062013c3dccb2397a;
    uint256 constant deltax1_PART1 = 0x0000000000000000000000000000000007e5ae223964a7c29bfe8595fd858553;
    uint256 constant deltax1_PART2 = 0xe559a05169f4edeeae49b546dbc0f9f37f45eaba04b4188e298adfa97f855d45;
    uint256 constant deltay2_PART1 = 0x00000000000000000000000000000000045debacc998bdb964b4be264116fdc8;
    uint256 constant deltay2_PART2 = 0x41386f40cc114085b1d28d3b831dc57d3bd54b95ed55fe1921ae752e7d5dbb6b;
    uint256 constant deltay1_PART1 = 0x000000000000000000000000000000000be92407781499e7fdcf9a3cab6e9173;
    uint256 constant deltay1_PART2 = 0x1b22d479a28eda0693fd262c3bec914e8635ad2090c40334c023b855e3cc3bd0;

    uint256 constant IC0x_PART1 = 0x00000000000000000000000000000000072cc75cbd06676b5a618f0b8742d6d6;
    uint256 constant IC0x_PART2 = 0x46edf073c12d3cea647c35c632b73faf5d8ea0f43d96f3bfaa692d85d6cba054;
    uint256 constant IC0y_PART1 = 0x0000000000000000000000000000000007a1204e36c2e9f7b75db16001577e88;
    uint256 constant IC0y_PART2 = 0x34dbfbcf7bf9ca16d50ef0939e2eea59bc23382c5955ef5d9911c40748728a72;

    uint256 constant IC1x_PART1 = 0x00000000000000000000000000000000130a612e8e55c3bd90d0497c2a6ed5b1;
    uint256 constant IC1x_PART2 = 0xc8085c24ebbef8a823be3e2e287b5d0c4e53b08e205c6dbab142781ebc4ef097;
    uint256 constant IC1y_PART1 = 0x00000000000000000000000000000000043f7f4e7583694ad1ce8f910b0db72a;
    uint256 constant IC1y_PART2 = 0x3f6de487e11dda87c21b6e86aae735b520ccd2b32fa9a64a5612af98abcd582a;

    uint256 constant IC2x_PART1 = 0x000000000000000000000000000000001973fad6174fa8a7178e42ff8110b022;
    uint256 constant IC2x_PART2 = 0x0bb44e287a9ae6e8e56c4c3ad9eb8681a03229647b4e9642d98778a133751de9;
    uint256 constant IC2y_PART1 = 0x0000000000000000000000000000000002cd85a2ff0cef8bc6b20fcd371c48fb;
    uint256 constant IC2y_PART2 = 0xe1c7c937fbe80019a2b3e6edaef1a3f04961961aa1fc92001606f0f0899422d1;

    uint256 constant IC3x_PART1 = 0x000000000000000000000000000000000c9f4b75860c27c9ed3138012d3c76ec;
    uint256 constant IC3x_PART2 = 0x5be4175faf9eb021cf948a43e2c00234d4bebad0cd4630331185ac5243c4d7a3;
    uint256 constant IC3y_PART1 = 0x0000000000000000000000000000000013fb11f92e56793fef6f8545a8d3ec51;
    uint256 constant IC3y_PART2 = 0x3f9fa54b5d17eec6acd8ac63082a6f764e0a7bf59d8a55c81ee34c648380739e;

    uint256 constant IC4x_PART1 = 0x00000000000000000000000000000000144362aabbd4d4bbd599b6ee213baff2;
    uint256 constant IC4x_PART2 = 0xca9765fd74b64189fccf21520a3b3956438127e8355a5f8ecafea4b16bd03ccf;
    uint256 constant IC4y_PART1 = 0x000000000000000000000000000000000d8df1a9eef283ec1ba8178d9c0c8150;
    uint256 constant IC4y_PART2 = 0x49d357208394d4c1d7329870bf82ac41a2cdb1f106fd922a68ff4698cffdb247;

    uint256 constant IC5x_PART1 = 0x0000000000000000000000000000000016a45464b2cbff5c5e6ba8fa07493104;
    uint256 constant IC5x_PART2 = 0x12c8c1d9c79f3d72512e3a496b4a3e3878bba7ff9b2b750a47e707f13e8de278;
    uint256 constant IC5y_PART1 = 0x0000000000000000000000000000000018ae9541a0da0dd918d9848eab0f170d;
    uint256 constant IC5y_PART2 = 0x370e5932d6eea3c2f43df879a118a5b036fe2d71ce1937dcb9a4f37f8e086cd8;

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
