// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x0000000000000000000000000000000018c757ea3e4970cec959797d3fda8f42;
    uint256 constant alphax_PART2 = 0x320416cacd190bb9ccdc59245a798e4d9d4ce787ec4bfc202fc658adf637b4a0;
    uint256 constant alphay_PART1 = 0x0000000000000000000000000000000002328723758dcee326c62ea8f03c8ccc;
    uint256 constant alphay_PART2 = 0xed5ccff6f54a2f401398b54a9a7edd0651655ae319a97cc23762735c3a0b841d;
    uint256 constant betax1_PART1 = 0x0000000000000000000000000000000004fc38813fc78ff40f8d7b10a64606cc;
    uint256 constant betax1_PART2 = 0x0b2c67ce7f1aa6b6bc14b695f79b3d187cde9d0b6231d543d21bdc4f65e0b6c3;
    uint256 constant betax2_PART1 = 0x000000000000000000000000000000000343ebf3133b6dd2c3d59a74b0f69c01;
    uint256 constant betax2_PART2 = 0x549354b40a4bbcd39ada34907d5bc910a8d4188f8a9dbfedd4eda8d39373c4da;
    uint256 constant betay1_PART1 = 0x000000000000000000000000000000000c24aa00700f1769eacd269b5f0d32f0;
    uint256 constant betay1_PART2 = 0x057ab0a347ef72d949a0aecb8efae0275b548fb1de865d818e1b39fe486cdf9c;
    uint256 constant betay2_PART1 = 0x000000000000000000000000000000000fd21948ee15aaaa3f829116ac7f3b58;
    uint256 constant betay2_PART2 = 0x72741a951796429175749c8aaf818337ab0b4ead0ccb15ea7c504b56c57df919;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x00000000000000000000000000000000125a0983ccf65c2efcefc890d0011d4c;
    uint256 constant deltax2_PART2 = 0x5c8b79fa421484ed919477bbfc41d2539c98b4625c0f222629718f7cba274c4c;
    uint256 constant deltax1_PART1 = 0x000000000000000000000000000000001673f4580ae7e32a2bd892cfb2acbacd;
    uint256 constant deltax1_PART2 = 0x2c277616f2e98f72ffb5b5655c698efba17ed1e2da385ed48b4689e60607bc77;
    uint256 constant deltay2_PART1 = 0x000000000000000000000000000000000aa4625be730ce39676b4707fd759eea;
    uint256 constant deltay2_PART2 = 0xe948dc957f009af3222b30fa4fb0744d52e40580f8fd78750f6300b4dbe78dc2;
    uint256 constant deltay1_PART1 = 0x000000000000000000000000000000000796966029c49ab629d5f497493a472f;
    uint256 constant deltay1_PART2 = 0x2d95e1898dfcc177bb1562d92f1a35dfd1131f93f249fd3559477bac5b2f481a;

    uint256 constant IC0x_PART1 = 0x0000000000000000000000000000000005f9d9a4a084952e365d7e6eacee3cb0;
    uint256 constant IC0x_PART2 = 0x17e9ab8af0827a6549ad35f9e231ca05c122b3953a23af4e0e3eb1b097edbcc1;
    uint256 constant IC0y_PART1 = 0x000000000000000000000000000000000c1bfb27f6f53596aeaf05443ebd0a3f;
    uint256 constant IC0y_PART2 = 0x44e05b8d655fccbfe39dc91cc9c1655fb49c80e31470c9eff606515f61fd6d77;

    uint256 constant IC1x_PART1 = 0x0000000000000000000000000000000014b2e13619c07ac6b229bce8149af73e;
    uint256 constant IC1x_PART2 = 0x53fbf67818f571b1f3dc7d5410ab6e14ca2554b7ab77bce942c180a7bfe27318;
    uint256 constant IC1y_PART1 = 0x000000000000000000000000000000000e9fec7c5e5553bef300cb8f9e49d067;
    uint256 constant IC1y_PART2 = 0x6ed698a54c0d29eb76a74fef49968a876532bad9d7b0e791dcd4a5f096b2266f;

    uint256 constant IC2x_PART1 = 0x0000000000000000000000000000000005e297ddf701b3b41bb643057699276a;
    uint256 constant IC2x_PART2 = 0x1a40399fefe5f6aba869b1150131c757e6893435eed1e2156d4f746a1d0c547f;
    uint256 constant IC2y_PART1 = 0x00000000000000000000000000000000045094ecaaf7972d111b823eacfee49c;
    uint256 constant IC2y_PART2 = 0xc5304521a81251b7395155854033769b1984d75d9dd4675e66e30d47e4888e91;

    uint256 constant IC3x_PART1 = 0x00000000000000000000000000000000030a95ed0110d8b21c40d99bd9bbc2e1;
    uint256 constant IC3x_PART2 = 0xd120d6ef6fc34cf0d01c0277c68d642ae27608fe1ab23ba911012dddbbefef16;
    uint256 constant IC3y_PART1 = 0x00000000000000000000000000000000017de5e87a6c0093dd19acc3a700716b;
    uint256 constant IC3y_PART2 = 0xbde70cb69b984400938b6da7ee70834a041e8961d316d0473c096416bda083a3;

    uint256 constant IC4x_PART1 = 0x0000000000000000000000000000000018c7b70820f0fe05330c388791d0d1c3;
    uint256 constant IC4x_PART2 = 0xb85f8ad4a604a97064632b9b7a48f1097e08615bab920ddd28b1586fa1ae13c6;
    uint256 constant IC4y_PART1 = 0x0000000000000000000000000000000001d9ac3090cf722dfcf8adab0ae0ce4d;
    uint256 constant IC4y_PART2 = 0x6d544933454b372ed56756e66b4fbc5c5dc04eaba3c59fc5a8a669ae523f2cab;

    uint256 constant IC5x_PART1 = 0x00000000000000000000000000000000011300a729203dda8d09a5c9f954dd5f;
    uint256 constant IC5x_PART2 = 0x09ccb429548722c7b030742ad855abde1262baf8a8662a6c69c135af97bba04e;
    uint256 constant IC5y_PART1 = 0x0000000000000000000000000000000010ce6b2ce63b3fda590dda7d643912fd;
    uint256 constant IC5y_PART2 = 0xec2f259ac81286032b6217b934a022d1c89bb6b8df3634a4d155196d25322d01;

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
