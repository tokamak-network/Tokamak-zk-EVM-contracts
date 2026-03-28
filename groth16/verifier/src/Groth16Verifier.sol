// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x0000000000000000000000000000000005382ecdf6602bd4f3d37b9569d90b2c;
    uint256 constant alphax_PART2 = 0x04ca7f8848dc35b71927ea336e5137d334d3cf6582a7aa580201b83df03da864;
    uint256 constant alphay_PART1 = 0x000000000000000000000000000000000991a38cb20e444f0c6108aa1ae0c956;
    uint256 constant alphay_PART2 = 0x476cfac4e614571156b816b49253740b8768fa2219b266baca50e9e326a8e4ab;
    uint256 constant betax1_PART1 = 0x0000000000000000000000000000000019a141e89610e3c9bfbd2d62c04c5ce5;
    uint256 constant betax1_PART2 = 0x7bea738bf89e514badb71e6b8710ccf6eb2a14dcb6fb991bf665f608b064639d;
    uint256 constant betax2_PART1 = 0x00000000000000000000000000000000182f97916bace0cd9b5a75eb93bc8e8e;
    uint256 constant betax2_PART2 = 0x46d7b696fda04d27b8a58f96c4e801ef885c5983f7ccd3ab4ea697d134032104;
    uint256 constant betay1_PART1 = 0x0000000000000000000000000000000007abbbbfc9f2150433424bc09da9df18;
    uint256 constant betay1_PART2 = 0x49857a974526f2e38f6249b7eef23b50394dd917945dac769df703b93eec8a09;
    uint256 constant betay2_PART1 = 0x0000000000000000000000000000000003f3bcebc49865f3ad6427d7b83e55ca;
    uint256 constant betay2_PART2 = 0xacf0e7eff2a5c784eb7d3c2cd9108da1b46a8292a1f430d82ae2c06544ab02c4;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x00000000000000000000000000000000166824e8ab68eadec7968c76aa48f9fa;
    uint256 constant deltax2_PART2 = 0x41917b9a9f2f335feadad4c8c1c359cd7c557d94b69b6bba812f129481483c66;
    uint256 constant deltax1_PART1 = 0x0000000000000000000000000000000009e2c3a9a9b2f100910f7344a01e866b;
    uint256 constant deltax1_PART2 = 0x3cbc20115df32fe8fecae9873cf693133dcb44972cc3e82d8ed4abd5c70cdd6b;
    uint256 constant deltay2_PART1 = 0x000000000000000000000000000000000eb371b0f1496bb05483b4aae43dc9df;
    uint256 constant deltay2_PART2 = 0x00a9370a68ab05afa76286e3b9719aaefbc4154d3014545ce45ebac70370d209;
    uint256 constant deltay1_PART1 = 0x000000000000000000000000000000000dea697532da87e86a438aa5bbf432f1;
    uint256 constant deltay1_PART2 = 0x35fb018daeac1e50b5ddcb6868d4b8ebf1bae9e5e20b4e5e39b15c7efd750ef0;

    uint256 constant IC0x_PART1 = 0x00000000000000000000000000000000098d246d97ac5a833acd0e553bb3044d;
    uint256 constant IC0x_PART2 = 0x540ac2b97e7f201addf305b9d5820069b7a3498bc6c1a7c64abfeb4ad23b9f42;
    uint256 constant IC0y_PART1 = 0x00000000000000000000000000000000147fabcaa293fa27c7b87818400528f8;
    uint256 constant IC0y_PART2 = 0xa21d2dfe72d7b2393539f172f967b6aea7bbb10fd9916faf788f0c80b3df3ad8;

    uint256 constant IC1x_PART1 = 0x00000000000000000000000000000000166af0abf1cac9cc3fa47e091b290a28;
    uint256 constant IC1x_PART2 = 0xf83d20fb5109c81ee225e90d73f3bd13ff1fa8e5802ef3d982bbc133ff1ff48a;
    uint256 constant IC1y_PART1 = 0x000000000000000000000000000000000923128040e47fd558a3f8cbe9af9541;
    uint256 constant IC1y_PART2 = 0x95856da2fddd2197ae67f7ca9789171ff24d9262f6e7503b7f7d11103674901f;

    uint256 constant IC2x_PART1 = 0x0000000000000000000000000000000004ffcb561794963bb99a4cfbe4ee02db;
    uint256 constant IC2x_PART2 = 0x6d817bec7d5924211db6f5ea4e528312b987660a97935940210c39085c40b671;
    uint256 constant IC2y_PART1 = 0x000000000000000000000000000000000fb14fb1d3f6b19adfd11709253d1dc0;
    uint256 constant IC2y_PART2 = 0x7c3bc80ff474e1477af610d251513c1be39b6ff086134f6f9ae97e2437c03568;

    uint256 constant IC3x_PART1 = 0x00000000000000000000000000000000174cf4959f888dc81308d6798d1b32c4;
    uint256 constant IC3x_PART2 = 0x7d17afe10e4e935059d1b0c91d071231812917ee7d23b94db3fbcf03fed96819;
    uint256 constant IC3y_PART1 = 0x0000000000000000000000000000000005787a60e3188ca1887b79f1b621bc0d;
    uint256 constant IC3y_PART2 = 0x02bb5dabe61cf4a8ab3ba2b003313d0ae3241f41eef06719b5cda32a7a633669;

    uint256 constant IC4x_PART1 = 0x0000000000000000000000000000000018870b530e01944aebd6447671c6b5d3;
    uint256 constant IC4x_PART2 = 0xf8d80b082e412b3dde1472ca11669c9cbb2bf967af3dcb79b55454cfdfd28089;
    uint256 constant IC4y_PART1 = 0x000000000000000000000000000000000ec483ffb6cf8e304ab3d13e3aa52d53;
    uint256 constant IC4y_PART2 = 0x1d40b581e5145f970c680dc5957fd96a224b76400b380e4e2e752a16f02f4215;

    uint256 constant IC5x_PART1 = 0x0000000000000000000000000000000003c2b22c11c9b0131a7f6c6c0d85aba3;
    uint256 constant IC5x_PART2 = 0xa46b6e73eec0730263d64bf2cfab8731b5d9a1f176e0f30f7311f9d9fec6bbf5;
    uint256 constant IC5y_PART1 = 0x000000000000000000000000000000000ed19ee9328965547ea1f919febd7d3f;
    uint256 constant IC5y_PART2 = 0xbdd26113c2ff6bdd2db9bab0d846936c8ed69d07499093d14a068cc33e1423bd;

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
