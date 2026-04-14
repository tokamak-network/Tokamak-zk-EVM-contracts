// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x0000000000000000000000000000000016fee513bcb98f8615db1def29387922;
    uint256 constant alphax_PART2 = 0xe11e1f4bff159343041cae24fbffd63b173d5a3ddd967da695f0a91f4db17c02;
    uint256 constant alphay_PART1 = 0x000000000000000000000000000000000ddb222beb35dbd15a835b8f8741d887;
    uint256 constant alphay_PART2 = 0x21214fce5bb47d7c17da760121adaeae475e7b936dd95dc7e3ea0aa6b0955cb8;
    uint256 constant betax1_PART1 = 0x0000000000000000000000000000000018c0b3dd6968453cf4883ba1217afda8;
    uint256 constant betax1_PART2 = 0x5eabf08f493f0b31959a76e8497b939aba72d48d813191634a07a565e1c6336b;
    uint256 constant betax2_PART1 = 0x000000000000000000000000000000001111e30f3bee48480a65627711731734;
    uint256 constant betax2_PART2 = 0xfa67e7b488162a7ee39388888eb49d3ddbdd136fc9ffdc662b9e251d74ca5b28;
    uint256 constant betay1_PART1 = 0x000000000000000000000000000000001758d66737c3447fd9ce9ada42ae7d70;
    uint256 constant betay1_PART2 = 0x80721447434c84efa9332f4ed71922d1debbea12ffca89546b48c57208eb6836;
    uint256 constant betay2_PART1 = 0x00000000000000000000000000000000046558fb61c1bd35ac43422a3f9cf1a7;
    uint256 constant betay2_PART2 = 0xb0aafc9a0cc99c134633a6888e5af8ae475e6249f06430e6d05ea131c35a51e5;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x000000000000000000000000000000000f3435f970cb76eee4945a1129e6db9d;
    uint256 constant deltax2_PART2 = 0xd6eafc7bb4b21b872432f5284e224b3d46712834f88bd5a93a27191a02e0a941;
    uint256 constant deltax1_PART1 = 0x000000000000000000000000000000001745191bfaab33502e4e038fcadb5118;
    uint256 constant deltax1_PART2 = 0xa50b7de93da47ced513d8ae8eb7fbfbf918bc0e8518627664426a4a3e4cffbb1;
    uint256 constant deltay2_PART1 = 0x00000000000000000000000000000000087fb8f9b02952f6b52bef1222b90836;
    uint256 constant deltay2_PART2 = 0x1a2e8cd5d66f31865dbd3a948eb5f1f356d5c4a4c26d8a70bbe27745e5be4b3c;
    uint256 constant deltay1_PART1 = 0x00000000000000000000000000000000137994cb42424013a4f2be6c51d03b94;
    uint256 constant deltay1_PART2 = 0xdaf26e541811a109a0b22f5cded98da8099bc3fd0cc160c37f009f4d4d30135b;

    uint256 constant IC0x_PART1 = 0x0000000000000000000000000000000017f48edfac0642d2bb828279c40c42fc;
    uint256 constant IC0x_PART2 = 0xc6fa4790b0ae1bb5c7e195330964226e24f2747cc795ad2a233794888eb0f169;
    uint256 constant IC0y_PART1 = 0x000000000000000000000000000000000546937cab05d4fdf2e94e686ed34e67;
    uint256 constant IC0y_PART2 = 0x96160a73575c5e4294aaaff4f3ffe8b18fc937286b1bb0b15668f1ccc9d65180;

    uint256 constant IC1x_PART1 = 0x000000000000000000000000000000001831d0f06cebe61c6d2fce80e9603d80;
    uint256 constant IC1x_PART2 = 0x56c67b045059fdb613abdb5e147d3ad11925c8133cf55c1ef98a3cee6fa7f27d;
    uint256 constant IC1y_PART1 = 0x000000000000000000000000000000000b5f0372a548e2f5bce10969fbb143ee;
    uint256 constant IC1y_PART2 = 0x813383998182181871d22c2bde2e3be4052c88dfa83118cd77736fbf9d659156;

    uint256 constant IC2x_PART1 = 0x000000000000000000000000000000000de72ca887425815251eb1afe4e5facd;
    uint256 constant IC2x_PART2 = 0xc0ec18350df937ecbc7d1c8b587db983009c01c670e7102b20f441c01f6f1b7d;
    uint256 constant IC2y_PART1 = 0x000000000000000000000000000000000590143787efbdb7625fa053541ee2eb;
    uint256 constant IC2y_PART2 = 0x4493275bc1480daf8ff248cac858cc9dc58c8fa29f01dc1f59ab3d8ce7333f2d;

    uint256 constant IC3x_PART1 = 0x00000000000000000000000000000000109844609b80ad4e9a0c24daf8f02e2b;
    uint256 constant IC3x_PART2 = 0x707750deaafa5c800dd9abf1fc634496ef117144333be07ab7dac16df8d38998;
    uint256 constant IC3y_PART1 = 0x00000000000000000000000000000000195d2d93fc0dbe35fe9450f270591dd1;
    uint256 constant IC3y_PART2 = 0x85e82a33d2c32d1025b04ba08966a27bfd7ff7a162c11e3414ed42d3c5484ce9;

    uint256 constant IC4x_PART1 = 0x00000000000000000000000000000000131fdd8714cf8ce0c0a4babb927db022;
    uint256 constant IC4x_PART2 = 0x288bc8b2112e90240acee7534649e1e69f29d6ddbbbe2e5609bb81341c47db9d;
    uint256 constant IC4y_PART1 = 0x0000000000000000000000000000000018810ba7419834febc1c854fb8d4e993;
    uint256 constant IC4y_PART2 = 0xbe8834eee77d6b4c24460afb55f3a9ea2ef214e6a17ae5168fa5ce4f59ca03e3;

    uint256 constant IC5x_PART1 = 0x000000000000000000000000000000001829288c9b168011da769d2d590a9626;
    uint256 constant IC5x_PART2 = 0x859bf24f14036344c1100a449738e68052644fc9f7aca775cc898dafb03ebc7f;
    uint256 constant IC5y_PART1 = 0x000000000000000000000000000000000180bc6be564604ab0ff2eea3ca558a9;
    uint256 constant IC5y_PART2 = 0x0b4357bd977c47b3d670a9f5318f43af76d812c45287679beb678b38da0f9569;

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
