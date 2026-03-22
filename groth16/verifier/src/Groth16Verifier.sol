// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x000000000000000000000000000000000069d27056c3de0189c5efe2305d6c24;
    uint256 constant alphax_PART2 = 0x5afbbd2883572e71cb807a01d4f377c265b1ef6c6d88d5eec8ca04b25119addc;
    uint256 constant alphay_PART1 = 0x000000000000000000000000000000000d507e87b936fc27eb759ba589dc9ec5;
    uint256 constant alphay_PART2 = 0x369f37026070bda0a6d630c78c1b6a2add50c123f9ec0ed91bf69a0691be7d00;
    uint256 constant betax1_PART1 = 0x0000000000000000000000000000000010495c3ba62dd9735d79b4420a9e1d03;
    uint256 constant betax1_PART2 = 0xb5476e7ade4af625929cc788e3b11c568dd41a4d81c7516405ca3280e3b72659;
    uint256 constant betax2_PART1 = 0x000000000000000000000000000000001633666aaa0e0fae466227dea208679a;
    uint256 constant betax2_PART2 = 0xdf9e04d265521cef374965848d99bec2dc9566b0ea5c30ef48cdae48972b22de;
    uint256 constant betay1_PART1 = 0x000000000000000000000000000000001182a8cd9b05e719fc84863ee6fcb0c9;
    uint256 constant betay1_PART2 = 0x83187c3857448b353fe89a279b03f0337e60c4eecec2f6c278e278943a3ad385;
    uint256 constant betay2_PART1 = 0x000000000000000000000000000000000a012a908537539a2f90053b7d04aa9e;
    uint256 constant betay2_PART2 = 0x9e11d0b660fc6b8d8a6c9178f65fe4fd08eca34e05efc5b0b547dee8fcc61082;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x0000000000000000000000000000000013062e01db095f335d42d1a5765c250a;
    uint256 constant deltax2_PART2 = 0x2a79a9d399de9b42424dc16e4a2e21522269ee062093cc8ae2d8a3e196e7fbde;
    uint256 constant deltax1_PART1 = 0x0000000000000000000000000000000007d6e9e9797f2b9a91287dd1ddac1316;
    uint256 constant deltax1_PART2 = 0x6d58fe521160e87cc35d1795d45ede51860315aca728b856663dd269fc050482;
    uint256 constant deltay2_PART1 = 0x00000000000000000000000000000000057d6da783488d4f567bbb93e43bfe88;
    uint256 constant deltay2_PART2 = 0xa5f8c359a706e0fe8938d43a6df697a7b2fdc8add4a8eb96e4d3c19a7ae3bd22;
    uint256 constant deltay1_PART1 = 0x0000000000000000000000000000000007c3a197f439cc6449105390f5301471;
    uint256 constant deltay1_PART2 = 0xd0e4d32640e230e197f268ee4df5fcd054762d41829231a391a941265ddec3fe;

    uint256 constant IC0x_PART1 = 0x000000000000000000000000000000000526e80ce6215ac7c92306c3aa6a8d1f;
    uint256 constant IC0x_PART2 = 0x44c4da5c929861130f958ff7fc9b48eefe3db35dba9e132fa91c89fda77f3062;
    uint256 constant IC0y_PART1 = 0x000000000000000000000000000000000965183a876839e5e980bf1bc75c68ae;
    uint256 constant IC0y_PART2 = 0x7d9af3d576178ea28aa6331fdc8468ee6762ce4c8c08a3365a480390bddf8606;

    uint256 constant IC1x_PART1 = 0x0000000000000000000000000000000017e9782335bc0b85161a64c4970ae236;
    uint256 constant IC1x_PART2 = 0x9f503b750151e12f72afd756eedc1b03dc9c628c276a1b14df7d6309a25c0429;
    uint256 constant IC1y_PART1 = 0x000000000000000000000000000000000fd33c98d1b9ca5ce7872eff96ab776c;
    uint256 constant IC1y_PART2 = 0x4b3137c4952d7c0c28f245c7576bff1051164bee4dc0013920d3f63ec49e7910;

    uint256 constant IC2x_PART1 = 0x000000000000000000000000000000000c993722e083c842bac32f1f20b252fa;
    uint256 constant IC2x_PART2 = 0xd632c745390c5206927cd317e8af39f56a0b09605bd5099d8328eceaf6a1e9e9;
    uint256 constant IC2y_PART1 = 0x000000000000000000000000000000001010d4f6fda9dce506055645026ebb93;
    uint256 constant IC2y_PART2 = 0x7121b26545af598d228ff4030273836a4e69f3fa20eb58069b7dba0e865879c6;

    uint256 constant IC3x_PART1 = 0x00000000000000000000000000000000042f192447d9c319d809e9908593588c;
    uint256 constant IC3x_PART2 = 0x8090ea65e8f656f44f7e08d4d2ac2b3d5224e236f3edb645f9bffeff7f0cedea;
    uint256 constant IC3y_PART1 = 0x00000000000000000000000000000000156f24d781305b17cf6658ff42f5bc30;
    uint256 constant IC3y_PART2 = 0xb71fca158a89e0f532431d5840fe584693dd5531186a9f42e0fc51842822a3f4;

    uint256 constant IC4x_PART1 = 0x0000000000000000000000000000000006145eaf57951c96586b6696e57c2dc3;
    uint256 constant IC4x_PART2 = 0xe6eb5c06c6cb0ef5c342c14ceab441359249cf634aef210bd8e4bc3a22230dc7;
    uint256 constant IC4y_PART1 = 0x000000000000000000000000000000000f89ac5dd76054088df9a6010c7a33e8;
    uint256 constant IC4y_PART2 = 0xd58da817586dc69dde118361187381133d54d6e1e401d636766d3186be74da89;

    uint256 constant IC5x_PART1 = 0x000000000000000000000000000000001795790bfec0b4fa556883185014cdeb;
    uint256 constant IC5x_PART2 = 0x0b11a7764c59d48d159385f914a22c15098c754367f5d235f17f4cceb2a92aff;
    uint256 constant IC5y_PART1 = 0x000000000000000000000000000000000b96b9fb394382251a91aa39fbd417f6;
    uint256 constant IC5y_PART2 = 0xdba8664e64d0d3375a07196f0dc92c19a79c1c4db2c9a742990a8cd1f5220ea7;

    uint256 constant IC6x_PART1 = 0x0000000000000000000000000000000019a34e2214eea510e3545742c744c090;
    uint256 constant IC6x_PART2 = 0x851693d3a6ef4648b3e13040e643f9fc004123f781ba6c86cdec2a24ee62d908;
    uint256 constant IC6y_PART1 = 0x000000000000000000000000000000000ccc041616d127cc839aee2d45b0bcd1;
    uint256 constant IC6y_PART2 = 0xf17abadb1a2667f46f3beb10f8c210bb7b5042234169edb8c940b3132e59a951;

    uint16 constant pVk = 0;
    uint16 constant pPairing = 128;
    uint16 constant pLastMem = 1664;

    function verifyProof(
        uint256[4] calldata _pA,
        uint256[8] calldata _pB,
        uint256[4] calldata _pC,
        uint256[6] calldata _pubSignals
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

                g1_mulAccC(_pVk, IC6x_PART1, IC6x_PART2, IC6y_PART1, IC6y_PART2, calldataload(add(pubSignals, 160)))

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

            checkField(calldataload(add(_pubSignals, 160)))

            let isValid := checkPairing(_pA, _pB, _pC, _pubSignals, pMem)
            mstore(0, isValid)
            return(0, 0x20)
        }
    }
}
