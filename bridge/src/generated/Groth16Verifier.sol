// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    string public compatibleBackendVersion;

    constructor(string memory compatibleBackendVersion_) {
        compatibleBackendVersion = compatibleBackendVersion_;
    }

    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x00000000000000000000000000000000088e636421aaf62ae9092aa67a214d43;
    uint256 constant alphax_PART2 = 0x2a134580aa3ffe03fe733d5c64e256217f61a77b905a789c0aa592a1712d10f8;
    uint256 constant alphay_PART1 = 0x00000000000000000000000000000000103f5893ff118ce58f5e1401af02b63a;
    uint256 constant alphay_PART2 = 0x3d57640cfef85f180b8e0c3fe655243453e5d30c9dd68b05df2b7ed569c76b37;
    uint256 constant betax1_PART1 = 0x000000000000000000000000000000000a18c5a755d82b5891e52d82f0828e69;
    uint256 constant betax1_PART2 = 0x12ccf219ffa9ec2f16aff510b657097cd0b8b8c92f26c3b1db43d5675c1bbf09;
    uint256 constant betax2_PART1 = 0x00000000000000000000000000000000142a5b9784099a6a5fd024a25d999f8b;
    uint256 constant betax2_PART2 = 0x0c064c9eaed4f7eb86892dc52dbbbe73d5d807ec17b1f1e672d97d59dbd11710;
    uint256 constant betay1_PART1 = 0x0000000000000000000000000000000017e7abb731ae671491d117982f3b51b7;
    uint256 constant betay1_PART2 = 0x17beff4054f6d6537707957f8266ffa2280eeebad944869891378e831c1c66fd;
    uint256 constant betay2_PART1 = 0x000000000000000000000000000000001894c175fd99f8106d355c078f268705;
    uint256 constant betay2_PART2 = 0x62c98cd6f0c3b9cd0b952d2dcec6515f45727389a79017f4beecf6f9d0780d59;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x00000000000000000000000000000000119656bc82b0b6a6ca472992c24335c7;
    uint256 constant deltax2_PART2 = 0x21e66fcb5850dd9e8fb5fc015d9fb0411a546f6bb1c1a3b6062e5412b6d4098d;
    uint256 constant deltax1_PART1 = 0x00000000000000000000000000000000171b54f91b2200c4949e46618b3a62ff;
    uint256 constant deltax1_PART2 = 0x92aa2bd6255548bd27f1dc1b301f7afdb434833fa6018ef7c0fd49c9fdba9bcf;
    uint256 constant deltay2_PART1 = 0x00000000000000000000000000000000117a76837745c3e9f114faed0f6c3f2f;
    uint256 constant deltay2_PART2 = 0xff708cf691f650428b4667f13202936d8a842c853c7205c98aecd7cf2555e2f7;
    uint256 constant deltay1_PART1 = 0x0000000000000000000000000000000012e83973b57b51dd7521ed2b3c6c86db;
    uint256 constant deltay1_PART2 = 0x953cc3040ae669ffbfe6ba99269fd32b1c8f13ff6a4a067d1b7aa41d915e1d3a;

    uint256 constant IC0x_PART1 = 0x0000000000000000000000000000000015b5114c266f9e91f4f9666f5fcb93de;
    uint256 constant IC0x_PART2 = 0xf9781ab8563500c0e13c74c080bbf93bcc8d4a34e6f37dec8475572e7f8dfbda;
    uint256 constant IC0y_PART1 = 0x00000000000000000000000000000000065e9d3c37b79cbc64fa6cb517e1f76c;
    uint256 constant IC0y_PART2 = 0x77a68ac7a9194805322f0e1662a3c445e725027fb53e4c4fd4628b73b4367d0b;

    uint256 constant IC1x_PART1 = 0x000000000000000000000000000000001713519e5ae4457677bcf6d8251068bd;
    uint256 constant IC1x_PART2 = 0x524ee90059c9c5eb603145eef3d0dfc230c52eefa2f0e6143c7ff84c41f9ebcd;
    uint256 constant IC1y_PART1 = 0x0000000000000000000000000000000010bddfef916e1317523f07496af56c15;
    uint256 constant IC1y_PART2 = 0x19af0d6830dc355583cca3cfcbe288235be72f88eced79f29f11842f89602e53;

    uint256 constant IC2x_PART1 = 0x0000000000000000000000000000000016c5161272be3474d5c192c6fd5eae02;
    uint256 constant IC2x_PART2 = 0xb0ee1cefe16b54a737e8ced6b451a259301accc7b544a2e157feba5df112daf0;
    uint256 constant IC2y_PART1 = 0x0000000000000000000000000000000002a6c27085ff59dacccdd0a46d78df2d;
    uint256 constant IC2y_PART2 = 0x497f828004421eaf772be9fe86b74d3da65e4e07d75671c9a77669fcb627f35d;

    uint256 constant IC3x_PART1 = 0x0000000000000000000000000000000008de6c240ca779e86ab78e61e5830edd;
    uint256 constant IC3x_PART2 = 0x354134d660dddf0fa0a160c76890bd4ffdb1aa9fe9ea1d2ff169ab78e19d839f;
    uint256 constant IC3y_PART1 = 0x0000000000000000000000000000000008828919a538b1dda833a1c2a510c184;
    uint256 constant IC3y_PART2 = 0xb5181e18a6b0a3b9ea5241195680d7ee40a02c4b8b49677e6dc0fc7f724f9d1f;

    uint256 constant IC4x_PART1 = 0x0000000000000000000000000000000010821774ee8debd52032b11b00f74923;
    uint256 constant IC4x_PART2 = 0x9c7605f7af426309323a53dc94a46a6453dab23eb4db63b7c46b815331f7176f;
    uint256 constant IC4y_PART1 = 0x0000000000000000000000000000000000a2cb75e930222d86dd9fc89c5da818;
    uint256 constant IC4y_PART2 = 0xcb1a0be28b506aec69fe79043893c8def05dc10eabc2f0f937f15316cca8c4ce;

    uint256 constant IC5x_PART1 = 0x00000000000000000000000000000000095eea9a2f34a03d043a280162bd1377;
    uint256 constant IC5x_PART2 = 0xa9f1482eae6e25105ebe6fa50e27a42124f9631feb7623461c696b7760f9970e;
    uint256 constant IC5y_PART1 = 0x000000000000000000000000000000000d3483c87c85e90d70b48b8937fc9252;
    uint256 constant IC5y_PART2 = 0x7a51233f7325529c3732231dae9eec16c2eaeafb9b0d9fecb1b865dae37ec513;

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
                if iszero(success) { mstore(0, 0) return(0, 0x20) }
                mstore(add(mIn, 128), mload(pR))
                mstore(add(mIn, 160), mload(add(pR, 32)))
                mstore(add(mIn, 192), mload(add(pR, 64)))
                mstore(add(mIn, 224), mload(add(pR, 96)))
                success := staticcall(sub(gas(), 2000), 0x0b, mIn, 256, pR, 128)
                if iszero(success) { mstore(0, 0) return(0, 0x20) }
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
                default { neg_y_low := sub(Q_MOD_PART2, y_low) }
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
