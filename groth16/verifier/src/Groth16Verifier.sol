// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x0000000000000000000000000000000009443ffc64bd58bdf32b3de905ad46ec;
    uint256 constant alphax_PART2 = 0x4665390580b807cdefb72e8383046415b2a947eee615b601699fb77ecf73d314;
    uint256 constant alphay_PART1 = 0x0000000000000000000000000000000007a76cf0b5eb941a24f0b4b361824597;
    uint256 constant alphay_PART2 = 0xbed1c41239017829a7085e126c874369447fbd270c3433f0869930e287f55ab8;
    uint256 constant betax1_PART1 = 0x000000000000000000000000000000001209753f82f2bf0f7d342fbffa72a7b6;
    uint256 constant betax1_PART2 = 0x367236a88cf7927d5155dbdbe13aa0e38ee96a77e813587fa1a02d6abf63b1f1;
    uint256 constant betax2_PART1 = 0x0000000000000000000000000000000003be8bf4b95460dd0246e7ae71590b24;
    uint256 constant betax2_PART2 = 0xbd388be4928e7ec14f9961b7ea9f0feb236dafa2d0cfc716d58fecc5046829cb;
    uint256 constant betay1_PART1 = 0x0000000000000000000000000000000008fe0cf4c1741410f1b9afab265432cc;
    uint256 constant betay1_PART2 = 0xa9c66519449cb3244aca968713707eb6a473bdca74be681939a7bd1cb4ce98e7;
    uint256 constant betay2_PART1 = 0x000000000000000000000000000000000eccc60b7e26b264f18f618b45f11a5b;
    uint256 constant betay2_PART2 = 0x13ad633979b739df28652e1169b1b68e02c06f807ec04945fdceb79b7799070f;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x000000000000000000000000000000000bbddee812e4866a13812495b2608125;
    uint256 constant deltax2_PART2 = 0xc84f067f5772d82fdc4fb3a9d035869bde144cb36b6ea583356f083e406579c0;
    uint256 constant deltax1_PART1 = 0x000000000000000000000000000000001718d9ee81984f2c17e48e6c30c0a7d7;
    uint256 constant deltax1_PART2 = 0x9d9346b8fb7ad233a68f8947144b0cf063ed5e716de686695a4691b8af75c49f;
    uint256 constant deltay2_PART1 = 0x00000000000000000000000000000000011dfb0f60857d771b606faab9491b2d;
    uint256 constant deltay2_PART2 = 0xd4fcaafb7c1a0fd85e3f30f23fc43fb6832d5ac0e975c7d6a2d1674dd0a4182d;
    uint256 constant deltay1_PART1 = 0x0000000000000000000000000000000013643d633249afcc1bb67b07bb64d0be;
    uint256 constant deltay1_PART2 = 0xc63ebc090916d5cf9b907dd4956dbc1c47fca90f5798c09b00b671dff19cbbbb;

    uint256 constant IC0x_PART1 = 0x000000000000000000000000000000000a1f838984e26a2addf6eb7151e6e306;
    uint256 constant IC0x_PART2 = 0xa8f59e02bec4793c5f8fc398d6dd1a8aab1649b6dc5601c221243f6b0181fbe9;
    uint256 constant IC0y_PART1 = 0x0000000000000000000000000000000014dd6c11bc905842dfd1b7644b450e79;
    uint256 constant IC0y_PART2 = 0xd607ddce1fa5e7f6200972b71dfdc5f4379a9cbec76d414c808465004b75f04d;

    uint256 constant IC1x_PART1 = 0x0000000000000000000000000000000008620a91d7d223468673935406b0d369;
    uint256 constant IC1x_PART2 = 0xaecd2bb5bdcd67b315b214e0438d75452b6358dd5572c6f5ae7637fe34913b54;
    uint256 constant IC1y_PART1 = 0x0000000000000000000000000000000014274d717aa13727467122ce8c422cdb;
    uint256 constant IC1y_PART2 = 0x27236a9192e78615e00ee92a30bcbcaa7295b3f8a569ab4390b373b51f8cc0b7;

    uint256 constant IC2x_PART1 = 0x00000000000000000000000000000000010ea0548c31adb1368440b7ff4f6cf0;
    uint256 constant IC2x_PART2 = 0x4d34760933c354ca40b882c54e189df102f2f6eae48ed65f14eb3da7cec27642;
    uint256 constant IC2y_PART1 = 0x000000000000000000000000000000000c2d5037bb0d35c1f76775a0774de4ea;
    uint256 constant IC2y_PART2 = 0x37d62cbd91fd6583f8081425ed20fe4b755ab23e96e028e90590519b36798631;

    uint256 constant IC3x_PART1 = 0x0000000000000000000000000000000017f8e4c34cffe56fab529a910bb8a544;
    uint256 constant IC3x_PART2 = 0xe86c2537dd1cdfab53a567b53fed9db1a008e90b7dadfc2f4647f9c6950f9823;
    uint256 constant IC3y_PART1 = 0x000000000000000000000000000000000598b19bc2a90540c0abbdbfb5fd2fe0;
    uint256 constant IC3y_PART2 = 0xc373174bdad49265a890bcaf470482bb3e3be255fa95ae8d356849ba6959694d;

    uint256 constant IC4x_PART1 = 0x0000000000000000000000000000000003124bfa5b17e7ae30978c5053803c39;
    uint256 constant IC4x_PART2 = 0xd4c6f8a790c5494312fa1dafa704ca921088f03f847d60036f8e902242889c96;
    uint256 constant IC4y_PART1 = 0x0000000000000000000000000000000002a282a200cae5472cf92132844ad24a;
    uint256 constant IC4y_PART2 = 0xd8dc8bd3cfa74dd0fbd7b97d518f6adb7cc4d19d03b04caf5c5354abd549a58b;

    uint256 constant IC5x_PART1 = 0x000000000000000000000000000000000020cc3199e6b945087180ea129da2b5;
    uint256 constant IC5x_PART2 = 0xa21bf6a57cbe135ae60724ef1a6558080e45d5f8a451064c05fb17a9810ade0e;
    uint256 constant IC5y_PART1 = 0x00000000000000000000000000000000020a88f21ea9d04421ce89a082c4b4b6;
    uint256 constant IC5y_PART2 = 0x9bfc1e1743f23e091433e1a5863c03c22160464427912644a36db21cd1ace43e;

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
