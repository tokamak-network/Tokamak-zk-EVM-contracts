// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x0000000000000000000000000000000003577106118d530860518bdcb45c1d88;
    uint256 constant alphax_PART2 = 0x711ec42dc388cd479084d8382496c68a26a16a448726494b32d15d0ddb6b8912;
    uint256 constant alphay_PART1 = 0x000000000000000000000000000000000d25c68be1978da265e86f39131cb9a3;
    uint256 constant alphay_PART2 = 0x81d180ffaf60d2e614f81348e86f3efd62aa37a4c1462bd8f1c6fc7019c7b95b;
    uint256 constant betax1_PART1 = 0x000000000000000000000000000000000af0d89f58a94c6f265601492b48264c;
    uint256 constant betax1_PART2 = 0xa41ec309e7abb1eb4c2202c90d803df0749927022749c6019802563abc346eb3;
    uint256 constant betax2_PART1 = 0x0000000000000000000000000000000013ef6ba706698fdfbc976c899c6bb29e;
    uint256 constant betax2_PART2 = 0x224b7332b4604ede4481546d4a06e79581db36c1b1d44ea3d6be989d22baaf97;
    uint256 constant betay1_PART1 = 0x000000000000000000000000000000000db4b0b3878b9b0ece9542e4007d60ea;
    uint256 constant betay1_PART2 = 0x88831207ecd0e6a77d9684ecee053a0c22908a12250ded26bfd7bd24f8ed57a4;
    uint256 constant betay2_PART1 = 0x0000000000000000000000000000000018f81d43829592b1e61f00c77014a61c;
    uint256 constant betay2_PART2 = 0x04d580f1b221a03864281120e3e74f1b0b8bf526d446e41460cad1dff160320b;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x0000000000000000000000000000000014c171b0bedd2b89a6fd956fcae07f1e;
    uint256 constant deltax2_PART2 = 0x18200d771529fd67a773c41d7cb9616ab839bff8ad3a4ebc5f2aecdbbf9d6673;
    uint256 constant deltax1_PART1 = 0x000000000000000000000000000000001321ece1ba7d3f0ba2ca2e8a40a0d117;
    uint256 constant deltax1_PART2 = 0x824faafd328ff0b9af247707430de0578853a88bfd9e9eeecf81220e296b41cc;
    uint256 constant deltay2_PART1 = 0x000000000000000000000000000000000929ca8c491e17bf9390aaa697dfeed8;
    uint256 constant deltay2_PART2 = 0x1e75fac76c736870beb06d0f73fd222b46911e39e9c45e91e80224703411a8fb;
    uint256 constant deltay1_PART1 = 0x000000000000000000000000000000000be0c19c7591b931a84cb0735d48d5bb;
    uint256 constant deltay1_PART2 = 0x1fc4d2b15eb7d47e6c08b0b307593674fc1c9471e54ec7899498aa09689d6a96;

    uint256 constant IC0x_PART1 = 0x00000000000000000000000000000000014aa0dfd7b4906948160b15c7a718fd;
    uint256 constant IC0x_PART2 = 0xb1cf9027ff7daba090ac625bcab1d06e7e0018b5055d260c3ecb6df87a8b1f0d;
    uint256 constant IC0y_PART1 = 0x00000000000000000000000000000000103a7cb5635246b93318b2440bae242c;
    uint256 constant IC0y_PART2 = 0xb702348848bfd3a3b8e65144f00d8c553357a095fe60cfdf27a82d6a7568eba7;

    uint256 constant IC1x_PART1 = 0x000000000000000000000000000000000d8c53f46e5134248929c6f77c2c9b39;
    uint256 constant IC1x_PART2 = 0x3a6bf8d7e056014af3710c55d39c4247d4a6baea8514987b4de2c1976603344c;
    uint256 constant IC1y_PART1 = 0x0000000000000000000000000000000010f29d0a0a0cd0853dbfb4fc5051895c;
    uint256 constant IC1y_PART2 = 0x69b1ca6734bd27f12cd4ab2c5a9f7aaf5120fb83375fb4b1940442c193d9e83f;

    uint256 constant IC2x_PART1 = 0x000000000000000000000000000000001924ee0bc265c355cf4a334648aeac5f;
    uint256 constant IC2x_PART2 = 0x76fd0d5e47f85b9149e919400e000ac251719383df12541458a5d7c3d7510d52;
    uint256 constant IC2y_PART1 = 0x000000000000000000000000000000000870b27088ec62ff2933d1c396de3fb2;
    uint256 constant IC2y_PART2 = 0x9602ce8f2980273db2a3f0c7cc3f061cabcfd71c88fa45d64f4402a3c8c226c7;

    uint256 constant IC3x_PART1 = 0x000000000000000000000000000000000ff5548ec47d28c1c1eea502e63a9423;
    uint256 constant IC3x_PART2 = 0x150e4191d536fc010a27247e4020b27849558ead55b3c76cca96ee2b7a338bbe;
    uint256 constant IC3y_PART1 = 0x000000000000000000000000000000000ad842323b459cf1d887c13d9b30d553;
    uint256 constant IC3y_PART2 = 0x6d0977fdff269348995407e5a3ca41a2be977f4c1e655d468d61687bfaac6556;

    uint256 constant IC4x_PART1 = 0x000000000000000000000000000000000eac047d565aac19947faba04b9731a2;
    uint256 constant IC4x_PART2 = 0x8f5c22aa00cf75e1b9c3ced48ceeac53ceeab8d115e7d41747087cc3265a5113;
    uint256 constant IC4y_PART1 = 0x00000000000000000000000000000000153580393719b84b846e5c81c4bc439c;
    uint256 constant IC4y_PART2 = 0x980b828cc78769245a4b63f4db1c28368574877d2128eccb8cc22688445801a5;

    uint256 constant IC5x_PART1 = 0x000000000000000000000000000000000db6a9bdff068feff8ede4c70adadd57;
    uint256 constant IC5x_PART2 = 0x799c415f762eb1b3d6a0b73845c185ed66352ed8b64186dfa80787defeeab327;
    uint256 constant IC5y_PART1 = 0x000000000000000000000000000000000d51d57f21a8dd0e9df39fe3e374df64;
    uint256 constant IC5y_PART2 = 0xab0946d23c1547181b35a0fc900a45fd90a599db03ca770aa7ff0ce8944726c4;

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
