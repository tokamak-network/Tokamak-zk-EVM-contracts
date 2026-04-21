// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x0000000000000000000000000000000011b32582e99e4c63370dfa26d698547d;
    uint256 constant alphax_PART2 = 0x7113a1bea9537c5f99f0c6e9c31a61fc1b32411302cb6920b54d97a9ee037276;
    uint256 constant alphay_PART1 = 0x000000000000000000000000000000000c25e76aa3640f07bba1660754fa8339;
    uint256 constant alphay_PART2 = 0x69e9321c4cb58355dccf90429ebf94599b1037bfce830eed167ed3257939ea59;
    uint256 constant betax1_PART1 = 0x0000000000000000000000000000000017cd486125e55b2fdc9fa475b22f8c35;
    uint256 constant betax1_PART2 = 0xf89c706cb2d68f4b7a6561e3810521037609085419a7b4f3d2c1bd05d4e75b59;
    uint256 constant betax2_PART1 = 0x0000000000000000000000000000000004b574a8c6b5088f0572d00ab0d9fddc;
    uint256 constant betax2_PART2 = 0x2f48f025fbf99a125eac518b1536e69711a6eea9de6cf01831b79d21773c0516;
    uint256 constant betay1_PART1 = 0x000000000000000000000000000000001530537bdb4499b25dbd4377c79f1bab;
    uint256 constant betay1_PART2 = 0x17d564e59e4214b8367262c5e3722d62d692696bbf0be8cc8068c01cb0ebb431;
    uint256 constant betay2_PART1 = 0x000000000000000000000000000000001903ff1154591a18a3f1c0982c79805b;
    uint256 constant betay2_PART2 = 0x22f0b88d55afc2b83bf6b69e61f071f33a93aaca3d9d6feea2c3b9babfe8aabd;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x000000000000000000000000000000000a8b30e20b5342d4815d907019bbf383;
    uint256 constant deltax2_PART2 = 0x69b2f966f55fa78cfe3bc60163e8f2a158c27f8c7697db82cf8ec7c1ca9c1613;
    uint256 constant deltax1_PART1 = 0x0000000000000000000000000000000000952f686a086eb55ccad18559321b47;
    uint256 constant deltax1_PART2 = 0xd0f0972d43685a2367816d503e9dda4de6fc38b580fba7192258ffc362d7b614;
    uint256 constant deltay2_PART1 = 0x000000000000000000000000000000000b853a54a9709961fa98ebddcf94a02b;
    uint256 constant deltay2_PART2 = 0xf827bb4d4b63cf4b5994bbe7762716b7530c0c5fd798e8596b055bc92b360d0d;
    uint256 constant deltay1_PART1 = 0x000000000000000000000000000000000dcf6ca155c64e48da0629a4982e015e;
    uint256 constant deltay1_PART2 = 0x8fd60016f9ee79c698198f6eb32b170d5d94f4be72e70bc077500ee2a4d7aa3a;

    uint256 constant IC0x_PART1 = 0x000000000000000000000000000000000524febc3710d13ed0b01bcc91483ba4;
    uint256 constant IC0x_PART2 = 0xf2a9890c669814f06e88cf3421cbd3f11eff3d256b933661c01d49060c5ed241;
    uint256 constant IC0y_PART1 = 0x000000000000000000000000000000000171fa4234485a85b0031aca3a192386;
    uint256 constant IC0y_PART2 = 0x257dd60377142b05ea9b4bd7bf04ad4439646ac578376887fa7f1d2b16553ab4;

    uint256 constant IC1x_PART1 = 0x0000000000000000000000000000000012dc1798fa76770f1c1122dcbb9cca2b;
    uint256 constant IC1x_PART2 = 0xc4d615548adcf26398a698cb16e35b2469766aaba2fe620f12fc147d782e7543;
    uint256 constant IC1y_PART1 = 0x00000000000000000000000000000000031356246e4cd06a73e9646f553d0cca;
    uint256 constant IC1y_PART2 = 0xd5724b0e8297979b06661bd49ee005a383d59f9c751ad9c3531cfc81ddeb1cf1;

    uint256 constant IC2x_PART1 = 0x00000000000000000000000000000000165eab59c83ee66d2879541a01ccb43f;
    uint256 constant IC2x_PART2 = 0x8b1b736fa90bb65a53c9cd61c3f1b299b655ca3cab58f3a2dbdcc370ba2fc437;
    uint256 constant IC2y_PART1 = 0x0000000000000000000000000000000019a17a9791693cca3aaef6a2f711e670;
    uint256 constant IC2y_PART2 = 0x5f0cd3f9bed458ba444e2ccd540cb2576052a49fb5fa582fd2a9d8596193484e;

    uint256 constant IC3x_PART1 = 0x00000000000000000000000000000000119e7f933d5ac6b0ae1dc905b804f968;
    uint256 constant IC3x_PART2 = 0x5762636fd814359dfb7d18b4434cc6fd1a4f9e158d375aa587697ff9e18279b3;
    uint256 constant IC3y_PART1 = 0x0000000000000000000000000000000014cac96504284745019f15d2c1bc7f02;
    uint256 constant IC3y_PART2 = 0x1f453817c394e718b6bc254642048a6af5ccd79b62f1c39f729e019355fb157c;

    uint256 constant IC4x_PART1 = 0x0000000000000000000000000000000005ffc7b0d141b2aebb86f709aa26dd1a;
    uint256 constant IC4x_PART2 = 0x084bc72ad74c4d4ff8d39f53cd055c95c4ba6864a09e17b265c22b0bceece1dc;
    uint256 constant IC4y_PART1 = 0x0000000000000000000000000000000008f034df325a19dcdfada607bfb1ad87;
    uint256 constant IC4y_PART2 = 0xdaf13db1ffbb3c428b8c1030dd78af38b9a8c1abd5548817d36cc1d4e7f30b8e;

    uint256 constant IC5x_PART1 = 0x0000000000000000000000000000000001385c5360375a48c005f30f2a1f7d76;
    uint256 constant IC5x_PART2 = 0xc7c32e979cbad0c99e5f80a6df5848bbc3fbfe1f0ce68f45ce5a372078d9490f;
    uint256 constant IC5y_PART1 = 0x0000000000000000000000000000000010771027bf4efb5b219f2cd2696667a5;
    uint256 constant IC5y_PART2 = 0x12f0540a16c8a8b0cb70087e8d0422896791a85b47eb17609c7d5c3232008197;

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
