// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x0000000000000000000000000000000004feddb33e239f0d783ab968827b0858;
    uint256 constant alphax_PART2 = 0x38771f23fd00a534c86461b9556ab1b18fabb51ff8feee388c81211fa1a94a52;
    uint256 constant alphay_PART1 = 0x0000000000000000000000000000000008424d72e139ce75ec87163f65fe5e7c;
    uint256 constant alphay_PART2 = 0x20f0d5b1b82769b7f46a7f3fb2d36582e97a9d3ee9c6e84aa58722cd815e26e1;
    uint256 constant betax1_PART1 = 0x000000000000000000000000000000000f66c85f7a371e7e812d817118f8be86;
    uint256 constant betax1_PART2 = 0xf951429aa4d6f6bc14d8dd3c6acf4ee6ce9eb10db4d28bd74d29e312d1a4948a;
    uint256 constant betax2_PART1 = 0x000000000000000000000000000000000f2520791fdd436d93034e5a81129ef6;
    uint256 constant betax2_PART2 = 0x1f2b01c9adbbcc2ca98dd8a89a5516c515c957439f3e06f2885274429331757d;
    uint256 constant betay1_PART1 = 0x000000000000000000000000000000000d01469b9b463d1cc41e7ea38d8efeed;
    uint256 constant betay1_PART2 = 0x825ded1d515b45ff4b818c3fb568d67264f50ecfe2c92e7238acb26ec23e14e4;
    uint256 constant betay2_PART1 = 0x0000000000000000000000000000000015810a24fe07c9e96dde3460aa9a3618;
    uint256 constant betay2_PART2 = 0x865c81d26192499b02b97190e271e4100c26013b9d9400f1545f6fb746586506;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x000000000000000000000000000000000a18ce5e2a4ad29baf24000d0c7492c5;
    uint256 constant deltax2_PART2 = 0x23fb30acc057759c1e96b490b9445b21bd8e0ffb060ff8890c9f74f53a023d8d;
    uint256 constant deltax1_PART1 = 0x000000000000000000000000000000001662097596666fb05a8f90ee443ad3bb;
    uint256 constant deltax1_PART2 = 0x07d2522b7240bb4754e9b984f4bb5dda80131dd895a2bce6e7ac828deaf4b6c8;
    uint256 constant deltay2_PART1 = 0x000000000000000000000000000000001443b2fa2ace448689d3d457b8a3fcda;
    uint256 constant deltay2_PART2 = 0x3f4f1ce9ab52e29b43388885068c6a80b8eb105fc7b103e4cbdcd836855aa5d3;
    uint256 constant deltay1_PART1 = 0x0000000000000000000000000000000004a1bb89d25ae81d7feadc77b6d4098d;
    uint256 constant deltay1_PART2 = 0x1add9527c7282fa41b63fe9fa4bd8cf74620be49c06a399518a34290d3b42652;

    uint256 constant IC0x_PART1 = 0x00000000000000000000000000000000126bf2c1f0f50381a8b05717b782ce35;
    uint256 constant IC0x_PART2 = 0x17bc4e19ed723a29d34de48656c2f440a19be47c9955e5da09ceafe8e803a889;
    uint256 constant IC0y_PART1 = 0x000000000000000000000000000000000f58690df44087a62ba98f958cd205ee;
    uint256 constant IC0y_PART2 = 0x1801583f0c2ddceafc9f0ea6e8a1d25459811056e857c71b55668c14e4c71380;

    uint256 constant IC1x_PART1 = 0x00000000000000000000000000000000158f466e429874d3a34bd92ce8a170a5;
    uint256 constant IC1x_PART2 = 0xe1a789ed5393755f732a74221ad3a29525da783dba938092acda83453f88ea3f;
    uint256 constant IC1y_PART1 = 0x000000000000000000000000000000000f7cc04d969ab50d1904193ceb3b96b1;
    uint256 constant IC1y_PART2 = 0x265cceba6d1aa2d12e3387ab688176b48f95aed10f8ab73d7c45d73698813ca0;

    uint256 constant IC2x_PART1 = 0x000000000000000000000000000000000bb70152ce86e9c28b1256f7a8466d67;
    uint256 constant IC2x_PART2 = 0x53e7fa134db5282955e2733ff553fd696cbc21d5af8e1c79c28eac00e144bc63;
    uint256 constant IC2y_PART1 = 0x0000000000000000000000000000000006d6bd86be17dc2a255583d95f8a52ab;
    uint256 constant IC2y_PART2 = 0x97dc59bdb046e615d18842ca7fba431c9cb1bee2968cf416c1c8fa5bfd4d1377;

    uint256 constant IC3x_PART1 = 0x000000000000000000000000000000000b38cbabcabfda7724e074a6ac56e6f0;
    uint256 constant IC3x_PART2 = 0xdb4f8339a4da175f30336854486115c2ba76b058c7efca3b12809677b465e049;
    uint256 constant IC3y_PART1 = 0x000000000000000000000000000000000f32d4a243dd45f42cf0291476a536d2;
    uint256 constant IC3y_PART2 = 0x8f39f81d748dba0408752afdfb2531177f4748fca7d5ed227e22342e23933611;

    uint256 constant IC4x_PART1 = 0x0000000000000000000000000000000019c6aeade8ce4fbf76836101de818617;
    uint256 constant IC4x_PART2 = 0xb6c20cc4b6dab75b75a682edcb456938204c602b6092a533e7cde473d4d8a8f2;
    uint256 constant IC4y_PART1 = 0x000000000000000000000000000000000453c25847795fd03cb54bb17a5f4015;
    uint256 constant IC4y_PART2 = 0x115ac7b5acc67149dce7f63dea6b03ed39fb8d288446bc289475706d52d33375;

    uint256 constant IC5x_PART1 = 0x0000000000000000000000000000000004cd22101cca29835511f2310bddb94a;
    uint256 constant IC5x_PART2 = 0x52e3fe480b756c41249da8072ae05fcb76177d630ac775b51e2e5ca8dcb1f3d6;
    uint256 constant IC5y_PART1 = 0x000000000000000000000000000000000ac9e04e63bf137f5deb2a641008096c;
    uint256 constant IC5y_PART2 = 0x9d03b6e8bb3b88c75def8b433e6e739d4d6eb2fe83264aced05a3938c622b0fb;

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
