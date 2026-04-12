// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x00000000000000000000000000000000059bdb9b3d047e953cd76a21c62346fc;
    uint256 constant alphax_PART2 = 0xf75a5bbe763fc92ef71241569d48544d2abf03fc660136ce18c1070d1fc4e651;
    uint256 constant alphay_PART1 = 0x0000000000000000000000000000000001161d186ff1e6ee30c069aa0728cc4c;
    uint256 constant alphay_PART2 = 0xfb7fa0b185db125e7959e6d0cfe265c59d2811227835af0cf95152e771ac85fd;
    uint256 constant betax1_PART1 = 0x00000000000000000000000000000000111ae44c04be30e25e42cba30a142657;
    uint256 constant betax1_PART2 = 0x24b77733ca608878b3c8a00d1ed0eb67982bef66e12df9fda013f9beeba52b0c;
    uint256 constant betax2_PART1 = 0x0000000000000000000000000000000003edcdac14f4d57375becd70167e75f0;
    uint256 constant betax2_PART2 = 0xedd422300ce3dab133971d98ce26fe58ffc13714595d2afb07216c1b79546b9c;
    uint256 constant betay1_PART1 = 0x0000000000000000000000000000000015049e9a6e3788b8766b2c7131e0e348;
    uint256 constant betay1_PART2 = 0x9bf7c0cc4c4248dcd52e385db451e7eb48b5c44fdce5fccbcca5a0ace01e8c6c;
    uint256 constant betay2_PART1 = 0x000000000000000000000000000000000502b0a8457803fc924672c9c445fca4;
    uint256 constant betay2_PART2 = 0xc1cd32997a6856df4bd1bb9ce40d51cd452a639a05112602a946c7bdd796653e;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x00000000000000000000000000000000108324c712c32ed0e21b9055218d166c;
    uint256 constant deltax2_PART2 = 0xe643ef36d2dab49d55a44f2fb852d9bae518d265398bff50092a15b7bc351cac;
    uint256 constant deltax1_PART1 = 0x0000000000000000000000000000000004504e0c839bb743b3cc1572e6cb0541;
    uint256 constant deltax1_PART2 = 0xc6e3d6a1109ba0cd63df3107e4742aad745b8dbc69e021ee62643163ddda3c41;
    uint256 constant deltay2_PART1 = 0x00000000000000000000000000000000179769e6b2cea9464d1f82c1c0314cf1;
    uint256 constant deltay2_PART2 = 0xbc5b8e564b32d753999eb4a0db2f17e4e34d73bf158a2c219924df5b347b1d71;
    uint256 constant deltay1_PART1 = 0x0000000000000000000000000000000007c89184bfd939cc5e4713363e58e74b;
    uint256 constant deltay1_PART2 = 0x8037475b6b4fc38f3ffd495ef83296b3fa56e2e4646d57fc3e56161597c550ba;

    uint256 constant IC0x_PART1 = 0x000000000000000000000000000000000054916c33fc939e5e04296db76ba1a4;
    uint256 constant IC0x_PART2 = 0xd7118dd1b5e1465a45b7e398d45875e3f4e5dc7a551059552820a499bb5fa8cb;
    uint256 constant IC0y_PART1 = 0x0000000000000000000000000000000016defb9cc7294d78ac0d01f06c5cc03e;
    uint256 constant IC0y_PART2 = 0x93180f4e83689726e5a1d66e90e0e6a9e755cbdfd71d90dc2059f54f3043ed1e;

    uint256 constant IC1x_PART1 = 0x000000000000000000000000000000000e4cb27cbdc5f2b55da7456726134fa0;
    uint256 constant IC1x_PART2 = 0x3ee2cd41434caafcffb228492d9dd0ea4cb2a509a40171db0bbe2233e365eeff;
    uint256 constant IC1y_PART1 = 0x00000000000000000000000000000000166fd272b76c5cb0e9168a27903963ea;
    uint256 constant IC1y_PART2 = 0xd6971644f5aeabe3587e1af4a946b2dbff87d6ed076212f793423d47708e1b16;

    uint256 constant IC2x_PART1 = 0x000000000000000000000000000000000093ef02c6a010b398c359720f875edb;
    uint256 constant IC2x_PART2 = 0xaaafca9701d0dcd31687efb94e196a25d0789e7200c3a18c3be09599974ccf85;
    uint256 constant IC2y_PART1 = 0x000000000000000000000000000000000efa0630224bdc2ebedef4a105db9091;
    uint256 constant IC2y_PART2 = 0x22a2d1c5ae472f570a968572f2f24b263b0bfffa8da25313071d14212ef9873f;

    uint256 constant IC3x_PART1 = 0x00000000000000000000000000000000029d074bbc8496626ca43b67b777dae5;
    uint256 constant IC3x_PART2 = 0xbce030688a064005cda10d91822ab771783c43c2f4abb1a33a1cbc461b919cbe;
    uint256 constant IC3y_PART1 = 0x000000000000000000000000000000000fa81772dc7fc8a02c47e0a540f24202;
    uint256 constant IC3y_PART2 = 0xe59c398119292e2399976e0a38429b1c53835ea11cbe50ad98a261c8060939b9;

    uint256 constant IC4x_PART1 = 0x0000000000000000000000000000000002f2da61d357321326533bc28c76943b;
    uint256 constant IC4x_PART2 = 0xf5e3a3dcaa5152c6b884967781ba6e418a0f49a05b445d033e3a928b081c9673;
    uint256 constant IC4y_PART1 = 0x000000000000000000000000000000000e912c949871d46fc363b1c49860290f;
    uint256 constant IC4y_PART2 = 0xc80e23f57eff046584cfe28e77bca255df992d8d5eb8b5db0fbbbe699234421a;

    uint256 constant IC5x_PART1 = 0x0000000000000000000000000000000013ee1339ac0cb68b4510d395f5d46b4b;
    uint256 constant IC5x_PART2 = 0xa4494486ae59d0e29c15acbed7b94030feda40be661fa65e1a7c2afc36d56792;
    uint256 constant IC5y_PART1 = 0x00000000000000000000000000000000133b0134727e106c0f370dbe8176843c;
    uint256 constant IC5y_PART2 = 0x74ce11dcbdb142d4b51b1c2681f444f3e0a022343796e2c74a6b58cfea6ca731;

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
