// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x000000000000000000000000000000000b4b34f15c4e85c64fa09545f1814a0b;
    uint256 constant alphax_PART2 = 0xc376541d88d71c3e8180e609c34b39dded062e76453feb258c81650faca29819;
    uint256 constant alphay_PART1 = 0x000000000000000000000000000000000b3cfc9021f3f36ffc704525ec764215;
    uint256 constant alphay_PART2 = 0x9344c428174c850b7631b78f92e3c8519b31369b080e1c9c825c72c4a8376f99;
    uint256 constant betax1_PART1 = 0x00000000000000000000000000000000009da0585e426fd91d14131e5840251c;
    uint256 constant betax1_PART2 = 0x3002baecfbf70fea5d465bdd7b62445ec1d11626b1337a76c621406735aa6a74;
    uint256 constant betax2_PART1 = 0x000000000000000000000000000000000ebd1b6c4a587c4d8231e09d25e45131;
    uint256 constant betax2_PART2 = 0x829ed1dcdff3de38dbbda698fbc865ac3a8d929332747a216badc53bb6907b70;
    uint256 constant betay1_PART1 = 0x0000000000000000000000000000000006ed7cf9f3cc53bf69e7737cb82d7f57;
    uint256 constant betay1_PART2 = 0xb14bf40b3c70e8954869f2234d04b10b454728c73bb5873b2d1b6722743d00c6;
    uint256 constant betay2_PART1 = 0x000000000000000000000000000000000cba84d2a2a015676838fd4dafe84016;
    uint256 constant betay2_PART2 = 0xbce4b02beac25dba1d20fcead6baeb4e147d665c0aeb737737492297012428ed;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x000000000000000000000000000000001297cffdb963116174374508d68bf40e;
    uint256 constant deltax2_PART2 = 0xbe83fb90eda259f85dcaed231a8d42afd5a3d6f1ca0c8d31e51aae8a8dd5831f;
    uint256 constant deltax1_PART1 = 0x0000000000000000000000000000000002251fbca23fa7603c7465fe9352b87e;
    uint256 constant deltax1_PART2 = 0x316d722cf410a087b2130848954577a3850c696eaaea76aa5b7b16ce582c049c;
    uint256 constant deltay2_PART1 = 0x00000000000000000000000000000000126e8f2ac7bc3fdfc1d56bf15f38957f;
    uint256 constant deltay2_PART2 = 0x0275c5c13448102f5986e49a0563d9f5edd6e5ab558e4327f6110eec03f27b19;
    uint256 constant deltay1_PART1 = 0x0000000000000000000000000000000003fd14714c5d0a9a47ad6084f166b315;
    uint256 constant deltay1_PART2 = 0x9dfc2ea3bc405204fb0b716b21d3176d3a7be7dc2aa2c97ddfcaf9e465e91275;

    uint256 constant IC0x_PART1 = 0x0000000000000000000000000000000018ee22a653ca0fb917e18ee2e58dee46;
    uint256 constant IC0x_PART2 = 0x98d7492629be7ea08140a04598ab1e542ce826b05229423223b3580ce9a603fd;
    uint256 constant IC0y_PART1 = 0x0000000000000000000000000000000019c270ad5f19defaa1824cc79bd39c03;
    uint256 constant IC0y_PART2 = 0x2166d430ff55acd14b6b1f42b36fcad62d11cdff1c83c97b261ed3f2abcec5c0;

    uint256 constant IC1x_PART1 = 0x000000000000000000000000000000001403bf20943f40589da28dee55560ee2;
    uint256 constant IC1x_PART2 = 0x54befb6caa39c6c728ecb7ac2061d178a2748c121798e47fa4942bd5e692ea7a;
    uint256 constant IC1y_PART1 = 0x000000000000000000000000000000000c7dda138d917cecad8d1f1a63aa7c3d;
    uint256 constant IC1y_PART2 = 0x1a40abf75194392369172fa19d1ef1eb1e2f2a091c6e6b820e86be79da94be42;

    uint256 constant IC2x_PART1 = 0x0000000000000000000000000000000015d2ae117899becfa07b51ee35b5ee96;
    uint256 constant IC2x_PART2 = 0x183503438eafb09b2e90b0abe7bcee15e7ca1c667c492cc51df904d7c51ff3bb;
    uint256 constant IC2y_PART1 = 0x000000000000000000000000000000001701fe829bb551e0a7f8daa616d1304c;
    uint256 constant IC2y_PART2 = 0xe45c834da995dab68b990414c10aa0f6927619c41f01443b7268584525107865;

    uint256 constant IC3x_PART1 = 0x0000000000000000000000000000000017922ecf9f189cd4ecb95704e9d8e368;
    uint256 constant IC3x_PART2 = 0x127a159e91b95ec8fad6664d72a7429f938897914527d85cd5fd9b3843c5d3c2;
    uint256 constant IC3y_PART1 = 0x0000000000000000000000000000000005aabdfa37ef7b82bc4c2a407552ee25;
    uint256 constant IC3y_PART2 = 0xab3d594c0b393c813d721b4603835ba8a6edca7b07dd3a6c23dfa7d8545ddd50;

    uint256 constant IC4x_PART1 = 0x000000000000000000000000000000000ca44ad83b2729749e5859ae85802819;
    uint256 constant IC4x_PART2 = 0xfddebed080f32943a4db8181070b5bafcdbbb9d4497aa3c659e4598e5723ed92;
    uint256 constant IC4y_PART1 = 0x000000000000000000000000000000000da802016cd6c290ecfc45e02ad21f06;
    uint256 constant IC4y_PART2 = 0xff9af88259cf850839cc90d8be576c901e2bf077c5a8c5800ee7ac1356009ea1;

    uint256 constant IC5x_PART1 = 0x0000000000000000000000000000000001a76b3c07f707c7f1767bf25234b35c;
    uint256 constant IC5x_PART2 = 0xbfeff2c1d10368f8976603d6aa7a798e168b7482cb2c597989fc2b300eb533ae;
    uint256 constant IC5y_PART1 = 0x000000000000000000000000000000000aa4d7fb96b9fd60da9f1a0819cecdc9;
    uint256 constant IC5y_PART2 = 0x2c8a5dc9e1941aa63ef23cb51c0d357c6b3047cf5728079d9917493350a4e7ac;

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
