// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x000000000000000000000000000000001369e56688f257fc66d5023b4c2ae530;
    uint256 constant alphax_PART2 = 0x1580643ebcbc64123d0b52cbd01fb3a2b505da749f8293b20b25bc2adac4130e;
    uint256 constant alphay_PART1 = 0x00000000000000000000000000000000071c3b9a1d727607eb1a0034945f581f;
    uint256 constant alphay_PART2 = 0x9564f9f2044685f60c2634f48024a3098b252958119de38d19f32f0a04e8b033;
    uint256 constant betax1_PART1 = 0x00000000000000000000000000000000054a9422c1e71c1b1053ecf17262e475;
    uint256 constant betax1_PART2 = 0xe7be449f410b2a4807d0e24044e0b019e5ad1f419a4d6db49705ecf32f4b22b9;
    uint256 constant betax2_PART1 = 0x0000000000000000000000000000000014478a601eeb4507b56f435c8ce6120e;
    uint256 constant betax2_PART2 = 0xb15f1aa33714e82855193433af1d42885f0c81adf733437fe3ddf39d74c47bcb;
    uint256 constant betay1_PART1 = 0x0000000000000000000000000000000017495c2666a6a18bc35388ee34be8d66;
    uint256 constant betay1_PART2 = 0x3350d22b18fec8859744e3129ca352240ade377a90f76c0229ce2f3dd4be90f9;
    uint256 constant betay2_PART1 = 0x00000000000000000000000000000000154b9ce1a19c6ec8450200bfdb164766;
    uint256 constant betay2_PART2 = 0x86efb75789818e257ec101856f64caa5fa30781971c287155dfe42bb96d3b5d0;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x000000000000000000000000000000000328ffb106d5c03c5f120730198bcc26;
    uint256 constant deltax2_PART2 = 0xd650ab4b6e24a92329269a427014c88a1d29b1f5526545011ab09680c9fe6638;
    uint256 constant deltax1_PART1 = 0x00000000000000000000000000000000137f6230af547a317622843b959ef341;
    uint256 constant deltax1_PART2 = 0xbc626b4e2ef34b266a2200e455f092600628787f0fdf172b41460c62fb9dcf09;
    uint256 constant deltay2_PART1 = 0x0000000000000000000000000000000007f83a3c9f7a5e0138c73b206ded46cc;
    uint256 constant deltay2_PART2 = 0xfd4005813573ebad8bdf6848ae3ee70db8d171e815735b5b437d4f4d3c3d11e0;
    uint256 constant deltay1_PART1 = 0x000000000000000000000000000000000e7e0933f87be21717f8839e5702e70b;
    uint256 constant deltay1_PART2 = 0x20e9cebbc9877367b743a294c40a437c214642abd3945de519f1320ca61e40c8;

    uint256 constant IC0x_PART1 = 0x000000000000000000000000000000001045a739beb576e5f2eb770bb5e6de0a;
    uint256 constant IC0x_PART2 = 0xccdc6c9bd30b68614faa8de679e7f85d76812e71641fd68f8f375188bbaefb6b;
    uint256 constant IC0y_PART1 = 0x0000000000000000000000000000000014878b7c13f47d20d6a3d39b59fb30ef;
    uint256 constant IC0y_PART2 = 0xd081d47bd653f9f072453086f5a8582a37bf20f42f9081d4b5b17568d33093be;

    uint256 constant IC1x_PART1 = 0x0000000000000000000000000000000019bef0c1bd10f482a998d1bb7e99be34;
    uint256 constant IC1x_PART2 = 0x8411418a01896b769109e3f7ebd25a5377e46369ab6e82e4006f1cd8d321e704;
    uint256 constant IC1y_PART1 = 0x0000000000000000000000000000000015338f060bc14b2f4d9cbeb7c959a8ce;
    uint256 constant IC1y_PART2 = 0xf59170aa12638166ed878988cd7815be5046997bbe2b0d49cab74fe19312e58d;

    uint256 constant IC2x_PART1 = 0x00000000000000000000000000000000192e9bf3d672771e20fb46f087f955f8;
    uint256 constant IC2x_PART2 = 0x3bd13f16e7d55d95e81a4e06e651c68aa8f228d1ccbe545907a7b5a6e4fbe9de;
    uint256 constant IC2y_PART1 = 0x0000000000000000000000000000000011ffda8205280ff192646210836c50e5;
    uint256 constant IC2y_PART2 = 0xd32bdf0a6f01ba74ffbcc535b4027ee75a73a89841896adf0c3aec3336c818f5;

    uint256 constant IC3x_PART1 = 0x0000000000000000000000000000000004ab5dbb8c6c855caa628d1caf9060fa;
    uint256 constant IC3x_PART2 = 0xe1c833911854051e67db8e4133b19f318c726a261c0e52aa1100b7017241d79d;
    uint256 constant IC3y_PART1 = 0x0000000000000000000000000000000003d3cc50bdf200ddc1571cd86be691fa;
    uint256 constant IC3y_PART2 = 0x713660cbac252ba2e829d8337bff20f4cabcafe90b392d56d3405af536a6aa95;

    uint256 constant IC4x_PART1 = 0x000000000000000000000000000000000eaa1e0390e31d5eef352a3c37d0c01f;
    uint256 constant IC4x_PART2 = 0x431bc4ebe2c7cafdd4ed0b0180560eb5c8369f1f4ebac6b662dec862ef5024fe;
    uint256 constant IC4y_PART1 = 0x0000000000000000000000000000000016ac8b8bb6f30a0d38453f177375aa66;
    uint256 constant IC4y_PART2 = 0x8fd4b2d1200afa5640869fefd3d120e67f836594ed7a01038e673bd5f66dcf23;

    uint256 constant IC5x_PART1 = 0x000000000000000000000000000000000e29ef980072f251558b9c6f8590b3e7;
    uint256 constant IC5x_PART2 = 0xac857efc4af44a0becb4a6e9bede6ac54e1449f5c74fd53a47bfe87855ebfdde;
    uint256 constant IC5y_PART1 = 0x000000000000000000000000000000001829cdc860325f13f45ca3f395c07172;
    uint256 constant IC5y_PART2 = 0xa5022d05025c9ca61168b04892698f2f47c9eb234288c63eca4380c839cbb1d5;

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
