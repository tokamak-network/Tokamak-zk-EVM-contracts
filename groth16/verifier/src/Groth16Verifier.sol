// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x000000000000000000000000000000000da5773ab8edc5e7a8db36d52812475c;
    uint256 constant alphax_PART2 = 0x8f9a1fb91a15a1f50ef18eb6c2e54e5520d403c35e387c95eccc67ca7947edc5;
    uint256 constant alphay_PART1 = 0x00000000000000000000000000000000062a8f3627a00769d762f127265bd0e1;
    uint256 constant alphay_PART2 = 0xaaa149b93be728d2e494dcc4f4d6ab39600c73bf1eaa967e58cd5f47c022de8c;
    uint256 constant betax1_PART1 = 0x0000000000000000000000000000000009c81072a587518f78ebe54638560564;
    uint256 constant betax1_PART2 = 0xeb066bf37e71566adcebc1e84acae2b7cfcccc48bc7f0ffff605f5d801715d01;
    uint256 constant betax2_PART1 = 0x0000000000000000000000000000000013f5d9ba683c101af6218775711d4315;
    uint256 constant betax2_PART2 = 0x39102b38e093682eb809fb34a5944399a88c374ba6e701fa13b1170a9bf9592a;
    uint256 constant betay1_PART1 = 0x0000000000000000000000000000000011c26de8757ea63f3c1aeba998cd6973;
    uint256 constant betay1_PART2 = 0x2d38bf8be57d48f56d0fe8470ed040c7f56862fb9b39ac40e15b4f8fafd2a5c6;
    uint256 constant betay2_PART1 = 0x00000000000000000000000000000000014ab7d352cec031593db74bf69690c7;
    uint256 constant betay2_PART2 = 0x27c8179e635006b91d81f4afb2d6dd5b17325251f9597b103df661f22444638f;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x000000000000000000000000000000000c054bf4d4da709e56c4d1eccb101270;
    uint256 constant deltax2_PART2 = 0xf9f559db68b2c52547454e90b349c1e5cf444ba062c453bd289f8da711d9a238;
    uint256 constant deltax1_PART1 = 0x00000000000000000000000000000000124d0600065838dbad8b465aaf6c77f5;
    uint256 constant deltax1_PART2 = 0x2f191c2b0ff0b9d33a4a78edd9cfb65bd30e64c41d932221efd4420fb724164e;
    uint256 constant deltay2_PART1 = 0x0000000000000000000000000000000004f2ca463a6ce4d20c5255921d152017;
    uint256 constant deltay2_PART2 = 0x4560668edf3cac413791369c740a29aa0672eadba9f733ca3648d2ff96734c67;
    uint256 constant deltay1_PART1 = 0x00000000000000000000000000000000190e61d7722057447f1db0920ebb7f8c;
    uint256 constant deltay1_PART2 = 0xa899e5d9e073083e376a6ff2e09662259d798eaa639cec9d2b5a86f94d7dd5a2;

    uint256 constant IC0x_PART1 = 0x0000000000000000000000000000000002435c7d5dbc86f58110db38f1acd73a;
    uint256 constant IC0x_PART2 = 0x6a68491dcecc081e6547a9565287777f47111b6fbd5ae57f5151e357235be906;
    uint256 constant IC0y_PART1 = 0x0000000000000000000000000000000002bc95ca1b04e6df6a77d7aeb54739a6;
    uint256 constant IC0y_PART2 = 0xb0a4b1c849c756cda2c27ebed97c9cb60ca8022af46c70f576a82b0d6caa1647;

    uint256 constant IC1x_PART1 = 0x000000000000000000000000000000000bc5f18f11262b001cee2546ec84995c;
    uint256 constant IC1x_PART2 = 0xb3be609b3f4be9f3f84c111c2d6151523741f39cc09bc008de9779844fe1ebb1;
    uint256 constant IC1y_PART1 = 0x00000000000000000000000000000000019388771f9665ea04194836685dc18b;
    uint256 constant IC1y_PART2 = 0x9f56e37237d02a4550be6be3c7d80bacc47001cd6c7ce9e955dfa2528f9c44d3;

    uint256 constant IC2x_PART1 = 0x0000000000000000000000000000000013fc32a5da28b0665304435395f3c1ee;
    uint256 constant IC2x_PART2 = 0x164330728300339579c7c7ea2478747e30c2e755c54abafc40b2d99d05085b3f;
    uint256 constant IC2y_PART1 = 0x0000000000000000000000000000000000650ad94111ea500bba18e5241cd0e7;
    uint256 constant IC2y_PART2 = 0xf52c988d8dc994f0f4a88f3a9c99c1a51613880c4efe47f769f4c75102282d19;

    uint256 constant IC3x_PART1 = 0x000000000000000000000000000000000de6514f8119318b1724925ff91223c9;
    uint256 constant IC3x_PART2 = 0x8b6b4a84ebf14043115a6632a331ee04f6dd7a51a4ce4ef29b9ba3cd59a67418;
    uint256 constant IC3y_PART1 = 0x0000000000000000000000000000000016fc50bcbd9d3d2c056a74723bf39416;
    uint256 constant IC3y_PART2 = 0x342f0478a7e7350d312a5277e0bbcb91ec4356d872e3acf3c32ee68acc72c94e;

    uint256 constant IC4x_PART1 = 0x0000000000000000000000000000000007b408272cb6427f46299f8ea31bd141;
    uint256 constant IC4x_PART2 = 0xb9a7f4522b3b192cc71ac4ed7ecb8f1e24a70d0b8d2f8f273ee5d11661e3dcd1;
    uint256 constant IC4y_PART1 = 0x00000000000000000000000000000000144e7d33318c75a32145e6f87e7b0427;
    uint256 constant IC4y_PART2 = 0xe4e0468bc6d11fc7025b431ae8043496515f236e7ed5e06132e6e05f61fcdfc5;

    uint256 constant IC5x_PART1 = 0x0000000000000000000000000000000017c5175889dbdd7570c4428727d29dc2;
    uint256 constant IC5x_PART2 = 0x4c50391a923b8a29938a2296e701d770ad5f0e31b6354594c28b49df6c3835f7;
    uint256 constant IC5y_PART1 = 0x0000000000000000000000000000000008a0c1b0d1659589fa0249f7bf317174;
    uint256 constant IC5y_PART2 = 0xd4d647175d5b1d38d8ca510fe8a9b97414457eb6d0e5f1543e89bd4782317f4e;

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
