// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x00000000000000000000000000000000140665b74aa6eef5950749a7238a53c9;
    uint256 constant alphax_PART2 = 0x6305b7eae09cbd7a7f2ccdd0a7a84c58a4e2dc00cca569dd3c6f4ca0399119e2;
    uint256 constant alphay_PART1 = 0x000000000000000000000000000000000de68df82dbd944ba3d1b4be93fe3bf3;
    uint256 constant alphay_PART2 = 0x7743a6b7d1cab03fea6b6a85dd44ef1a8c4a123e35c1ebf03ecbb7e06480ae85;
    uint256 constant betax1_PART1 = 0x0000000000000000000000000000000017a91f091f9d353abe342ec455c6c26b;
    uint256 constant betax1_PART2 = 0xa402b717dbaf3a670e0a4b279e0ef00754573398adb455c57028e6a8532c8628;
    uint256 constant betax2_PART1 = 0x0000000000000000000000000000000009fd039affd13122271f433cacd7030d;
    uint256 constant betax2_PART2 = 0x6d0f5141395551664cbd6fb3af8fc5b2ca733a8443610f0b39c9ad644606e8db;
    uint256 constant betay1_PART1 = 0x000000000000000000000000000000000161074177f8a95a00dc565ec2da0a27;
    uint256 constant betay1_PART2 = 0x6d20f193a9562ecb75f5b3f91597b6f063ce1cc8fe81101c31139f6bddf82551;
    uint256 constant betay2_PART1 = 0x0000000000000000000000000000000009ce36d62afb00aa54731cad82c351c6;
    uint256 constant betay2_PART2 = 0x45cd0f30996dfaa248843a3001649d3c3ff5827708a9b65088859523fa767351;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x000000000000000000000000000000000add77391347aa0e6cab0582ef3333bf;
    uint256 constant deltax2_PART2 = 0xdf057de5ca1b04b96e8b7dafa87cd89e16fd506c6c0e85f3721179995a7f8ce0;
    uint256 constant deltax1_PART1 = 0x0000000000000000000000000000000018156ef52b418c60dc95f946edac9824;
    uint256 constant deltax1_PART2 = 0x57ae531d63a6a3ecee0771910b4d22bc1014c5e28142e1a18098a9defb21882b;
    uint256 constant deltay2_PART1 = 0x00000000000000000000000000000000195666abfe29be783b2380ddf9c46a5b;
    uint256 constant deltay2_PART2 = 0x385284f9f0d6a96c82abbbe26fa624a1aa7ad02f82226ce04a0ecc5736d9ecbe;
    uint256 constant deltay1_PART1 = 0x0000000000000000000000000000000019a47e244b36e927d97516e3c2b6166e;
    uint256 constant deltay1_PART2 = 0xda902309ae48972262c404b269b7714298e964a6f3e774f3a050c5600c64d09c;

    uint256 constant IC0x_PART1 = 0x000000000000000000000000000000000693423d40bb2c341d9ba732c187ff74;
    uint256 constant IC0x_PART2 = 0x519276d0c40c5baec007aac79a16223a0a67bfae435f04c8571f17b55160ac5b;
    uint256 constant IC0y_PART1 = 0x0000000000000000000000000000000009ff96bd32b5e754ef6b854d80027ab6;
    uint256 constant IC0y_PART2 = 0x0f425ac15940710b4c67b6b185abde7c1b2baa8f4c3681d69a9f0be1a0636ec8;

    uint256 constant IC1x_PART1 = 0x00000000000000000000000000000000150955f20d1f2ab4c359b3c8fce59ae0;
    uint256 constant IC1x_PART2 = 0xa1d7a91a7db2bdb48369a173658884bd48e93386eede3ae1dedfa4636508becf;
    uint256 constant IC1y_PART1 = 0x00000000000000000000000000000000006501400ea582059c84d97dc8cd2681;
    uint256 constant IC1y_PART2 = 0xb866e3ec50124547a0d8a4f073f3fa2dd2744ff952e07a4028b60c8192fe5e4e;

    uint256 constant IC2x_PART1 = 0x0000000000000000000000000000000002caa6855312b92186718bdc3ce9085c;
    uint256 constant IC2x_PART2 = 0xbe041223622fa721a28c8cdb4d6adc741a0a0832370891f4fd738ec40209186c;
    uint256 constant IC2y_PART1 = 0x000000000000000000000000000000000ad1a6f1ff09e2ad88c642ad0e0b1167;
    uint256 constant IC2y_PART2 = 0xac08fc10abd76d796cb44a78319ef91a0ff2d007eebfb0d5c356b9ac3889bbe0;

    uint256 constant IC3x_PART1 = 0x000000000000000000000000000000000337db669ae0e625601ad88ddd8cf49c;
    uint256 constant IC3x_PART2 = 0x677c55f62b4b32b5a10876e04a6e69cd3ea38fb062594984381d73e7d3f255ae;
    uint256 constant IC3y_PART1 = 0x0000000000000000000000000000000001e2aa04a130545ededa0ef84c08db8d;
    uint256 constant IC3y_PART2 = 0x6b5a2262d5cc500314eb5ea8f08c5c8f684fcbeeee5b4917c19a88f8e5ed6748;

    uint256 constant IC4x_PART1 = 0x000000000000000000000000000000000cc950ba99dbe9d33beab1fc8208fb99;
    uint256 constant IC4x_PART2 = 0x9b338f7700ef59e79274ee287e10dee27a8690b583ab6a27d4b128623e360cea;
    uint256 constant IC4y_PART1 = 0x00000000000000000000000000000000169656f29b3c85218a9bea899386835b;
    uint256 constant IC4y_PART2 = 0x5175697fc6adde73e01dc0a1d9b6bcf46eab33824ada5d7840b48f7b75acb56c;

    uint256 constant IC5x_PART1 = 0x0000000000000000000000000000000008459db56c15ef35790f22bef925cb48;
    uint256 constant IC5x_PART2 = 0xabbc25bc8e27962ad400d3a26639f50aef68838d1b653dcca121d0bb57110e0f;
    uint256 constant IC5y_PART1 = 0x0000000000000000000000000000000000cb339f40189c3f9372baff0fecc065;
    uint256 constant IC5y_PART2 = 0xe0812c125094a9304a87dddf17b9ac717159de60cfacb5c5e2ce62a6210fa746;

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
