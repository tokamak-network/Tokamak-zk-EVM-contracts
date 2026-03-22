// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = 0x0000000000000000000000000000000010e4b70e060f70206116de3a0d7d455b;
    uint256 constant alphax_PART2 = 0xd89390e906734663e20a0f253e177d89fd83cde560ae2568fc311bdfc91b521a;
    uint256 constant alphay_PART1 = 0x00000000000000000000000000000000011ec7dc02e461e37d8ebef89a6eb25a;
    uint256 constant alphay_PART2 = 0x487f00e3ab39d6ca68a3a89ff971590442d2b84de42349d9b16ca1dcdb63002e;
    uint256 constant betax1_PART1 = 0x0000000000000000000000000000000001ea9771b8f21a0db00485f402f1d360;
    uint256 constant betax1_PART2 = 0x11eb5229de354f1ddc2b1de7fe29ad6d66f16788de1f30921807d7f73e85d06d;
    uint256 constant betax2_PART1 = 0x0000000000000000000000000000000010b86b070d540d1b4345fdc5a5d501d1;
    uint256 constant betax2_PART2 = 0x3347ba304b26a4c412a17a40bcc239f25754e8666343cb2bd787f9b5a59c2b9f;
    uint256 constant betay1_PART1 = 0x000000000000000000000000000000000f51a7bf46e4f6a2381d39aee6a46c7a;
    uint256 constant betay1_PART2 = 0xc0a5b461f0fb6077be22810658d2e788895b7d378505dcb489a43688d82a4058;
    uint256 constant betay2_PART1 = 0x000000000000000000000000000000000e6fceb1ee55df76e64de3520720b470;
    uint256 constant betay2_PART2 = 0x5b7586f9c411f1d40fb13d1b688167e8e683a925d85574423579c53dfc9f6191;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x000000000000000000000000000000000a67f4b128fc3e94e88730abe7e7577c;
    uint256 constant deltax2_PART2 = 0xfae1bba1ff30684c87fd3d1f14e7c6bde4803acd0817d1e0205987e357a1d398;
    uint256 constant deltax1_PART1 = 0x00000000000000000000000000000000078d65909a5278a8370e0ba03c5501fd;
    uint256 constant deltax1_PART2 = 0xbd7959a8046aa832810f6ce45507e1b8e4aa6591916a78e535b128aa22847d9b;
    uint256 constant deltay2_PART1 = 0x000000000000000000000000000000000548f777352891f7feeb583b1692dd60;
    uint256 constant deltay2_PART2 = 0x925e9e5413d2cd5cc5493c00f64f1af6ee6225a5fb338675adfaacbd23aa4645;
    uint256 constant deltay1_PART1 = 0x00000000000000000000000000000000094da4e521f44638d0c12a2889ade89b;
    uint256 constant deltay1_PART2 = 0x9f73fbf0df4a19f0a86403d461beb064ab3044ed028a52e784d08c5241a16f78;

    uint256 constant IC0x_PART1 = 0x00000000000000000000000000000000158f4a32f8965f91b89cc14c1dd7a5c8;
    uint256 constant IC0x_PART2 = 0x9eb91cf3b1a9f95dd9c380d9228f91424f31ddf3504ce8b7387cfc7909c87541;
    uint256 constant IC0y_PART1 = 0x0000000000000000000000000000000010911a56993896e9ca59c9d880f37205;
    uint256 constant IC0y_PART2 = 0x2093fb02569eb6121371fd6701ce8bdc8b4ac14925e34013acedd658a9d3a911;

    uint256 constant IC1x_PART1 = 0x0000000000000000000000000000000013eb13a31e5b70ff9f158464521c6b77;
    uint256 constant IC1x_PART2 = 0x9a7bf695ad1ad5a5dac6342332f4b392036cb742eb5aa7be28d505e5bf3f4408;
    uint256 constant IC1y_PART1 = 0x00000000000000000000000000000000096490e1e1cf69760dfebe3603e88f5d;
    uint256 constant IC1y_PART2 = 0x27c3badf96d8c37b1b260f27a265b38b29d1edc05096f64d0b5188e2c3ad2441;

    uint256 constant IC2x_PART1 = 0x00000000000000000000000000000000140e7690b426da8718eaff3a14d7318c;
    uint256 constant IC2x_PART2 = 0x3f5989f277a6f6e86433e34ea3e33ce77a8313c027844b28261bd8530adfdb60;
    uint256 constant IC2y_PART1 = 0x000000000000000000000000000000000ed303f2a92ccaa465aa49a853101cc6;
    uint256 constant IC2y_PART2 = 0xe859c4ddeeba5fb8d4389feb9fd68c6bedce13e6e5fb84d9e92f3dbeeb9710ef;

    uint256 constant IC3x_PART1 = 0x0000000000000000000000000000000002fd137034f9c0a9401c8b30359d614d;
    uint256 constant IC3x_PART2 = 0xa33617aa3dc5ecc1154dd20ff64518498423fce3573cce72caa687c0da44d7f5;
    uint256 constant IC3y_PART1 = 0x000000000000000000000000000000000df61c810803b076d6b2d7c2ea87e816;
    uint256 constant IC3y_PART2 = 0x0db2ded08b0a04e35181824198ce306369eeb16f51bdf30a537a9a85ed947d00;

    uint256 constant IC4x_PART1 = 0x000000000000000000000000000000000610fddd238b43789009bf18744ae299;
    uint256 constant IC4x_PART2 = 0x4c10c032da7b1d349b99d3fb59da9d65c785870f6fa8d40f425940042647fc36;
    uint256 constant IC4y_PART1 = 0x00000000000000000000000000000000180ca50fedd1989c5a8c7a44c58a70a1;
    uint256 constant IC4y_PART2 = 0x0e535d304c5310acdd3f678867154ee186f2fb2eeae3d8d79a23b0eb93276841;

    uint256 constant IC5x_PART1 = 0x000000000000000000000000000000000aac208b930367e9d1775692c09d041a;
    uint256 constant IC5x_PART2 = 0x21c43a0a109eb7eeb127bb4fecf78a8675cc1f2391291d1d79c36e9fa707373d;
    uint256 constant IC5y_PART1 = 0x0000000000000000000000000000000005ab41b90f3903c6a8f762f4fc230e56;
    uint256 constant IC5y_PART2 = 0x9f6ccc86c865bca1c422b59cc87ab99078b3f7e1797c85b6b8ebe509581d7089;

    uint256 constant IC6x_PART1 = 0x0000000000000000000000000000000012e750e06d74df031cf02daf696ac653;
    uint256 constant IC6x_PART2 = 0xcf594ce3effa6a1003420e0365dc8d00257bbcaaaacc523fe1e1c8877cc4b4ec;
    uint256 constant IC6y_PART1 = 0x0000000000000000000000000000000016f0067d5a16bb57470317bb29bc2739;
    uint256 constant IC6y_PART2 = 0x993ebcd6d682b4a1ac7fa794bb7ce55002ec514bb0fd079ae42645a506e21e18;

    uint256 constant IC7x_PART1 = 0x000000000000000000000000000000001555a4247ddba92c9c786220cc3a7467;
    uint256 constant IC7x_PART2 = 0x2f91d06ef146300dfed9f7db3b3448420dcca9839fb17b3f2f86ba4dbdaef32c;
    uint256 constant IC7y_PART1 = 0x00000000000000000000000000000000144ebbf453c24e4f6733a7bcd341b96a;
    uint256 constant IC7y_PART2 = 0xb9aa3f80c759c70e095d53cf44193892c5b1349d91113e627c98c714f146026c;

    uint16 constant pVk = 0;
    uint16 constant pPairing = 128;
    uint16 constant pLastMem = 1664;

    function verifyProof(
        uint256[4] calldata _pA,
        uint256[8] calldata _pB,
        uint256[4] calldata _pC,
        uint256[7] calldata _pubSignals
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

                g1_mulAccC(_pVk, IC7x_PART1, IC7x_PART2, IC7y_PART1, IC7y_PART2, calldataload(add(pubSignals, 192)))

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

            checkField(calldataload(add(_pubSignals, 192)))

            let isValid := checkPairing(_pA, _pB, _pC, _pubSignals, pMem)
            mstore(0, isValid)
            return(0, 0x20)
        }
    }
}
