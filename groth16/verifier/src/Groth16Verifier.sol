// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x000000000000000000000000000000000644be7b49e690ada88aaac79f010919;
    uint256 constant alphax_PART2 = 0x8f1aff2a91c1e3f84154b00f618418df580aec3584baef5209e631c18f713c4c;
    uint256 constant alphay_PART1 = 0x000000000000000000000000000000000c4b637d5f6c50b32a670789763dfe56;
    uint256 constant alphay_PART2 = 0x5f09fa018a50402ad68bb49fc32d7162ca3f2abfc054f0557d0d70547c6e2846;
    uint256 constant betax1_PART1 = 0x0000000000000000000000000000000014448caf80e104bbfec465592a199568;
    uint256 constant betax1_PART2 = 0xf7ad6394f9b1100db584a97a1e5ac3f7c7d8084908a7756dbcff983d4ae4eb62;
    uint256 constant betax2_PART1 = 0x000000000000000000000000000000000bb3071a4ec137f25a38ce8a20d992c4;
    uint256 constant betax2_PART2 = 0xe33dadd56a3bf718c01e869cd95ef8542b742cd7ddd2f6571136e6c70e371a12;
    uint256 constant betay1_PART1 = 0x000000000000000000000000000000000f374a0d809f35e977c4f3ca3c92c1c9;
    uint256 constant betay1_PART2 = 0xaa86e51f9b1ab443cf19c1d1dbe7b3ee3fd6a14072a380a6d2a386787f842116;
    uint256 constant betay2_PART1 = 0x0000000000000000000000000000000004d90f988db05fcbff547df108c0d931;
    uint256 constant betay2_PART2 = 0xa6496f7b8015142ceb4a0ea3c165e8d58d34c42834999563f6393c3ab3ab2c10;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x000000000000000000000000000000000afd75e85d829e31d62bb6171953f773;
    uint256 constant deltax2_PART2 = 0xa1dcea6fb2b2a8038e56de8e8545667b76820e7b078036db9d89d6b44145186d;
    uint256 constant deltax1_PART1 = 0x0000000000000000000000000000000001bd962fe470f24b54fa630499723d7b;
    uint256 constant deltax1_PART2 = 0x4ffacbec42915eb86f4abcd60430c097f4c74ac0776700a2604422b24cf484d1;
    uint256 constant deltay2_PART1 = 0x0000000000000000000000000000000008d335ae8a8193db7c49b0e67718b3b9;
    uint256 constant deltay2_PART2 = 0xa90d0a1baa7160acbb60e6a6e800208dbb8f9426a0e68479074da12618b4990b;
    uint256 constant deltay1_PART1 = 0x000000000000000000000000000000000421be05dcf46be550478dd6ae036e56;
    uint256 constant deltay1_PART2 = 0x8907eb20a2f9a32e34914c3bc05aa3dc70916019875ce323f9c4a200cc68883c;

    uint256 constant IC0x_PART1 = 0x00000000000000000000000000000000044060c432c63760bd095d75169a990b;
    uint256 constant IC0x_PART2 = 0x152546f2b85259a112965a62bc7155ce35bdd463fe7ba498292d2b84a133915f;
    uint256 constant IC0y_PART1 = 0x0000000000000000000000000000000015c54a535e122d4a85b3957b5a151ed6;
    uint256 constant IC0y_PART2 = 0x14f7ddf8f2e7ddba904532030c9bcd87e56cccf05d1244b49448bc3e670c7095;

    uint256 constant IC1x_PART1 = 0x0000000000000000000000000000000004f8a65eb31f1030a55b8c71e40252fd;
    uint256 constant IC1x_PART2 = 0x322b052cc7229f56b09613dc08fd9e628f849fc12c148ca0916c0a75ba3bdf2c;
    uint256 constant IC1y_PART1 = 0x000000000000000000000000000000000610b73a2f9b9d0336b52fdc8142ec3c;
    uint256 constant IC1y_PART2 = 0x473fa710d082761e23018286b22c57918ed13a0cbfc7a37ff65e52384f9c326f;

    uint256 constant IC2x_PART1 = 0x000000000000000000000000000000000d27d02e4a063baa86e99432443d60fd;
    uint256 constant IC2x_PART2 = 0x08f4bbe62b0bdfc66f76046d59b3699491593ea99f35b6b248218b315733bc82;
    uint256 constant IC2y_PART1 = 0x0000000000000000000000000000000002734d7b626f77f2d3a451450fe93736;
    uint256 constant IC2y_PART2 = 0x596bef9ea25b7b7f41963b7bb463cc7f86594326dde564048726570bdc29a9a9;

    uint256 constant IC3x_PART1 = 0x000000000000000000000000000000000b145e4560cee884cbe1506faee7ead5;
    uint256 constant IC3x_PART2 = 0xafc8010cf086aad9579a2a10d849a4a7de06125ff7774dfda8c061c835da6b66;
    uint256 constant IC3y_PART1 = 0x0000000000000000000000000000000006c73d57053093d4d8af14ef8bb5d91b;
    uint256 constant IC3y_PART2 = 0x41ce9daa7c8a4b7877af7ceb02f20e38d65c12af5ea21c05350e3dfacf57bb3f;

    uint256 constant IC4x_PART1 = 0x000000000000000000000000000000000995377d8dbb12c263a491915d762a1c;
    uint256 constant IC4x_PART2 = 0x42e207af9dc0608b23e0f2f29d25fd6227c6db3e0b7254b834263e818f362d00;
    uint256 constant IC4y_PART1 = 0x00000000000000000000000000000000012bb3ee1935d53040deea3e951208c7;
    uint256 constant IC4y_PART2 = 0x5539d5b91e769997b2b7deb68512e1014412998c2afd35dca535dc70ed72d0ec;

    uint256 constant IC5x_PART1 = 0x0000000000000000000000000000000016b6177902e6ffe7614e1b48b6e88181;
    uint256 constant IC5x_PART2 = 0xf0f0b85e8b32f5afe9a6022e84774f4ef690e0a8d682933cda5f219d2a478c2c;
    uint256 constant IC5y_PART1 = 0x00000000000000000000000000000000049b14ac7101b42144ea9da7b7a1ecfc;
    uint256 constant IC5y_PART2 = 0x80a5ecd3a4b92ca536a2c51e6d052d684da313cd34f132199c951352760ffe5a;

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
