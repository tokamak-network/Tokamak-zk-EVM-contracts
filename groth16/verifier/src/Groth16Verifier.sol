// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x0000000000000000000000000000000003b4114a89f506b3a1b0ebc196597c37;
    uint256 constant alphax_PART2 = 0x981269eee4a1dfc6623cd53d937d87aaecfaa438a2a09a1bfc580a735b0b6059;
    uint256 constant alphay_PART1 = 0x000000000000000000000000000000001459e1eef42ee848410f69dd55a78441;
    uint256 constant alphay_PART2 = 0xcaca2c315e82b84f34185f80d82fda29eee4d024a82cccc739daa9f7172fa1e7;
    uint256 constant betax1_PART1 = 0x000000000000000000000000000000001575f8ca823dd872c489d40acafe1714;
    uint256 constant betax1_PART2 = 0x9ba0fb4f13f2a79e2fb826a13086bc1b7b9c2e28a21b2122bfbe9d62f72e7c8f;
    uint256 constant betax2_PART1 = 0x000000000000000000000000000000001363e8dcfd870f31c29c06afb0fcefd5;
    uint256 constant betax2_PART2 = 0x14facdc0c42b2a5b6545db24136b7e3cbc419b092e25aed88448a6899b89a832;
    uint256 constant betay1_PART1 = 0x00000000000000000000000000000000153474ef6f82c0add79241ce5cdbe600;
    uint256 constant betay1_PART2 = 0x16a74905d34131c34977dc4d5eeb49934e1cd84f8b9d7d0607adaae934e549a4;
    uint256 constant betay2_PART1 = 0x000000000000000000000000000000001906473039245c8ab7268e783e9d13ff;
    uint256 constant betay2_PART2 = 0x27653ec56a8d1b9f5f48c91a809d253c52b3247962c492c4f7113d3db367fa23;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x0000000000000000000000000000000008d62e114692654ca49e0d0ce539f56c;
    uint256 constant deltax2_PART2 = 0x6e6e77a643f524d303303935bdb39e5676193996df16829930fdca087782e09a;
    uint256 constant deltax1_PART1 = 0x00000000000000000000000000000000123229f4301dba7dd2d54f0531e168d8;
    uint256 constant deltax1_PART2 = 0xdbc7a713fcfea506f853db371ba33456cf66cf01f2b62d009c2e7acf66c35940;
    uint256 constant deltay2_PART1 = 0x00000000000000000000000000000000072b369b84a05d5d212575b050ad6599;
    uint256 constant deltay2_PART2 = 0x94ad2f01c8e27dc0db545bb99569e00c649165b8861ebb0c5f51fbe93c98c21d;
    uint256 constant deltay1_PART1 = 0x0000000000000000000000000000000006ff6daf2750975397766d8fba058759;
    uint256 constant deltay1_PART2 = 0x26782b3a73d9be8e9aff6b5f82387c3e5387552650f2995145e63e14ca17cfbd;

    uint256 constant IC0x_PART1 = 0x000000000000000000000000000000001177e0075530c47409d1bda55e9af0fa;
    uint256 constant IC0x_PART2 = 0x91d8611f9723d6b1a17d8428c6a995bb448fa67c2f0e05f185f61f2e57e579ed;
    uint256 constant IC0y_PART1 = 0x000000000000000000000000000000000a37efbca802e3880ce87dcc6db690a1;
    uint256 constant IC0y_PART2 = 0xeaf147a5fca8847dabbbe07441ee8aa13c0bc9ada73856d601e8d7f132382291;

    uint256 constant IC1x_PART1 = 0x00000000000000000000000000000000149a5573d75aeefc7eb240b79a3b57f0;
    uint256 constant IC1x_PART2 = 0xc2745ba00a7561715dddc56a4b5272fa2f0a334febaa7ccad9fec406989737ca;
    uint256 constant IC1y_PART1 = 0x000000000000000000000000000000000deae6a034a02ca679b51d98b79f487f;
    uint256 constant IC1y_PART2 = 0x1069a8268c293143a06001b663ade1df40eeeb5e256526f034b6cba98d0a24fc;

    uint256 constant IC2x_PART1 = 0x000000000000000000000000000000000e48d1133c34ebba795e725ea0c37035;
    uint256 constant IC2x_PART2 = 0x30de677f25b60e3f1d0d02b2a2eeb77f17819f55743210bcdfb5b7bf62c780f7;
    uint256 constant IC2y_PART1 = 0x000000000000000000000000000000000442fa7cf2cf64da49656b7118d75bae;
    uint256 constant IC2y_PART2 = 0x35441d4e76451b7215c1ac86cb7e7fc2bfa8fb4f79b7aa6b60244fe236e2d4da;

    uint256 constant IC3x_PART1 = 0x000000000000000000000000000000000f70ffa96860d941d587b2f265c28458;
    uint256 constant IC3x_PART2 = 0xfcfa83577bdc8e8caecc9ea42a37d37ff55c66ffc3ecb9b40af7b83f9351c045;
    uint256 constant IC3y_PART1 = 0x0000000000000000000000000000000006f5dda4e08f24914f9a0c6b283270d2;
    uint256 constant IC3y_PART2 = 0xcfb2c13435dfc29aa88e2c13eb7a7a2a18f822b549f04a3b42725eaf3f76b701;

    uint256 constant IC4x_PART1 = 0x0000000000000000000000000000000014de199b3d601280fdadf0c98716835d;
    uint256 constant IC4x_PART2 = 0x59b698dc77a806be0ca06b2c2ae7c47069630e08c13d31d8b32d28199de75915;
    uint256 constant IC4y_PART1 = 0x0000000000000000000000000000000017dc48c3b455be31963d56a960eeb580;
    uint256 constant IC4y_PART2 = 0xb61523ac47e4d1b13ce4e01f13344496c39833518b851fef3fce5b1a614b880c;

    uint256 constant IC5x_PART1 = 0x0000000000000000000000000000000005923f0ce0588c2d2e762cf705aeb22a;
    uint256 constant IC5x_PART2 = 0x2d2b3d51f671a3ecaf6b382033d77ed7d42cd05e508c9aa0329cc2762e81e616;
    uint256 constant IC5y_PART1 = 0x0000000000000000000000000000000019f384b0fc7725878bc3cb664a38abe2;
    uint256 constant IC5y_PART2 = 0x573726869d830a02f7da64b22b541930c7131924cfb45e1697b3122a3280e312;

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
