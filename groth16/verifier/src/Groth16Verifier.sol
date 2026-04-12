// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x000000000000000000000000000000000081c05ff7279dd609611bbe8e6cc94f;
    uint256 constant alphax_PART2 = 0xe4966302abf2c98ef169402eeab1212c778d379ea1e97d82b5e6f0c82aea1185;
    uint256 constant alphay_PART1 = 0x000000000000000000000000000000001386ea1db7714bc565e120c9dc19ae72;
    uint256 constant alphay_PART2 = 0x63a3e47cb159c5018506a14cf9d1a2f8d5c91cd1ac34604b94f8d0d41689a009;
    uint256 constant betax1_PART1 = 0x0000000000000000000000000000000014dba4bd1f3df3a0a6811803a1d380c3;
    uint256 constant betax1_PART2 = 0xa3be59af6876fc6fa1f38394fc845e28bd8bfd49d649ab53f04783cbcbd8e41b;
    uint256 constant betax2_PART1 = 0x00000000000000000000000000000000030a93f54f457d56b555fccf825f159f;
    uint256 constant betax2_PART2 = 0xd2ee92f43934250e7f5754b01524e0e455d5a7936e005e2951237bfea7f36a13;
    uint256 constant betay1_PART1 = 0x00000000000000000000000000000000006fa161affee7988179622a6b86ed8f;
    uint256 constant betay1_PART2 = 0xf9e55eccdf99b83329dc8f69937a54b2502022d084b069699b64a40646b51e82;
    uint256 constant betay2_PART1 = 0x00000000000000000000000000000000176ef99c72575a34430493a79d92f84d;
    uint256 constant betay2_PART2 = 0xecdbb8f4bb7dbe5e2edc1fc3d4e3403bb55f6dfb957e0036eafffa99ed559196;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x000000000000000000000000000000000aa393adf654389b1ecfcca7d49d288f;
    uint256 constant deltax2_PART2 = 0x24dcd0bda433e920a8f096d26d45694dac8e9459128e5d36f577cef4b80cf239;
    uint256 constant deltax1_PART1 = 0x0000000000000000000000000000000003fe0cdf3bf79473aa8e040cf6ac98b2;
    uint256 constant deltax1_PART2 = 0x38ba9be059e778ab01a8039ca44f0e8596c1494bf0c86e95b628557b2769516b;
    uint256 constant deltay2_PART1 = 0x0000000000000000000000000000000015a13b149bd064d13d6ed5b8047cc7cc;
    uint256 constant deltay2_PART2 = 0xdc10f9a979a19233904f2e52955203fa6572cb33e04214c778ce5a3470fa1413;
    uint256 constant deltay1_PART1 = 0x000000000000000000000000000000000bef966e1504bbcdedefef3cb004e4f4;
    uint256 constant deltay1_PART2 = 0x37ae4c6c421b333d05d9feac87ca60e2e766522343bfc72425d78f534d7718e3;

    uint256 constant IC0x_PART1 = 0x0000000000000000000000000000000001f5f9eab8e406be3dab3402bd099eef;
    uint256 constant IC0x_PART2 = 0xb6d5f90cb66b9dc4444f7c0d396dff9c20600f6df44745c64cf4e09884da0c14;
    uint256 constant IC0y_PART1 = 0x0000000000000000000000000000000016bb9d83a09678a193991303f8a1c7d8;
    uint256 constant IC0y_PART2 = 0x6bd928367ba53316b9398528738cbc429a6863397b2dbdfb66d7f3e74b94544b;

    uint256 constant IC1x_PART1 = 0x000000000000000000000000000000000e58fb18ff06df5abd323debef546030;
    uint256 constant IC1x_PART2 = 0xc3debff8eab87a81b88c209d7be7993c7272c48b3aef5591cde784b70b1b3647;
    uint256 constant IC1y_PART1 = 0x00000000000000000000000000000000072386c8711674a982846e81150ac347;
    uint256 constant IC1y_PART2 = 0xf3974f5202fa1b8659b0a29d3d6ae1bd90efdc897be10dd59e13e4145c4e4af3;

    uint256 constant IC2x_PART1 = 0x00000000000000000000000000000000087d8d620554a08d0a9e3eea9660fe14;
    uint256 constant IC2x_PART2 = 0xca63023e598eb437d0bd4d25c77465878d33929860c72538b64a137ff8ab9ed1;
    uint256 constant IC2y_PART1 = 0x000000000000000000000000000000000691330c0a01918c09e3702d5452fb73;
    uint256 constant IC2y_PART2 = 0x13c0248f7b8672db667c6f77809ed0a9cefbb90ab35f93dcef8f8e3fcd27b52a;

    uint256 constant IC3x_PART1 = 0x0000000000000000000000000000000003356f0e7b606f2bdf164e2ca64bc9ef;
    uint256 constant IC3x_PART2 = 0x3e5f1163bea7826342aa08e48bc8aa77062007b9e88843172f4d1d3f7b0bc36b;
    uint256 constant IC3y_PART1 = 0x0000000000000000000000000000000001944f4c13998a0ba3edca157c2af7e3;
    uint256 constant IC3y_PART2 = 0x2057333b187a1d4a85d61625a25ec1af3ef6d037cb5fba2fe12f3f5e844eb2a1;

    uint256 constant IC4x_PART1 = 0x00000000000000000000000000000000170c89a70de2a3bf42bed829b0000e54;
    uint256 constant IC4x_PART2 = 0x4d217775658e5ae06a76eb5e8250a16404d78fb2a26d29444262212bab70869b;
    uint256 constant IC4y_PART1 = 0x0000000000000000000000000000000000624e64f73a9f2914302db5fa674bcc;
    uint256 constant IC4y_PART2 = 0x9cba30580d36b4ae6ab383a2f4b45feaa91a4100d0b19cccb394aeb91e8a32e9;

    uint256 constant IC5x_PART1 = 0x0000000000000000000000000000000009100d47ac27704a7f75e01f3848265d;
    uint256 constant IC5x_PART2 = 0x71ca9609eb52049c884f5e9123766d2e182235fc9e30ee0cce5327d65f86b58f;
    uint256 constant IC5y_PART1 = 0x00000000000000000000000000000000163aa36de4f049cd766dc9cc9834567c;
    uint256 constant IC5y_PART2 = 0x8bd1475d16672a10230f4978cd5dab6a27c3c6c18c959a590225d2f8b22c8987;

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
