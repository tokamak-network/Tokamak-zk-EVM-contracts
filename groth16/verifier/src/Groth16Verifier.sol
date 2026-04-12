// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x000000000000000000000000000000001453f5db4749192efcdce6a20b54bc23;
    uint256 constant alphax_PART2 = 0xa45f89735c7fff19fd9eb56bb173feffcdddf656db8d0639b48be875ef0baad2;
    uint256 constant alphay_PART1 = 0x000000000000000000000000000000000619dced60c8b4fe496ba5552c8f414e;
    uint256 constant alphay_PART2 = 0xd20c49dac8f16e0fa3170eeab2c8d7bb955f65ed3e75fadee2604c77e91128cc;
    uint256 constant betax1_PART1 = 0x00000000000000000000000000000000043dc3c189977b9ea59645f21ca490f4;
    uint256 constant betax1_PART2 = 0xe371232d477dcc9fd1b0184becf7a9fc36fa7de1a8a02b82a66df54c81a9bbe7;
    uint256 constant betax2_PART1 = 0x000000000000000000000000000000000f5c3fd4ccbc9a5622b5f742e42faf3d;
    uint256 constant betax2_PART2 = 0xeb71d5023cdeb080bb1d77376dabbabfbead474304354921adbb417f11384709;
    uint256 constant betay1_PART1 = 0x0000000000000000000000000000000003da6d9b74da99eba20a9050f076f179;
    uint256 constant betay1_PART2 = 0x146b4e18ade6495bd9039f12980354c690f6f40baf3d93e6e4647281c0cd10ca;
    uint256 constant betay2_PART1 = 0x000000000000000000000000000000000623e7c6ca1bd7bb196b8ee60b4eeb68;
    uint256 constant betay2_PART2 = 0x9f37554c8c5ab61958c38b4ad3e532a532ee9f312a6980d41f0b87298812a630;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x0000000000000000000000000000000013529bed030c71252342f030494484f1;
    uint256 constant deltax2_PART2 = 0x3e79c85881f6e8298203d1743a6038b41799521a4c6438e1f040a2f2d656f7fa;
    uint256 constant deltax1_PART1 = 0x000000000000000000000000000000000f20067d63824a566c3266a4060eb36c;
    uint256 constant deltax1_PART2 = 0x3b0b5b97feab7013c71fb3158dae645e66d8151da687e54ced273a5588ef136b;
    uint256 constant deltay2_PART1 = 0x000000000000000000000000000000001264ef4094360de99da690ae15252a98;
    uint256 constant deltay2_PART2 = 0xc7ff60c30fbf0f2d62a136b43b43d9416b8fd4f925f4aac1cc92ff8760b0f275;
    uint256 constant deltay1_PART1 = 0x0000000000000000000000000000000018d9be63922232f055ba847be931d4d8;
    uint256 constant deltay1_PART2 = 0xb450e7db5a7d2b33ba6c85fadec910f3dac7e04bfea3eddac94a086722071187;

    uint256 constant IC0x_PART1 = 0x000000000000000000000000000000000df9148bf8b0fa6db798e4a17c153cd0;
    uint256 constant IC0x_PART2 = 0x4e46ae66224627f6c2e4f383fd19be53f8b8ee853c5935c27888dce4c8db8ce8;
    uint256 constant IC0y_PART1 = 0x00000000000000000000000000000000069011fb37bb1ab6341c336cd3cbb8c4;
    uint256 constant IC0y_PART2 = 0x7e1221cdb9eed0a0be3ef6f17693fb1bfcefea6f38c13225bbe33d4d1ce24627;

    uint256 constant IC1x_PART1 = 0x0000000000000000000000000000000019ed89d7596b747481ab339239ccd10b;
    uint256 constant IC1x_PART2 = 0x9a1a313c0fcc08b77aab9cc372bf33587deb41050861dd76a670380e0f51ee66;
    uint256 constant IC1y_PART1 = 0x0000000000000000000000000000000004ac2fe5cd71aba5bf38efa7ff34de57;
    uint256 constant IC1y_PART2 = 0x022832bb235d8f1f808156e9011617aba7be699f1392fc667ca9a2ab797211b6;

    uint256 constant IC2x_PART1 = 0x000000000000000000000000000000001371e6958f7d0b61697e0efd07acdb41;
    uint256 constant IC2x_PART2 = 0x9ca47c83b7f6eaac8f4c271f941a2b872f51977650aa2ba917662be90ac2b8ec;
    uint256 constant IC2y_PART1 = 0x00000000000000000000000000000000124e7ec451e7ab554f51f1d4e6d19d5c;
    uint256 constant IC2y_PART2 = 0x9e900fbe257943be663fdffc44808424e3514f0bf69368ee23dc26057930a61a;

    uint256 constant IC3x_PART1 = 0x0000000000000000000000000000000009fd6cee857b60f6b0e71292b67ccf40;
    uint256 constant IC3x_PART2 = 0xf65d084d2db1054588b112a48d2ff30edc250d4a57364e3131c49ce5ae7a1f73;
    uint256 constant IC3y_PART1 = 0x00000000000000000000000000000000140c24dab660e780186c52756d39fa31;
    uint256 constant IC3y_PART2 = 0xb36a1c36a8f3d3bf8efc1d634fc9ad4bb5d40d2a3bb1677bde50b47265483e77;

    uint256 constant IC4x_PART1 = 0x0000000000000000000000000000000006d33ee064da1a0262c440a9886fe981;
    uint256 constant IC4x_PART2 = 0xc41fd0240b0ea54a12df3e79e80ee448ea1f19c212bcfaea3f9870d9c9c699d5;
    uint256 constant IC4y_PART1 = 0x000000000000000000000000000000001101e2d599820c2091238e9b0cdddda5;
    uint256 constant IC4y_PART2 = 0x296feefe50a919e5450d834af5b0c606fe6decb9b380628dbe84cf438be767d0;

    uint256 constant IC5x_PART1 = 0x0000000000000000000000000000000009401a566aa17e26fbc827f699d55c05;
    uint256 constant IC5x_PART2 = 0x961e7a656720a43a72d438841799ad737f45ba6391741a0a7e3d336df3406804;
    uint256 constant IC5y_PART1 = 0x000000000000000000000000000000000da2fdbedb2aa4c34a96437fc49aba34;
    uint256 constant IC5y_PART2 = 0x67878ee5be7207a379adfc63d37bed37cb936107eb789a1ca4e80669e20d1416;

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
