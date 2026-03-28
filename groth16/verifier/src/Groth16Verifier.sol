// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x00000000000000000000000000000000128c43933a0d9f6fc58b4bea66b9bb21;
    uint256 constant alphax_PART2 = 0x294fb9c2d002f768313e15cda27e1cbd75ab9fa8f5dd01a994472a61edc41e7a;
    uint256 constant alphay_PART1 = 0x000000000000000000000000000000001847a76056f211c3757f59d975c1684f;
    uint256 constant alphay_PART2 = 0xccdbb86ec86e44fb19464fd0de0018d69d26035f48ea83ebeaa15f5fb61a1637;
    uint256 constant betax1_PART1 = 0x0000000000000000000000000000000012e71ad3fb823eddc237e32e3ed21fc6;
    uint256 constant betax1_PART2 = 0x7c18332a857b0d8f2cd591f1910a09590a9c3675c8b6b0ad2951b33136a520c9;
    uint256 constant betax2_PART1 = 0x0000000000000000000000000000000018c1e6988ef7612c2a4123b76a2f31ce;
    uint256 constant betax2_PART2 = 0xd54762ed35d26be04307bb6bd31b35871b805b70bda2a265529ca7f6f34193c7;
    uint256 constant betay1_PART1 = 0x0000000000000000000000000000000003cdb0c749237e0ac594f3cd63bf27e4;
    uint256 constant betay1_PART2 = 0xfcac11185aff76480b8e276c272279c5331bb54e3f5e3d980022de90ceb12ba7;
    uint256 constant betay2_PART1 = 0x000000000000000000000000000000000d0c2fb20dbe919e78996be9e9d8d4e3;
    uint256 constant betay2_PART2 = 0xd1e311c187319c469e29a32e8300e863e2619412cc3f63e391487164d3dcea7a;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x0000000000000000000000000000000005f44bc7bf8d97fd312bd5e18f43c1c3;
    uint256 constant deltax2_PART2 = 0x1be1c7293fa746eb2df01f5afb6c11006a08eb8813440da0bf85e1f8fb9001b4;
    uint256 constant deltax1_PART1 = 0x000000000000000000000000000000000c0e0b7cdca42bb4fbdcca02cddf4f68;
    uint256 constant deltax1_PART2 = 0x4036f774392623b9fee4da76cc40429b7c3269e490353670ef1d390825a5abe1;
    uint256 constant deltay2_PART1 = 0x0000000000000000000000000000000003ad443af548203cb561b3ee735f5e83;
    uint256 constant deltay2_PART2 = 0xb7063246abc0d89e7eebf304e7a6c597f9b066087eb48354906f75ea248b1076;
    uint256 constant deltay1_PART1 = 0x0000000000000000000000000000000011af280f6868fe0e3d13be1c8f7c15ed;
    uint256 constant deltay1_PART2 = 0xa608a4cbc7eca596c5b3a62525f29ac74d79fc6145b5c94eef0d066827d376f6;

    uint256 constant IC0x_PART1 = 0x000000000000000000000000000000000950c55b45398ffca892815f9ca3ff5f;
    uint256 constant IC0x_PART2 = 0x7bff82540c2ef467ee52690ed33ae4960b11fe02919cedc1c0fad2eea5b6ca3d;
    uint256 constant IC0y_PART1 = 0x0000000000000000000000000000000001a530315721d29894d60c76bef3d7ce;
    uint256 constant IC0y_PART2 = 0xa8ed656fccb4abd4dacaf1d78ae29b7ddab17073899a323b3384803945ca49c1;

    uint256 constant IC1x_PART1 = 0x0000000000000000000000000000000002ae9da5af4d535385870c4803c6f546;
    uint256 constant IC1x_PART2 = 0xb0059e597b59f4ba9ecd491680e42235c3bd92172f3794d6123001203c0a4812;
    uint256 constant IC1y_PART1 = 0x0000000000000000000000000000000010e6aa2fc2779c569f7418cdbf8c2035;
    uint256 constant IC1y_PART2 = 0xff8cb886a9fc1e165bdd2c87f24c48865287237e844969e46df80857e68201e1;

    uint256 constant IC2x_PART1 = 0x000000000000000000000000000000000bb562725dc38d981ffee520e0b3290b;
    uint256 constant IC2x_PART2 = 0xc204fd965bcee859c1403a3a28cb63352f5607f8c04c8dff9b82937b208ec284;
    uint256 constant IC2y_PART1 = 0x000000000000000000000000000000000a8e2161c3e946e74fb0f6a98dd5dcc1;
    uint256 constant IC2y_PART2 = 0x83ace96dfa2ec8e90fbf087c6e54971c70b1ffd3f48ca8240e3184cb8329311a;

    uint256 constant IC3x_PART1 = 0x0000000000000000000000000000000005145bca51477f32b1e37e46005886f7;
    uint256 constant IC3x_PART2 = 0x193795eccdf2f1a64aacb7b4ee356f0772fadaf5475d5efb0af7494dd9f4b5bf;
    uint256 constant IC3y_PART1 = 0x00000000000000000000000000000000085abe1e94a2fee88dd6ef67120a9133;
    uint256 constant IC3y_PART2 = 0xa8b82f26a4fe6a938f9476192b163bb8eb9cbe657e243d3b5593f142b520d177;

    uint256 constant IC4x_PART1 = 0x00000000000000000000000000000000070d1f8cc7a724a42bc16cc791b09f8e;
    uint256 constant IC4x_PART2 = 0xa84e4e183f76bb150631e0a83976114f345004e6a2c20f4ccf76182bc7e2a671;
    uint256 constant IC4y_PART1 = 0x000000000000000000000000000000001763ee12a0e35c9d549bd263bca05213;
    uint256 constant IC4y_PART2 = 0xd26d992b42e1eeca9e0a6ad2fc445442a2b901edb20035df448f7a72da7adbea;

    uint256 constant IC5x_PART1 = 0x0000000000000000000000000000000009ec3c76f61167f17408d5e21ba2eb45;
    uint256 constant IC5x_PART2 = 0x4764df72d1f6fa84b1f186c87bc64f776defb1bbb7e9bc8b9055866001ab0050;
    uint256 constant IC5y_PART1 = 0x000000000000000000000000000000001791b2121c650335922e97cbfe94a669;
    uint256 constant IC5y_PART2 = 0xd8f43cdc41a5b93aa99fed932eb4b5711decc345db61679609c59b8cba996cb5;

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
