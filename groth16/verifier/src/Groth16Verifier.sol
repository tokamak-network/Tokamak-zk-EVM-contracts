// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x0000000000000000000000000000000009180b4f874183a45e5e66d2810425d7;
    uint256 constant alphax_PART2 = 0x42af851ce8e764db9b2011c110ad13bd7663748f250fc35d2fc7c70b93a1cbb5;
    uint256 constant alphay_PART1 = 0x000000000000000000000000000000000140bd2770cc5c48b299db52cb85018e;
    uint256 constant alphay_PART2 = 0x31d24196e00ce6894e58d791889192f7cd22069066f71ae7d8f187d7ea66af92;
    uint256 constant betax1_PART1 = 0x000000000000000000000000000000001287684faf44e486c9c8517d19c48469;
    uint256 constant betax1_PART2 = 0x6bac083ae05e82e8312f1fb923b89033fd46f70940e57bf41a674699e34f3dd1;
    uint256 constant betax2_PART1 = 0x000000000000000000000000000000000325c25ae85dfcdb4c945381cdfff4ed;
    uint256 constant betax2_PART2 = 0xde01496b5f239661bf4a84ee00cc016d776f3239273f1273ad2fed813a04a441;
    uint256 constant betay1_PART1 = 0x000000000000000000000000000000000199ac1813ae6218d70b30fc6ac9e570;
    uint256 constant betay1_PART2 = 0x9030dddc3fa285fec6b5e8d7af6e0a26a9c3ebafb52486c13dbbf437c025b92e;
    uint256 constant betay2_PART1 = 0x00000000000000000000000000000000141479af0df4d1fd0345cbc249cebbb3;
    uint256 constant betay2_PART2 = 0x2bdf11d40187be757a379e96fbbc8bfe7e72fe746e9f21ac9357690b3e178bf0;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x0000000000000000000000000000000004a3c6ce7841ec578200f38a39f52a42;
    uint256 constant deltax2_PART2 = 0xe5657753c02291484e6dda8366aeaa84bc9be4c78c46278ba1dc9c75eedc95d6;
    uint256 constant deltax1_PART1 = 0x0000000000000000000000000000000019c1478458629c864332c8fd396dc4ca;
    uint256 constant deltax1_PART2 = 0xdd1d5e955ed31a2267f7f18a70cefda806167f02c926aa47132a079b950f0532;
    uint256 constant deltay2_PART1 = 0x000000000000000000000000000000000436b468cdcb1c1acb3de7a9f2a97b9f;
    uint256 constant deltay2_PART2 = 0x0abafd534a6b6f5630022b620988030ff54abd1d19e84f5030c1a4372601e35f;
    uint256 constant deltay1_PART1 = 0x0000000000000000000000000000000013840d82b7250fa62079056141cf4de1;
    uint256 constant deltay1_PART2 = 0x4500a4ebaf78ce62bad2532a1e4003e47044bd295b94de21d8e48186b0305788;

    uint256 constant IC0x_PART1 = 0x000000000000000000000000000000001311fc2f0ef6c1a4d1e875bd77a1e028;
    uint256 constant IC0x_PART2 = 0xf38b82d0469349863f2af949e8b01f42cde51dee825d2846669e50e85d2a3974;
    uint256 constant IC0y_PART1 = 0x000000000000000000000000000000000923292d382200cf6bedc0bfc1618e96;
    uint256 constant IC0y_PART2 = 0xc012c96551ab66a7fc85350f7d59448c79d50af3a711618ac6882a7f17d06e67;

    uint256 constant IC1x_PART1 = 0x00000000000000000000000000000000075cddb7325a4af6ec218fd17b5484a8;
    uint256 constant IC1x_PART2 = 0xcde40b9d45628d04a370e671aa16ed5ce73071418b4b81cdd2b0479c33c493da;
    uint256 constant IC1y_PART1 = 0x00000000000000000000000000000000018f3206d1af4c3e66225d9a11a3b5db;
    uint256 constant IC1y_PART2 = 0x0d001f4e804d1fd7a6ed6cfe6a2147bfb3fa98adb553cbf0ecf835e9bd12f5c3;

    uint256 constant IC2x_PART1 = 0x0000000000000000000000000000000011c3b58e6bd6b9e305d03a292a4d8c31;
    uint256 constant IC2x_PART2 = 0xd958c7b448b5dae9fe5ec4d16eb00f4cc4c1c3e719b7dc3abbd06faab62d4c0f;
    uint256 constant IC2y_PART1 = 0x000000000000000000000000000000000d039b8d406e435c9f58dbd5c04f7aae;
    uint256 constant IC2y_PART2 = 0x0bd315fe45ea3d0d8ab82b0de70fc1fd907647187889f6b2e80d00d417ab7a18;

    uint256 constant IC3x_PART1 = 0x00000000000000000000000000000000172f9c31be5b2f02d377c5f6ca1432f4;
    uint256 constant IC3x_PART2 = 0xe65e4032cae81f9e4206a037cd8c0b7c0b68110e926a9eb2f2ef3bafcc68c91d;
    uint256 constant IC3y_PART1 = 0x0000000000000000000000000000000012a9f58ff998ede31f153d5015f75e91;
    uint256 constant IC3y_PART2 = 0xdb4196de4ce5e2069679e924c5de378cbf74437bed85890dd0a8881ee2b9d3f7;

    uint256 constant IC4x_PART1 = 0x00000000000000000000000000000000066ce4cec0e92786895f3b9dfc78b7a6;
    uint256 constant IC4x_PART2 = 0x9d9a20b774ac7e9e80e372eb9bc029beb6eba5c06a7c2529dc84c9bc5d036f25;
    uint256 constant IC4y_PART1 = 0x00000000000000000000000000000000089746c40c930185c6a2f842c635ea43;
    uint256 constant IC4y_PART2 = 0xa986adc9819f1fdf50f876134e729d7a03425e7034b05b1206a20402d28aae0c;

    uint256 constant IC5x_PART1 = 0x0000000000000000000000000000000003d2a4275d0493c64387ae138fe3907a;
    uint256 constant IC5x_PART2 = 0x4ac54c76e8848a329a43a9d90a8651d7a1c2a2bd0f30bacb3c80015a24fcd9ad;
    uint256 constant IC5y_PART1 = 0x000000000000000000000000000000001091063d773cb75b1510c39b9da7dbaa;
    uint256 constant IC5y_PART2 = 0xfdbd0069603e272f602ebf71c5361eef2cd8557f27bc052ab11daa1616cc83de;

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
