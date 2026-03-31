// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x000000000000000000000000000000001247942959def0eef94b4078f56672c1;
    uint256 constant alphax_PART2 = 0x42a2f165fb8a59c4b1ab644a43fbd160721939e2d30c5a2f2ceb761e28bd1f37;
    uint256 constant alphay_PART1 = 0x0000000000000000000000000000000009a3742eda1c464c5b367365c572fe9c;
    uint256 constant alphay_PART2 = 0x9617dc63b0319743121bf5dcf10bacf9912515a6f0752183c12bc35dab671aba;
    uint256 constant betax1_PART1 = 0x000000000000000000000000000000000b64caaa9d4fc1b826873cb4aaab72f9;
    uint256 constant betax1_PART2 = 0x72e5fa5cc49cbfd431f6705558389ebdd286751ebf86a4a665de1f75dd129ca7;
    uint256 constant betax2_PART1 = 0x000000000000000000000000000000001514b23609bc7857d48fa994e97827b4;
    uint256 constant betax2_PART2 = 0x4040cfffce0ff47f2adf6a26f8e9bd6e9cb58c64192b1b1c325a31c64214442b;
    uint256 constant betay1_PART1 = 0x0000000000000000000000000000000001ab37759f408255215b246ddbf25104;
    uint256 constant betay1_PART2 = 0xbf21b240d448b4920e8a4d7c71b9323aba73ecb472d7c339d880aeaf1fdeff99;
    uint256 constant betay2_PART1 = 0x0000000000000000000000000000000014429b47bfa5f9f07a127cdb6cf2f87a;
    uint256 constant betay2_PART2 = 0x5a0ced41aedf9dfc3db98d9c7036068a2b7f41ce03d167ac3f293d4b0cad3c7b;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x000000000000000000000000000000001555207644a79830423593dcef6ff91b;
    uint256 constant deltax2_PART2 = 0x95ab48e1eaf72ff7fc7c1918fd66d530634a9e32b9b95acf85d7b5cf1ef2c723;
    uint256 constant deltax1_PART1 = 0x0000000000000000000000000000000011fe5673147ec36de4fa22c95c6df8b5;
    uint256 constant deltax1_PART2 = 0xebe1356374555dc2aa7c7b56e18710fa4107a5ecd6118fd02fd941c9ac91e7fc;
    uint256 constant deltay2_PART1 = 0x0000000000000000000000000000000013bf08b1732b718ced88a08911061919;
    uint256 constant deltay2_PART2 = 0x62da12b3a95e4b2d34b10371ed8aa53a151262c280c30131eff58c66960fe2d1;
    uint256 constant deltay1_PART1 = 0x00000000000000000000000000000000073cd8f05e27b9e461e856fb85309475;
    uint256 constant deltay1_PART2 = 0xa1cd212682e0fde0f4cd87525e88ba72f914ed68affaaad8b946d174fb309aa7;

    uint256 constant IC0x_PART1 = 0x000000000000000000000000000000000414d8a920764056564bf6d1311fe1b8;
    uint256 constant IC0x_PART2 = 0x4721b5220647b973947eb21c3f96f1a227f810197466b14ffca5949cae49c7fa;
    uint256 constant IC0y_PART1 = 0x0000000000000000000000000000000003070857e8c3c3df8d291ad46d515b32;
    uint256 constant IC0y_PART2 = 0x19127a3ec0644e02ce7f6e5bfaf39d53ff53b1afd30546b57497633288b76d17;

    uint256 constant IC1x_PART1 = 0x00000000000000000000000000000000136f11ec15cb05c54369d6d265ec1687;
    uint256 constant IC1x_PART2 = 0x476191cfbc837fefa1e7d94848e08f43cdc52400c5e5341ae778155e4f833fdc;
    uint256 constant IC1y_PART1 = 0x0000000000000000000000000000000014349bafe8ccc6b73eef26da54201557;
    uint256 constant IC1y_PART2 = 0x34a004d8dfeef9e3d736c2f64d33c68dde4973621e6b612767be045f2de5d608;

    uint256 constant IC2x_PART1 = 0x000000000000000000000000000000000fa5489808e5b047da026c03d640cb94;
    uint256 constant IC2x_PART2 = 0x6f44e60c698f443993ee6113dcb2b265fa247619f71919f7f0dbab6f512fd91d;
    uint256 constant IC2y_PART1 = 0x000000000000000000000000000000000ab5dc9d4303cfe539c6e869a824e466;
    uint256 constant IC2y_PART2 = 0xf7c14275277fe9966cdba2d6db45de19f43944760859609adf5a9329543b6cdb;

    uint256 constant IC3x_PART1 = 0x000000000000000000000000000000000d0be4aa86847456c1a88ac793497ccb;
    uint256 constant IC3x_PART2 = 0x602bee806783a1a5600f8620056207b85791078dc347bdd5eb85bf1eb48d2094;
    uint256 constant IC3y_PART1 = 0x00000000000000000000000000000000150122ada4037a1e81399bfbc96d99f3;
    uint256 constant IC3y_PART2 = 0xf83d94c47d1f64302449d9faefcd61eebc9271a0a0c0dc70df3deab4900d4e79;

    uint256 constant IC4x_PART1 = 0x0000000000000000000000000000000017dab3620b13f267e8c0520278ce5bd4;
    uint256 constant IC4x_PART2 = 0xed54cd7c0df9a83fed03e7fb02352ad0e2ed5b5e7d7a17894f331c17798a1709;
    uint256 constant IC4y_PART1 = 0x0000000000000000000000000000000007408d16e26e3854f614ba89445f3457;
    uint256 constant IC4y_PART2 = 0xae2ac5f7c62124ac97ad80077466cf81dddf6932a946e2d138cba51ea350961d;

    uint256 constant IC5x_PART1 = 0x00000000000000000000000000000000129950a9667dbf9fe263ccdc36099223;
    uint256 constant IC5x_PART2 = 0x2cf79f65cd58d467281b93a43d1ee738f718c23876c99cb784715ad145c8ef68;
    uint256 constant IC5y_PART1 = 0x000000000000000000000000000000001733279f7f371350b9a3b8e7996ab2c0;
    uint256 constant IC5y_PART2 = 0xc5307d3445404bf23841c31081688d9c0d79904096fa28253e4a84e679f27db3;

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
