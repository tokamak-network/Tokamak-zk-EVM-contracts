// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    string public compatibleBackendVersion;

    constructor(string memory compatibleBackendVersion_) {
        compatibleBackendVersion = compatibleBackendVersion_;
    }

    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 =
        0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 =
        0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 =
        0x00000000000000000000000000000000088e636421aaf62ae9092aa67a214d43;
    uint256 constant alphax_PART2 =
        0x2a134580aa3ffe03fe733d5c64e256217f61a77b905a789c0aa592a1712d10f8;
    uint256 constant alphay_PART1 =
        0x00000000000000000000000000000000103f5893ff118ce58f5e1401af02b63a;
    uint256 constant alphay_PART2 =
        0x3d57640cfef85f180b8e0c3fe655243453e5d30c9dd68b05df2b7ed569c76b37;
    uint256 constant betax1_PART1 =
        0x000000000000000000000000000000000a18c5a755d82b5891e52d82f0828e69;
    uint256 constant betax1_PART2 =
        0x12ccf219ffa9ec2f16aff510b657097cd0b8b8c92f26c3b1db43d5675c1bbf09;
    uint256 constant betax2_PART1 =
        0x00000000000000000000000000000000142a5b9784099a6a5fd024a25d999f8b;
    uint256 constant betax2_PART2 =
        0x0c064c9eaed4f7eb86892dc52dbbbe73d5d807ec17b1f1e672d97d59dbd11710;
    uint256 constant betay1_PART1 =
        0x0000000000000000000000000000000017e7abb731ae671491d117982f3b51b7;
    uint256 constant betay1_PART2 =
        0x17beff4054f6d6537707957f8266ffa2280eeebad944869891378e831c1c66fd;
    uint256 constant betay2_PART1 =
        0x000000000000000000000000000000001894c175fd99f8106d355c078f268705;
    uint256 constant betay2_PART2 =
        0x62c98cd6f0c3b9cd0b952d2dcec6515f45727389a79017f4beecf6f9d0780d59;
    uint256 constant gammax1_PART1 =
        0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 =
        0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 =
        0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 =
        0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 =
        0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 =
        0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 =
        0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 =
        0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 =
        0x00000000000000000000000000000000145ba1cac8d393f4f7f3ce39f048f5b3;
    uint256 constant deltax2_PART2 =
        0xf6fc7eec6f853dc4d9c58d365216131c93407d8d10b180ad16c40452a0bb7e3c;
    uint256 constant deltax1_PART1 =
        0x00000000000000000000000000000000031870ba26563c916e15e1929caf2b38;
    uint256 constant deltax1_PART2 =
        0x8645eee4d7483eea0913c470bcbdaa71fbb0c39c08afe2c6420e4a8000791b99;
    uint256 constant deltay2_PART1 =
        0x000000000000000000000000000000001941b67522124cf304104c79cffe8b5d;
    uint256 constant deltay2_PART2 =
        0x5fddb6b766913a25623579c278ad64802a46c9c87d3ef90c4724c54780d478a4;
    uint256 constant deltay1_PART1 =
        0x000000000000000000000000000000000215db03d934bb14c720fc387f9dd3fa;
    uint256 constant deltay1_PART2 =
        0x281391f6828d7e1d4aabf6709f5aff25b38e5a707f380629d0ad0f1a843f04db;

    uint256 constant IC0x_PART1 =
        0x000000000000000000000000000000000b7c53300e4538e7171d57e920ee0505;
    uint256 constant IC0x_PART2 =
        0xdd81be2fadd86deb263f253e60cecc5415772b20f4e8ae2f76def52168e989e1;
    uint256 constant IC0y_PART1 =
        0x000000000000000000000000000000000337503b7b0a7fa32efaabb68e9e6915;
    uint256 constant IC0y_PART2 =
        0x2295f82ccd980d02563d91a1319154b8b98d789fe958668521d44a7ad7d0f8ea;

    uint256 constant IC1x_PART1 =
        0x0000000000000000000000000000000007ce2bce2cc1acec269acbc23ccd3c78;
    uint256 constant IC1x_PART2 =
        0x812dd7c290bbefa16afc48978797f38efe9c37c76a6efb99b4e99055b01991ea;
    uint256 constant IC1y_PART1 =
        0x000000000000000000000000000000001459d49c83cf193f84ff73bce04438fc;
    uint256 constant IC1y_PART2 =
        0x54106e746a0b0170124ef248f7f943f4634f443e2975b08884524709da8691e1;

    uint256 constant IC2x_PART1 =
        0x00000000000000000000000000000000195527dafb29688947d52c28d4af978f;
    uint256 constant IC2x_PART2 =
        0x77e1edd37481e0fdec0cb06a51959872ef86b6e55157a6b56d161424183b9e8f;
    uint256 constant IC2y_PART1 =
        0x000000000000000000000000000000000792e957a64f1117cfaf184765453050;
    uint256 constant IC2y_PART2 =
        0x0fe09d8cbafefc28e16bd4615aa179c30082cfecc4bcf38c193e209236950fd3;

    uint256 constant IC3x_PART1 =
        0x000000000000000000000000000000000dc42fe00fb263dac043f1771e8c06e1;
    uint256 constant IC3x_PART2 =
        0x0d7acdf20d1834db3b8a3b58e938e97491b05ec19a903b1718807bace0ba6679;
    uint256 constant IC3y_PART1 =
        0x0000000000000000000000000000000000a2f5de10274299beb9c5470350b84f;
    uint256 constant IC3y_PART2 =
        0xf1a363a948f095abba3341c049359c334833324fe9b4e0e48a34a0e13103c5a5;

    uint256 constant IC4x_PART1 =
        0x00000000000000000000000000000000041e843e19d7540b1cbfb6610d83c0e2;
    uint256 constant IC4x_PART2 =
        0xe5cb356517bdf6a4337e1124c22b54eaa42fa5f3d6ce291e2f3542ec42dbe398;
    uint256 constant IC4y_PART1 =
        0x000000000000000000000000000000000929f4c78df05b7d87ba9d211b1abfd2;
    uint256 constant IC4y_PART2 =
        0x32c8d8a40926079be71798e317a8dfca8971ded4a81c4ff63340d790ec18b013;

    uint256 constant IC5x_PART1 =
        0x00000000000000000000000000000000107b93e20a9bf6ac68d42206915c4f57;
    uint256 constant IC5x_PART2 =
        0x12ea13b517133cb6ab9e4936bb2932d29fa2b26d14cc36f2d1a0b8302bfb0975;
    uint256 constant IC5y_PART1 =
        0x0000000000000000000000000000000008c08861444d7660e97ccba643cccb43;
    uint256 constant IC5y_PART2 =
        0x3e935c546e486ac66c7cbc23f3d1c44992294bb97f55eacd9760030ed12f6705;

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

                g1_mulAccC(
                    _pVk,
                    IC1x_PART1,
                    IC1x_PART2,
                    IC1y_PART1,
                    IC1y_PART2,
                    calldataload(add(pubSignals, 0))
                )

                g1_mulAccC(
                    _pVk,
                    IC2x_PART1,
                    IC2x_PART2,
                    IC2y_PART1,
                    IC2y_PART2,
                    calldataload(add(pubSignals, 32))
                )

                g1_mulAccC(
                    _pVk,
                    IC3x_PART1,
                    IC3x_PART2,
                    IC3y_PART1,
                    IC3y_PART2,
                    calldataload(add(pubSignals, 64))
                )

                g1_mulAccC(
                    _pVk,
                    IC4x_PART1,
                    IC4x_PART2,
                    IC4y_PART1,
                    IC4y_PART2,
                    calldataload(add(pubSignals, 96))
                )

                g1_mulAccC(
                    _pVk,
                    IC5x_PART1,
                    IC5x_PART2,
                    IC5y_PART1,
                    IC5y_PART2,
                    calldataload(add(pubSignals, 128))
                )

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
                default { neg_y_low := sub(Q_MOD_PART2, y_low) }
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
