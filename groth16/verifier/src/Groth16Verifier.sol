// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x00000000000000000000000000000000151b09e11e44fbea7d02cbe067602d25;
    uint256 constant alphax_PART2 = 0x28d43a1f248308a21c32080efc5272a20d490f5ce60276f071b9b96005723e4a;
    uint256 constant alphay_PART1 = 0x00000000000000000000000000000000155a999afa8eaf5d62901e2b78a8bcfd;
    uint256 constant alphay_PART2 = 0x8d2b9963613ece54c5986e34b63775c56137f2ccbdaab3b43978489d1da6ba09;
    uint256 constant betax1_PART1 = 0x00000000000000000000000000000000178b932496cfc69f0e76c93f6a35391e;
    uint256 constant betax1_PART2 = 0xe2caeaede5185c583d21498bbec62dd440af8b1c79475c028736b249647dee8b;
    uint256 constant betax2_PART1 = 0x0000000000000000000000000000000005ac4c1965ae22a27047f7f0f0502539;
    uint256 constant betax2_PART2 = 0x9a5ae065698b1525f49b3c7d6a1daef2ca0016f11328ec84e86d8dbe9f310961;
    uint256 constant betay1_PART1 = 0x0000000000000000000000000000000016f8b4293b4647288c37aa1ee1b765f7;
    uint256 constant betay1_PART2 = 0x65a72b13ce902418d4ad340c72a99cc071739347372a6ef412600dea9cb1167e;
    uint256 constant betay2_PART1 = 0x00000000000000000000000000000000089233340656509ee04067d0d4fc01f1;
    uint256 constant betay2_PART2 = 0x29fed9c78658700605ab4382b876922dd1afa4e5f002962baeb0bf4274233a6c;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x0000000000000000000000000000000012314914d52660263fd9fc42b4b7afd0;
    uint256 constant deltax2_PART2 = 0xca65f407991149a7a2e3c352493b6b24c79589318cb87cb69f08a8730ce42cfe;
    uint256 constant deltax1_PART1 = 0x000000000000000000000000000000000c32c9d37aefa7fd8af78f10173b90e1;
    uint256 constant deltax1_PART2 = 0xe02feb44e85fbfc52d5f0946e4fed297fd7ab43d53a4a80259193dd130e320fc;
    uint256 constant deltay2_PART1 = 0x0000000000000000000000000000000003e4fc4388ecf808b09956a4d383e0e1;
    uint256 constant deltay2_PART2 = 0xd8220a738b91edc8e7f942d4db055006088751c8b411d6910d5a1637f66d335e;
    uint256 constant deltay1_PART1 = 0x000000000000000000000000000000000ea975ea4d9630780fd2e9ba44adce29;
    uint256 constant deltay1_PART2 = 0xc947c1ee78620365acdc7cd8d86d15214bfa0f343575cfb3c1f80e25d83bdd61;

    uint256 constant IC0x_PART1 = 0x0000000000000000000000000000000004390ed644ab672fa3ff334eb23a3b45;
    uint256 constant IC0x_PART2 = 0x7002ca0a9a92d0a94f256315ff0da411da5c3e948b35e3b7f6f470a95085180c;
    uint256 constant IC0y_PART1 = 0x000000000000000000000000000000000208de8bbb59321529f5aa8729a6fcc7;
    uint256 constant IC0y_PART2 = 0x9191b3a4662acaa0c23c41ac73b811cc87f9194ca87d8630e204d7311aa063a5;

    uint256 constant IC1x_PART1 = 0x000000000000000000000000000000000972723e2f94737112d9285c5a3e80ff;
    uint256 constant IC1x_PART2 = 0x3331739392c3785d4e2eeba43ca27c459cdb0fd162206c5e75c34456271dcfcc;
    uint256 constant IC1y_PART1 = 0x0000000000000000000000000000000012c452f87f0400992a36295cfe18c715;
    uint256 constant IC1y_PART2 = 0x93522b72059320c7886ce1d6f3bf332f63987053d92762b0f7350db55d94217a;

    uint256 constant IC2x_PART1 = 0x00000000000000000000000000000000034b37a7a76e3a4c18c1c8e419a14756;
    uint256 constant IC2x_PART2 = 0xe42780400592d792d8330048144ab693ae17be43eb569751f0a50466b76eb522;
    uint256 constant IC2y_PART1 = 0x0000000000000000000000000000000006d1cb9359a8d4d18f4f97c8c9d25478;
    uint256 constant IC2y_PART2 = 0x557ba080dcd73b8542b9e3a3977bff190944d9c54904d495f895525ded7d9d63;

    uint256 constant IC3x_PART1 = 0x000000000000000000000000000000000394285542ac96a4f62a21e4c3ff7f88;
    uint256 constant IC3x_PART2 = 0x683fa4a323895e1c8549e57578f7e9fac8751cb9b30157d2654c0f74b7e1f844;
    uint256 constant IC3y_PART1 = 0x0000000000000000000000000000000018c07ccf8a2e6cd49a5ca613353a410b;
    uint256 constant IC3y_PART2 = 0xdc82cee5773ee01839bdb6767318be89c6fe76cedb22551f720da426abf5e685;

    uint256 constant IC4x_PART1 = 0x00000000000000000000000000000000084f9c9bafed248a0e24bb6be770319e;
    uint256 constant IC4x_PART2 = 0x6604ac0c6317d3626a80c88d3237304e1fe40f0d0576bd02901490ad4ae29f37;
    uint256 constant IC4y_PART1 = 0x000000000000000000000000000000000fdf1adf208d08a847e5e60f2b3e2065;
    uint256 constant IC4y_PART2 = 0x900a1e35bfa921f11a14f60d296a0a29986061393fa5b86ada15d8e7f6cfb1d7;

    uint256 constant IC5x_PART1 = 0x00000000000000000000000000000000056ec5d55cb5edaa6cf06748751ae002;
    uint256 constant IC5x_PART2 = 0xeef3dd921d3176709eb5aea23a6eae5a89f7fd8913881143e08b31c17ed39af9;
    uint256 constant IC5y_PART1 = 0x0000000000000000000000000000000015cd8f180417b622fbee28773d4ae75a;
    uint256 constant IC5y_PART2 = 0x6139977972c56c6c2922cbc7329fa7a2edcf554a45571818dea7eb9accd5fad8;

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
