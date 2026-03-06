// SPDX-License-Identifier: GPL-3.0
/*
    Copyright 2021 0KIMS association.

    This file is generated with [snarkJS](https://github.com/iden3/snarkjs).

    snarkJS is a free software: you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    snarkJS is distributed in the hope that it will be useful, but WITHOUT
    ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
    or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public
    License for more details.

    You should have received a copy of the GNU General Public License
    along with snarkJS. If not, see <https://www.gnu.org/licenses/>.
*/

pragma solidity >=0.7.0 <0.9.0;

contract updateTree {
    // BLS12-381 Scalar field modulus (r)
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    // BLS12-381 Base field modulus (q) - split into two parts for 48-byte representation
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    // Verification Key data - split into PART1/PART2 for BLS12-381 format
    uint256 constant alphax_PART1 = 0x00000000000000000000000000000000047d8672942d1024cd027b51713b9e54;
    uint256 constant alphax_PART2 = 0xa8e6e5fa175805858c1af127b866a7bc6b49a67e15197affb0bfbf7c153b1b37;
    uint256 constant alphay_PART1 = 0x0000000000000000000000000000000013b1c5140bb2186f7e303aded8fbf4cb;
    uint256 constant alphay_PART2 = 0x405290b9c0f6955f7cb5e73900586f69530be0c3c119dfe05be028a5e11c3ecd;
    uint256 constant betax1_PART1 = 0x000000000000000000000000000000000b36b9561c72b9df7e08a1dd72dd85f5;
    uint256 constant betax1_PART2 = 0x1ea3515871d8f6100dff096513ed2602875a80da3bb540d41e9cb993b1990a46;
    uint256 constant betax2_PART1 = 0x0000000000000000000000000000000005917f995bfa07277a16e9c06d85a767;
    uint256 constant betax2_PART2 = 0xa919e606073b42bc2ce44ba863c236ada6d4bccee070fedd40200bbbc3e04384;
    uint256 constant betay1_PART1 = 0x0000000000000000000000000000000018104caac19b3acf229d5830c3f46468;
    uint256 constant betay1_PART2 = 0xe0a6dc2fa2515723fa5ea76c4ea0e3a68dd187c8213e6643a8ef4ef83396b421;
    uint256 constant betay2_PART1 = 0x0000000000000000000000000000000016aa68c746e18577905a22c08caf4eba;
    uint256 constant betay2_PART2 = 0xf78f760257d31822a8cf4a531ca264e505271021dd2ef63b8027d47c84f92f9a;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x00000000000000000000000000000000011e4b99f3b58f5b34b9bd224cfb81fd;
    uint256 constant deltax2_PART2 = 0x9a399817d9073cc7df1913b5f7df69edea5c6dd4ae0a4022543758d0ec982ce7;
    uint256 constant deltax1_PART1 = 0x0000000000000000000000000000000017e06ee938f61940d045317f26975184;
    uint256 constant deltax1_PART2 = 0x6ccfe7a82f28d3db5b705fa9fe68580f13204e8f54f9c356cde9e2cc67f2187a;
    uint256 constant deltay2_PART1 = 0x00000000000000000000000000000000134bc1565fb58e64830001e0356dc256;
    uint256 constant deltay2_PART2 = 0xc519213b8c909c5cc514d40f737c48d3cd19fb736a39deaa9faf4f344adeaa14;
    uint256 constant deltay1_PART1 = 0x000000000000000000000000000000000f71ed3c569dd9c5de7f9a7562fdd0dd;
    uint256 constant deltay1_PART2 = 0x31c9eee54767076646a440d835708923db68907ec9f5ff00a931d4fd9c1b7ef3;

    // IC Points - split into PART1/PART2 for BLS12-381 format

    uint256 constant IC0x_PART1 = 0x0000000000000000000000000000000019a04a9657d01ad9c53981844d1fff72;
    uint256 constant IC0x_PART2 = 0xa0ed855e6e4a8f062a0584a56b27cf4d128ad54a581621ac1462171bbf8d99ad;
    uint256 constant IC0y_PART1 = 0x00000000000000000000000000000000094d4f8525a3d2084f89076c9ee8d225;
    uint256 constant IC0y_PART2 = 0x9fb234e45efb66e3fedd592b19e7e3458560e3a8f3bfde03150a2191e94c540f;

    uint256 constant IC1x_PART1 = 0x000000000000000000000000000000000e7a5047f5fd8c5ea420930f081e540a;
    uint256 constant IC1x_PART2 = 0xb37a1add1add16018b320d5d147a11b184a8a93b3e94295b773b7439f4915136;
    uint256 constant IC1y_PART1 = 0x00000000000000000000000000000000162bdf4de2cde51f309dd5f1afc363ea;
    uint256 constant IC1y_PART2 = 0x794952f0b22d9fbde236f4d3fc98a2b99980f8c00dacc6b3a19070195f7ad51a;

    uint256 constant IC2x_PART1 = 0x00000000000000000000000000000000051d73df51c416d7bae04fc8870aa9ff;
    uint256 constant IC2x_PART2 = 0x54adafbcf590fa6908d751dd314e77a683b20aa6869043f6b1a9a27a20ece0dc;
    uint256 constant IC2y_PART1 = 0x000000000000000000000000000000000d8cce883c17278d94e0d8dca281cd09;
    uint256 constant IC2y_PART2 = 0xf6f723239324b3a0c9688bc8ef3015f5233573fe30c154b100af29459ee3ec5f;

    uint256 constant IC3x_PART1 = 0x0000000000000000000000000000000009defc431707e6989bd235ffbc2d61ac;
    uint256 constant IC3x_PART2 = 0x84c8da0bbfd402229d70dd5381f0f59b83373ff37f36ff3377241e644ff6c1e4;
    uint256 constant IC3y_PART1 = 0x000000000000000000000000000000000a80dcf3370caae4fb6a4ccce191a503;
    uint256 constant IC3y_PART2 = 0x982235e8bc5ea6e7a19fab60e30eef0ce0dfcbe63c627790f47d12eac5c206ea;

    uint256 constant IC4x_PART1 = 0x0000000000000000000000000000000013e4ca1c194f04ce1f6ebe04c6ba4a23;
    uint256 constant IC4x_PART2 = 0x7e6f98c0fcf9ac3cbcf5016d9844cbe6701795d893f1fed07b4b53572796fc62;
    uint256 constant IC4y_PART1 = 0x000000000000000000000000000000000188628c7bbed91f4054df4350658d9c;
    uint256 constant IC4y_PART2 = 0x09a6d6a93f552fd456417cbb38ca4660aaeba636f9250492079df4950766cbea;

    uint256 constant IC5x_PART1 = 0x0000000000000000000000000000000019daaecb6b5f8670d30bf7cc16323762;
    uint256 constant IC5x_PART2 = 0xe146d54baf7f9302c461933482f811b2aa907f9e2efc74cb2aaf74c2f1270d30;
    uint256 constant IC5y_PART1 = 0x000000000000000000000000000000001023149db5938b282773bc5271d1352e;
    uint256 constant IC5y_PART2 = 0x7660854417438fd486c040cb3a08508cfb0ef85baa5492d7989946c2c54020bc;


    // Memory data
    uint16 constant pVk = 0;
    uint16 constant pPairing = 128;

    uint16 constant pLastMem = 1664;

    function verifyProof(
        uint256[4] calldata _pA,
        uint256[8] calldata _pB,
        uint256[4] calldata _pC,
        uint256[5] calldata _pubSignals
    ) public view returns (bool) {
        assembly {
            function checkField(v) {
                if iszero(lt(v, R_MOD)) {
                    mstore(0, 0)
                    return(0, 0x20)
                }
            }

            // G1 function to multiply a G1 value(x,y) to value in an address
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

                // Initialize vk_x with IC0 (the constant term)
                mstore(_pVk, IC0x_PART1)
                mstore(add(_pVk, 32), IC0x_PART2)
                mstore(add(_pVk, 64), IC0y_PART1)
                mstore(add(_pVk, 96), IC0y_PART2)

                // Compute the linear combination vk_x = IC0 + IC1*pubSignals[0] + IC2*pubSignals[1] + ...

                g1_mulAccC(_pVk, IC1x_PART1, IC1x_PART2, IC1y_PART1, IC1y_PART2, calldataload(add(pubSignals, 32)))

                g1_mulAccC(_pVk, IC2x_PART1, IC2x_PART2, IC2y_PART1, IC2y_PART2, calldataload(add(pubSignals, 64)))

                g1_mulAccC(_pVk, IC3x_PART1, IC3x_PART2, IC3y_PART1, IC3y_PART2, calldataload(add(pubSignals, 96)))

                g1_mulAccC(_pVk, IC4x_PART1, IC4x_PART2, IC4y_PART1, IC4y_PART2, calldataload(add(pubSignals, 128)))

                g1_mulAccC(_pVk, IC5x_PART1, IC5x_PART2, IC5y_PART1, IC5y_PART2, calldataload(add(pubSignals, 160)))


                // -A (48-byte BLS12-381 format with proper base field negation)
                mstore(_pPairing, calldataload(pA)) // _pA[0][0] (x_PART1)
                mstore(add(_pPairing, 32), calldataload(add(pA, 32))) // _pA[0][1] (x_PART2)

                // Negate y-coordinate using proper BLS12-381 base field arithmetic: q - y
                let y_high := calldataload(add(pA, 64)) // y_PART1 (high part)
                let y_low := calldataload(add(pA, 96)) // y_PART2 (low part)

                let neg_y_high, neg_y_low
                let borrow := 0

                // Correct BLS12-381 field negation: q - y where q = Q_MOD_PART1 || Q_MOD_PART2
                // Handle the subtraction properly with borrowing
                switch lt(Q_MOD_PART2, y_low)
                case 1 {
                    // Need to borrow from high part
                    neg_y_low := sub(Q_MOD_PART2, y_low)
                    neg_y_low := add(neg_y_low, not(0)) // Add 2^256
                    neg_y_low := add(neg_y_low, 1)
                    borrow := 1
                }
                default {
                    neg_y_low := sub(Q_MOD_PART2, y_low)
                    borrow := 0
                }

                // Subtract high part with borrow
                neg_y_high := sub(sub(Q_MOD_PART1, y_high), borrow)

                mstore(add(_pPairing, 64), neg_y_high) // _pA[1][0] (-y_PART1)
                mstore(add(_pPairing, 96), neg_y_low) // _pA[1][1] (-y_PART2)

                // B (48-byte BLS12-381 format)
                // B G2 point order: x1, x0, y1, y0
                mstore(add(_pPairing, 128), calldataload(add(pB, 64))) // x1_PART1
                mstore(add(_pPairing, 160), calldataload(add(pB, 96))) // x1_PART2
                mstore(add(_pPairing, 192), calldataload(pB)) // x0_PART1
                mstore(add(_pPairing, 224), calldataload(add(pB, 32))) // x0_PART2
                mstore(add(_pPairing, 256), calldataload(add(pB, 192))) // y1_PART1
                mstore(add(_pPairing, 288), calldataload(add(pB, 224))) // y1_PART2
                mstore(add(_pPairing, 320), calldataload(add(pB, 128))) // y0_PART1
                mstore(add(_pPairing, 352), calldataload(add(pB, 160))) // y0_PART2

                // alpha1 (48-byte format) - PAIR 4 G1
                mstore(add(_pPairing, 384), alphax_PART1)
                mstore(add(_pPairing, 416), alphax_PART2)
                mstore(add(_pPairing, 448), alphay_PART1)
                mstore(add(_pPairing, 480), alphay_PART2)

                // beta2 G2 point order: x1, x0, y1, y0
                mstore(add(_pPairing, 512), betax2_PART1) // x1_PART1
                mstore(add(_pPairing, 544), betax2_PART2) // x1_PART2
                mstore(add(_pPairing, 576), betax1_PART1) // x0_PART1
                mstore(add(_pPairing, 608), betax1_PART2) // x0_PART2
                mstore(add(_pPairing, 640), betay2_PART1) // y1_PART1
                mstore(add(_pPairing, 672), betay2_PART2) // y1_PART2
                mstore(add(_pPairing, 704), betay1_PART1) // y0_PART1
                mstore(add(_pPairing, 736), betay1_PART2) // y0_PART2

                // vk_x (48-byte format from G1 point) - PAIR 2 G1
                mstore(add(_pPairing, 768), mload(add(pMem, pVk))) // x_PART1
                mstore(add(_pPairing, 800), mload(add(pMem, add(pVk, 32)))) // x_PART2
                mstore(add(_pPairing, 832), mload(add(pMem, add(pVk, 64)))) // y_PART1
                mstore(add(_pPairing, 864), mload(add(pMem, add(pVk, 96)))) // y_PART2

                // gamma2 G2 point order: x1, x0, y1, y0
                mstore(add(_pPairing, 896), gammax2_PART1) // x1_PART1
                mstore(add(_pPairing, 928), gammax2_PART2) // x1_PART2
                mstore(add(_pPairing, 960), gammax1_PART1) // x0_PART1
                mstore(add(_pPairing, 992), gammax1_PART2) // x0_PART2
                mstore(add(_pPairing, 1024), gammay2_PART1) // y1_PART1
                mstore(add(_pPairing, 1056), gammay2_PART2) // y1_PART2
                mstore(add(_pPairing, 1088), gammay1_PART1) // y0_PART1
                mstore(add(_pPairing, 1120), gammay1_PART2) // y0_PART2

                // C (48-byte BLS12-381 format) - PAIR 3 G1
                mstore(add(_pPairing, 1152), calldataload(pC)) // _pC[0][0] (x_PART1)
                mstore(add(_pPairing, 1184), calldataload(add(pC, 32))) // _pC[0][1] (x_PART2)
                mstore(add(_pPairing, 1216), calldataload(add(pC, 64))) // _pC[1][0] (y_PART1)
                mstore(add(_pPairing, 1248), calldataload(add(pC, 96))) // _pC[1][1] (y_PART2)

                // delta2 G2 point order: x1, x0, y1, y0
                mstore(add(_pPairing, 1280), deltax2_PART1) // x1_PART1
                mstore(add(_pPairing, 1312), deltax2_PART2) // x1_PART2
                mstore(add(_pPairing, 1344), deltax1_PART1) // x0_PART1
                mstore(add(_pPairing, 1376), deltax1_PART2) // x0_PART2
                mstore(add(_pPairing, 1408), deltay2_PART1) // y1_PART1
                mstore(add(_pPairing, 1440), deltay2_PART2) // y1_PART2
                mstore(add(_pPairing, 1472), deltay1_PART1) // y0_PART1
                mstore(add(_pPairing, 1504), deltay1_PART2) // y0_PART2

                let success := staticcall(sub(gas(), 2000), 0x0f, _pPairing, 1536, _pPairing, 0x20)

                isOk := and(success, mload(_pPairing))
            }

            let pMem := mload(0x40)
            mstore(0x40, add(pMem, pLastMem))

            // Validate that all evaluations ∈ F

            checkField(calldataload(add(_pubSignals, 0)))

            checkField(calldataload(add(_pubSignals, 32)))

            checkField(calldataload(add(_pubSignals, 64)))

            checkField(calldataload(add(_pubSignals, 96)))

            checkField(calldataload(add(_pubSignals, 128)))


            // Validate all evaluations
            let isValid := checkPairing(_pA, _pB, _pC, _pubSignals, pMem)

            mstore(0, isValid)
            return(0, 0x20)
        }
    }
}
