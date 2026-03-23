// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x00000000000000000000000000000000066390989bd40aa06fa3695195f182c1;
    uint256 constant alphax_PART2 = 0x69b98fe1f24c3e157d4f89921847cfec8ff91f942b6e2dd80032bdec16e5fb04;
    uint256 constant alphay_PART1 = 0x0000000000000000000000000000000015f4fdc2436ba76af08aa4a29b65df45;
    uint256 constant alphay_PART2 = 0xcc86c4220dce07f0abdcfd7617409fe641824a2ec095010e603d31eb84eca0b0;
    uint256 constant betax1_PART1 = 0x000000000000000000000000000000000a81d5f9f5ad8d291de22453287b71f4;
    uint256 constant betax1_PART2 = 0x58d0a8ec6d3550d4c9fabb5adba6e51e038e241647e8d200e689847222b8f7b1;
    uint256 constant betax2_PART1 = 0x0000000000000000000000000000000011f34d75551a9c70d8ae005f3879849a;
    uint256 constant betax2_PART2 = 0xb708d1b565ef453b23a3bf03f3b3eb74519d0c6baef049d66c47b144f14786aa;
    uint256 constant betay1_PART1 = 0x0000000000000000000000000000000012a6a0b0abbb0aa2fd2801ca3d524a4d;
    uint256 constant betay1_PART2 = 0x27d6fefd2d3578e3b6d6b9f3a0d9e9ccf15ebf7dd315faf9a7d19d0f5f496b5f;
    uint256 constant betay2_PART1 = 0x00000000000000000000000000000000089adfab71783eca68a4387d9a29aee0;
    uint256 constant betay2_PART2 = 0xd7048395840355ab2813e76606d7ea631a0acb1ddd95e7eac208ed0665e6bdf7;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x0000000000000000000000000000000006d45a623ae23403cbdad9cf294e14ce;
    uint256 constant deltax2_PART2 = 0x385f5dcd5256de9f2e9142cf6ea9936adab799b30e9789d7760045f59b067c96;
    uint256 constant deltax1_PART1 = 0x000000000000000000000000000000000f843524be53eaf25e69045626e8518c;
    uint256 constant deltax1_PART2 = 0xe22091ed7088b39317e7f014c8f1574a5f15a7ecc5d28ba306084e7fea09cb5a;
    uint256 constant deltay2_PART1 = 0x000000000000000000000000000000000a0da15ecacb084bed097657171253f8;
    uint256 constant deltay2_PART2 = 0x93abaf10a7adacc823925e8fb0760767fbe12d83f6b4fde9b015782570bd4180;
    uint256 constant deltay1_PART1 = 0x0000000000000000000000000000000005d4ab71105f23966f6ac88bafd5e698;
    uint256 constant deltay1_PART2 = 0x2d18f5dc8bf10732720075bbc03a5a50a7294b493c6b7bfee615ac9f8c6035cc;

    uint256 constant IC0x_PART1 = 0x000000000000000000000000000000000ef3f4d4f91b51a9b4e91fe6997cb808;
    uint256 constant IC0x_PART2 = 0xbff3e763bcb0a428009a17a41d5399068ef74780cfb5b75fa831d266ab1597ce;
    uint256 constant IC0y_PART1 = 0x000000000000000000000000000000000ff4fc57699df14f892d6b057a45ade1;
    uint256 constant IC0y_PART2 = 0xdeaa9eaca133e4971a2969bea9598ca77ce57493a12d510168621fccc69ef69e;

    uint256 constant IC1x_PART1 = 0x000000000000000000000000000000000d68c5762cb2c7c84b0068265b08d2f1;
    uint256 constant IC1x_PART2 = 0x71cfcd417d15ac3801781c0c416ea22ea59b1bbd21ed7a02760735c02f8358af;
    uint256 constant IC1y_PART1 = 0x00000000000000000000000000000000071e57da03c61905bab95e98f8d1f83a;
    uint256 constant IC1y_PART2 = 0x5dd6e259af3fc322a0a3b328c4e3c9b75d3c3b2932cca7299d879c4e911b8a27;

    uint256 constant IC2x_PART1 = 0x000000000000000000000000000000000237f873c678f25d56815bbfa7b9284b;
    uint256 constant IC2x_PART2 = 0xe78dc120c5aab7658b07d0edb4da934e30f8acdb325fe3228b7ac2f7acc3a278;
    uint256 constant IC2y_PART1 = 0x000000000000000000000000000000001272b22591a136f7e37912e26a56db33;
    uint256 constant IC2y_PART2 = 0x78e6cc59a9083cf7ea62f5f91adee5c3f314e78b91b606983d144d9225468bdb;

    uint256 constant IC3x_PART1 = 0x000000000000000000000000000000000240f8fbf26abf022296f6a787d2be99;
    uint256 constant IC3x_PART2 = 0x5535564dc37a519d915ac1ed877ec0e84da8ac96a8c6928b7e52276ecc2118a0;
    uint256 constant IC3y_PART1 = 0x000000000000000000000000000000000b32a76101a469d02c2fbc14a8da028e;
    uint256 constant IC3y_PART2 = 0x14ca3cfbd3840c19fb5314b4d436e570e53e59dd7cd94c18b3cfbcbb71b80cc8;

    uint256 constant IC4x_PART1 = 0x0000000000000000000000000000000019451dd6a7e025e29ea727ac00619a2b;
    uint256 constant IC4x_PART2 = 0x2839034e7b0b241fe5185e26812df7cfc821d93b2c83c67a37d95b9a1c90271b;
    uint256 constant IC4y_PART1 = 0x000000000000000000000000000000000f30af8cc4c57f513e0904945bd1de86;
    uint256 constant IC4y_PART2 = 0x87385b0bf681b4f6ea50bd61bc82f960a13feafac8545bf0cdf9bfdbeab1f82e;

    uint256 constant IC5x_PART1 = 0x0000000000000000000000000000000006cf5a118c46e965bf3a462094defa22;
    uint256 constant IC5x_PART2 = 0xbc7ef73dcc991331bd03aa585b6a528e5ab603c87dcc36c4ffdb774998c98357;
    uint256 constant IC5y_PART1 = 0x00000000000000000000000000000000143a3be7e9b278c3e3572fb83066e275;
    uint256 constant IC5y_PART2 = 0xdf16e68e495758efb35bcfc42d593261f47b6295f62e8ce26019bc381f41e4d9;

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
