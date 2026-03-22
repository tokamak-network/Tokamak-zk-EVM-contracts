// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x00000000000000000000000000000000089286eaa6622d895408d69c4dbd74a1;
    uint256 constant alphax_PART2 = 0xae89279ec00fb7076bfac3256c9ae076c1e4c6f5adeac4b919250a6839ac78af;
    uint256 constant alphay_PART1 = 0x00000000000000000000000000000000048f47c17fc0543da1dee3f886d9e09a;
    uint256 constant alphay_PART2 = 0x476912cf3e1f02fe5ca22e1147a3fa69892cc2d0938e48c314c71925af014491;
    uint256 constant betax1_PART1 = 0x0000000000000000000000000000000005ae3d054045d03dc337dbd7029301ef;
    uint256 constant betax1_PART2 = 0x1883de9be4d9c7c26472b7724120a337022370995f8e7f0771381c358a786dfd;
    uint256 constant betax2_PART1 = 0x0000000000000000000000000000000013deeb9abdb3a16069db587400c38ed4;
    uint256 constant betax2_PART2 = 0x055e11de5e3cdf86c0807cd8863b73e7162d8b82bbcbb7ddc84f5a2d04a069a3;
    uint256 constant betay1_PART1 = 0x000000000000000000000000000000000d7d5bd1bb138a834f755bcbeb326041;
    uint256 constant betay1_PART2 = 0xb0941dbed18a847df764f151af84ad931f773944abf3035267e84da29dbf62aa;
    uint256 constant betay2_PART1 = 0x0000000000000000000000000000000010ae3a2a6e4642473ae7a86a342319b7;
    uint256 constant betay2_PART2 = 0xd968538e10e549a922df9d375b079ab7d37d0f2f26bbb13c1dac2f156950ea58;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x0000000000000000000000000000000010b65c256014cf35d0735dab942736e2;
    uint256 constant deltax2_PART2 = 0x0c9cf13b8e752795812e72fe56ae381116fbf47801a5054a9c7967df3273c11a;
    uint256 constant deltax1_PART1 = 0x0000000000000000000000000000000008dce2ccf2cac83b4bc35dd696fcec2e;
    uint256 constant deltax1_PART2 = 0xeb4c8ad4ad6d8a7a32b2065fd2c73e18ec7e37176b8580d985bbb1db43d025c4;
    uint256 constant deltay2_PART1 = 0x000000000000000000000000000000000b5e05ae4bbcd46f688dc0f616593851;
    uint256 constant deltay2_PART2 = 0x486cd23a3ded00882fcb85339cc1ec38b96e2af208afa0ad5a91dc43dddb4310;
    uint256 constant deltay1_PART1 = 0x000000000000000000000000000000001795425c04199c06ab6bf719699e9383;
    uint256 constant deltay1_PART2 = 0xeb032d46877e8f10181a4ac4f691932d8342f554632e1952f0e8f96dd82a35c4;

    uint256 constant IC0x_PART1 = 0x0000000000000000000000000000000015149066ad1bfbd87a15e63b64d99770;
    uint256 constant IC0x_PART2 = 0x83a2001f8dab256335af3c7f46941bad522f8cc333c79e8036a6a1a24b528233;
    uint256 constant IC0y_PART1 = 0x000000000000000000000000000000000415643072386f5ac288744e5098065e;
    uint256 constant IC0y_PART2 = 0xf475a34106542619fcbe25725d92aa78ffd022a730b91c21208e81962b29fb07;

    uint256 constant IC1x_PART1 = 0x000000000000000000000000000000000ea58e32df8adb3d531cbc03da779c7f;
    uint256 constant IC1x_PART2 = 0x9f29dc6599db2a720cb45b846a378495ff2f19cba7e0ecf499ab9ede4bdafa50;
    uint256 constant IC1y_PART1 = 0x0000000000000000000000000000000002d909a67bf19f238e5fd7e6e5d5c500;
    uint256 constant IC1y_PART2 = 0x3d5d97531139c977e4c85cee8501bbea0585257d430a80956f912f3b5a75274f;

    uint256 constant IC2x_PART1 = 0x0000000000000000000000000000000005038acfdb09345da54e24b160653174;
    uint256 constant IC2x_PART2 = 0xeb99cf8d58477653937a0dbb95d521682e039980cea72b13815d86430e495250;
    uint256 constant IC2y_PART1 = 0x000000000000000000000000000000000c3837ed6761052a2d745e2ae4af1df5;
    uint256 constant IC2y_PART2 = 0xc74f96c414e4269af2e0628a9705474f0ff7657d56318fcccb8754d889df6ab3;

    uint256 constant IC3x_PART1 = 0x000000000000000000000000000000000f50bf0ef065ae1f11f9a8f26caf02e7;
    uint256 constant IC3x_PART2 = 0x0bc54212774831a5ce98fe435ce6646968a9282ee1e14cc32f0e8bd6095f1524;
    uint256 constant IC3y_PART1 = 0x00000000000000000000000000000000139e6743934cab2ad2fda7252c030308;
    uint256 constant IC3y_PART2 = 0xdd4ddbe9797ea6b856bd8039e901a0e4aa80450ba1faced405787675309b610f;

    uint256 constant IC4x_PART1 = 0x0000000000000000000000000000000017279bfbefd9c0d2a8be1be483a72782;
    uint256 constant IC4x_PART2 = 0x4faa3e893eb5ca423f70a8d3d1d5f434df622e3dbe830ceaa3980370c20b7b26;
    uint256 constant IC4y_PART1 = 0x0000000000000000000000000000000007d59d693cd023d60c8d9e022100245c;
    uint256 constant IC4y_PART2 = 0xa0661cd6e591ad073ee5889589a20c250e59abccf01a355d8b73692819762d9e;

    uint256 constant IC5x_PART1 = 0x0000000000000000000000000000000003e6b8231bf7e6e244dd467a1f187b3a;
    uint256 constant IC5x_PART2 = 0xeb4440c4c4915a992dfc3b912ac6a689ecad78865ace6d51fb2e1cd5a633d5af;
    uint256 constant IC5y_PART1 = 0x000000000000000000000000000000000bad65c47cca3e56ea1508a26935093c;
    uint256 constant IC5y_PART2 = 0x27aa8c9331598ea03fd1133ac05d5229112146989c4daa385673d7f5a3757d64;

    uint256 constant IC6x_PART1 = 0x000000000000000000000000000000000677f45a9de1ee3f404354763bbe10b4;
    uint256 constant IC6x_PART2 = 0xe0bdb8aa08a05348bb3beb6295361887304d4f5c44e4a538d585e827a8f89676;
    uint256 constant IC6y_PART1 = 0x000000000000000000000000000000000b7d355416375ae921edc639dab61beb;
    uint256 constant IC6y_PART2 = 0x5ec7748979849c4474ab3fe94e7498031287cecaf87fd7d08b02d2f62bcb50d1;

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
