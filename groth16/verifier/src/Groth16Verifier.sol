// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x000000000000000000000000000000001822f1d6a0e8132cad12b63c6564a7d8;
    uint256 constant alphax_PART2 = 0x593820f8268c03ae0bf6f32c7fd0e173fa2440e0dce47d850be9fe0b563a7c6c;
    uint256 constant alphay_PART1 = 0x0000000000000000000000000000000012e35ad673bf8e4aadd5d8f986f3a4c9;
    uint256 constant alphay_PART2 = 0xea42defb2ea0ea321bb96991117b7ce0be684fb685347505de83b20916b0127b;
    uint256 constant betax1_PART1 = 0x000000000000000000000000000000000de814f5668f07077a69deaf6d8d5717;
    uint256 constant betax1_PART2 = 0x57a44ec9914391e9b1c01390916c0c2ec85b9bf2a572cb2951f3178058447bf2;
    uint256 constant betax2_PART1 = 0x00000000000000000000000000000000044e83edc98c171a562d5d615b3ccbf5;
    uint256 constant betax2_PART2 = 0x8d5d0b9d6588264ab59d622c7cb23b915e8cbbb816dcc8b6510aeb5b2503f09c;
    uint256 constant betay1_PART1 = 0x00000000000000000000000000000000075caba482fcba23c9b8138f22e114e7;
    uint256 constant betay1_PART2 = 0xff9dd708a464f198f56fd60f5671d800a584294867d318bf451616371f3de927;
    uint256 constant betay2_PART1 = 0x0000000000000000000000000000000014db1a08f95ea5bde327eecb98d16d40;
    uint256 constant betay2_PART2 = 0xdb2a639ad12fbb030a614b307808773c170c11ec36285d18a3f8e91406fff2fd;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x00000000000000000000000000000000028c0188faff4576b3a43fce7d0b9b86;
    uint256 constant deltax2_PART2 = 0x2fd60414571986214006476fa49ad9f8234d8da04ae2e34687b37b5a4b2b609a;
    uint256 constant deltax1_PART1 = 0x0000000000000000000000000000000008c26cd39d17d5ce4ab0d1a038325176;
    uint256 constant deltax1_PART2 = 0xe89344b57bd6996a79896f974c642bf1a34cd14c18025ed56bf0074ac45e3e51;
    uint256 constant deltay2_PART1 = 0x000000000000000000000000000000000317fa97be0e7e9d454bc1c8540ce6bb;
    uint256 constant deltay2_PART2 = 0x99f49e2f08cf4b6140c46d45e381555fdd96e8d25da610e3ab02a16aba2b6a78;
    uint256 constant deltay1_PART1 = 0x0000000000000000000000000000000011668d450d7833fb9606e154fc5c2659;
    uint256 constant deltay1_PART2 = 0xe0a926233d95c54dc3ddaf97eb622640c68228f890bf8567e99b8222c641b7a5;

    uint256 constant IC0x_PART1 = 0x0000000000000000000000000000000016373439f0e7c1934be95db680574646;
    uint256 constant IC0x_PART2 = 0x58f52a3be9be521c8644d5da935deaed36accb4ee212c38687d202b9e3027fe5;
    uint256 constant IC0y_PART1 = 0x0000000000000000000000000000000001a19be9bf35b225e333702baf451431;
    uint256 constant IC0y_PART2 = 0xf75897c62ccadd602d12861746672e95d46e3abc3e509bb6c37b15af528361f2;

    uint256 constant IC1x_PART1 = 0x00000000000000000000000000000000155288f9a923bef5af881fc54996c997;
    uint256 constant IC1x_PART2 = 0xbbf98e3bedca04a330795d6b01d57df811351f16b5481bb1a81442194c60a519;
    uint256 constant IC1y_PART1 = 0x000000000000000000000000000000001224c7f0c834895a271aa3e7411e6c82;
    uint256 constant IC1y_PART2 = 0xc6f69aedbd2f5f837f3fd121b34a9ee4d000fdafa638f3c2d20a3ae9c40b04c8;

    uint256 constant IC2x_PART1 = 0x0000000000000000000000000000000014b0104b485b41f70607630e92d7a034;
    uint256 constant IC2x_PART2 = 0xbe6758f05ccde1271d43f917bb690657c283aee8323127a6dd5d92f9e4b821fa;
    uint256 constant IC2y_PART1 = 0x0000000000000000000000000000000004a74a799e1684bf1f3a5195c2ec707a;
    uint256 constant IC2y_PART2 = 0xc5045e88e4e260e120d5b73d2e3f9bae1e77e621dc9fd0ecb445d2f6dcd7e343;

    uint256 constant IC3x_PART1 = 0x00000000000000000000000000000000181f002d9f6e4d2fc013ada80088049c;
    uint256 constant IC3x_PART2 = 0x75f4166c7739009426a38c52b2088478fafa4d4a6048c00eca143e29bff3c669;
    uint256 constant IC3y_PART1 = 0x00000000000000000000000000000000174c9f5aa5c3b955acda9aeb6aaec29f;
    uint256 constant IC3y_PART2 = 0x44a737d46184b56a43d7dbf55718590ebe1b8263ccfe40cf28c31263f9726723;

    uint256 constant IC4x_PART1 = 0x0000000000000000000000000000000001c052fe4176287e1efda425893db387;
    uint256 constant IC4x_PART2 = 0x89506970a2ed17114cc3abc081f43d63c82ec3165876238adf4a44b6e39586d2;
    uint256 constant IC4y_PART1 = 0x00000000000000000000000000000000030aa62623d1f1dc2b6cdb75586f66c8;
    uint256 constant IC4y_PART2 = 0x550ab04be4916d2360e67301c088037d198bbf9c43b6a720b46c3674cb7b695b;

    uint256 constant IC5x_PART1 = 0x000000000000000000000000000000000c2037327686beae100ea2c7f5d74a76;
    uint256 constant IC5x_PART2 = 0xd15b77fde45ea803c43eea13fc84844e14c103c010f16c545503252712047cfc;
    uint256 constant IC5y_PART1 = 0x000000000000000000000000000000000970a886d84383ed2dfb36f9bebca24a;
    uint256 constant IC5y_PART2 = 0x0c0597e758dd8ba0ad8fb80918c281ae52bda841997df000907699d1258f1f60;

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
