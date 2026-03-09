// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "./Groth16Verifier128LeavesIC1.sol";
import "./Groth16Verifier128LeavesIC2.sol";

contract Groth16Verifier128Leaves {
    // BLS12-381 Scalar field modulus (r)
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    // BLS12-381 Base field modulus (q) - split into two parts for 48-byte representation
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    // Verification Key constants for 128 leaves
    uint256 internal constant alphax_PART1 = 0x00000000000000000000000000000000153ce34e3174dd1a7baae7989a950626;
    uint256 internal constant alphax_PART2 = 0x933c51ee499e126b2ddd7d1f5abd2f12ffcd8b2e46a73d87a45b3559dcdde2f4;
    uint256 internal constant alphay_PART1 = 0x00000000000000000000000000000000160a4b2e5f81fed6ba7c401d324521b6;
    uint256 internal constant alphay_PART2 = 0x5e1d36d8d21b5872f1a863ae7f552ee902b09fb6123405189a8c388aa759ab6c;

    uint256 constant betax1_PART1 = 0x000000000000000000000000000000001198aa9397180fdb72fa98b83e26e620;
    uint256 constant betax1_PART2 = 0x6c11a2437379a7fcbd6a98565a64fa809b80b722f439e3e8607d21526ddf6432;
    uint256 constant betax2_PART1 = 0x000000000000000000000000000000000490a2769d030c5ef37b830b87942e3b;
    uint256 constant betax2_PART2 = 0x6a128ca096f0a395cb376978bd79e0630f7c942e9e734d92d7c301820da7dfdd;
    uint256 constant betay1_PART1 = 0x00000000000000000000000000000000066c43799ca11a2858f9851866479aff;
    uint256 constant betay1_PART2 = 0x5067f8cc4bd6ef1531f373aa554364c084825f063980fd12b844bc8dc8d1c960;
    uint256 constant betay2_PART1 = 0x0000000000000000000000000000000012898d39a78666b136ce8524e41d1c42;
    uint256 constant betay2_PART2 = 0x146f103b4be7ccf3b46c1ebff5038237fdffbd8fdfd15c7c50ab10e1f63bd402;

    uint256 constant gammax1_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax1_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammax2_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax2_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay1_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay2_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;

    uint256 constant deltax1_PART1 = 0x0000000000000000000000000000000000e7cf36cd7af398517c38fe5369290a;
    uint256 constant deltax1_PART2 = 0x98db2b905b6bec746f7ad06275e0b5a6da82f16e87dec8bc8ea4b7678292d037;
    uint256 constant deltax2_PART1 = 0x000000000000000000000000000000000fa234f167ec7c99d5c41569688e9059;
    uint256 constant deltax2_PART2 = 0x176b7a19cfd39942976f78a7bbe7d575344ad6a1ee8e6fe484485472c604d5c6;
    uint256 constant deltay1_PART1 = 0x00000000000000000000000000000000058fad8d35d4558bfa929f30f74cacda;
    uint256 constant deltay1_PART2 = 0x47c1b9f1790c2a66bc56d6ca2149bc54caad97fdaa3e6e83d1fe8b17a6611742;
    uint256 constant deltay2_PART1 = 0x000000000000000000000000000000000265513799ca7a0875c58b7ec8f27837;
    uint256 constant deltay2_PART2 = 0x6e91cfa4ff1ac8fcf476dfbe8d1a55c79a6b4bc72a193465936da637b91079ed;

    // References to the IC constants contracts
    Groth16Verifier128LeavesIC1 public icContract1;
    Groth16Verifier128LeavesIC2 public icContract2;

    // Memory layout for pairing check
    uint16 constant pPairing = 1408;
    uint16 constant pVk = 0; 
    uint16 constant pLastMem = 1664;

    constructor(address _icContract1, address _icContract2) {
        icContract1 = Groth16Verifier128LeavesIC1(_icContract1);
        icContract2 = Groth16Verifier128LeavesIC2(_icContract2);
    }

    function verifyProof(
        uint256[4] calldata _pA,
        uint256[8] calldata _pB,
        uint256[4] calldata _pC,
        uint256[259] calldata _pubSignals
    ) public view returns (bool) {
        assembly {
            // G1 function to multiply a G1 value(x,y) to value in an address
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

            function getICValues1(index, ic_contract_addr) -> x0, x1, y0, y1 {
                let mIn := mload(0x40)
                
                // Prepare call data for getIC1(index)
                mstore(mIn, 0xf231279100000000000000000000000000000000000000000000000000000000) // getIC1 function selector
                mstore(add(mIn, 4), index)
                
                let success := staticcall(gas(), ic_contract_addr, mIn, 36, mIn, 128)
                if iszero(success) {
                    mstore(0, 0)
                    return(0, 0x20)
                }
                
                x0 := mload(mIn)
                x1 := mload(add(mIn, 32))
                y0 := mload(add(mIn, 64))
                y1 := mload(add(mIn, 96))
            }

            function getICValues2(index, ic_contract_addr) -> x0, x1, y0, y1 {
                let mIn := mload(0x40)
                
                // Prepare call data for getIC2(index)
                mstore(mIn, 0x49d837fe00000000000000000000000000000000000000000000000000000000) // getIC2 function selector
                mstore(add(mIn, 4), index)
                
                let success := staticcall(gas(), ic_contract_addr, mIn, 36, mIn, 128)
                if iszero(success) {
                    mstore(0, 0)
                    return(0, 0x20)
                }
                
                x0 := mload(mIn)
                x1 := mload(add(mIn, 32))
                y0 := mload(add(mIn, 64))
                y1 := mload(add(mIn, 96))
            }

            function checkPairing(pA, pB, pC, pubSignals, pMem, ic_contract_addr1, ic_contract_addr2) -> isOk {
                let _pPairing := add(pMem, pPairing)
                let _pVk := add(pMem, pVk)

                // Get IC0 values and store (always from contract 1)
                let ic0_x0, ic0_x1, ic0_y0, ic0_y1 := getICValues1(0, ic_contract_addr1)
                mstore(_pVk, ic0_x0)
                mstore(add(_pVk, 32), ic0_x1)
                mstore(add(_pVk, 64), ic0_y0)
                mstore(add(_pVk, 96), ic0_y1)

                // Compute the linear combination vk_x using external IC values
                // Process first 128 signals (indices 1-128) from IC1
                for { let i := 1 } lt(i, 129) { i := add(i, 1) } {
                    let ic_x0, ic_x1, ic_y0, ic_y1 := getICValues1(i, ic_contract_addr1)
                    let pubSignalOffset := mul(sub(i, 1), 32)
                    g1_mulAccC(_pVk, ic_x0, ic_x1, ic_y0, ic_y1, calldataload(add(pubSignals, pubSignalOffset)))
                }

                // Process remaining 131 signals (indices 129-259) from IC2
                for { let i := 129 } lt(i, 260) { i := add(i, 1) } {
                    let ic_x0, ic_x1, ic_y0, ic_y1 := getICValues2(sub(i, 129), ic_contract_addr2)
                    let pubSignalOffset := mul(sub(i, 1), 32)
                    g1_mulAccC(_pVk, ic_x0, ic_x1, ic_y0, ic_y1, calldataload(add(pubSignals, pubSignalOffset)))
                }

                // -A (48-byte BLS12-381 format with proper base field negation)
                mstore(_pPairing, calldataload(pA)) // _pA[0][0] (x_PART1)
                mstore(add(_pPairing, 32), calldataload(add(pA, 32))) // _pA[0][1] (x_PART2)
                
                // Negate y-coordinate using proper BLS12-381 base field arithmetic: q - y
                let y_high := calldataload(add(pA, 64)) // y_PART1 (high part)
                let y_low := calldataload(add(pA, 96)) // y_PART2 (low part)

                let neg_y_high, neg_y_low
                let borrow := 0

                // Correct BLS12-381 field negation: q - y where q = Q_MOD_PART1 || Q_MOD_PART2
                // Handle the subtraction properly with borrowing
                switch lt(Q_MOD_PART2, y_low)
                case 1 {
                    // Need to borrow from high part
                    neg_y_low := sub(Q_MOD_PART2, y_low)
                    neg_y_low := add(neg_y_low, not(0)) // Add 2^256
                    neg_y_low := add(neg_y_low, 1)
                    borrow := 1
                }
                default {
                    neg_y_low := sub(Q_MOD_PART2, y_low)
                }
                
                // Subtract high part with borrow
                neg_y_high := sub(sub(Q_MOD_PART1, y_high), borrow)

                mstore(add(_pPairing, 64), neg_y_high) // _pA[1][0] (-y_PART1)
                mstore(add(_pPairing, 96), neg_y_low) // _pA[1][1] (-y_PART2)

                // B (48-byte BLS12-381 format)
                // B G2 point order: x1, x0, y1, y0
                mstore(add(_pPairing, 128), calldataload(add(pB, 64))) // x1_PART1
                mstore(add(_pPairing, 160), calldataload(add(pB, 96))) // x1_PART2
                mstore(add(_pPairing, 192), calldataload(pB)) // x0_PART1
                mstore(add(_pPairing, 224), calldataload(add(pB, 32))) // x0_PART2
                mstore(add(_pPairing, 256), calldataload(add(pB, 192))) // y1_PART1
                mstore(add(_pPairing, 288), calldataload(add(pB, 224))) // y1_PART2
                mstore(add(_pPairing, 320), calldataload(add(pB, 128))) // y0_PART1
                mstore(add(_pPairing, 352), calldataload(add(pB, 160))) // y0_PART2

                // alpha1 (48-byte format) - PAIR 4 G1
                mstore(add(_pPairing, 384), alphax_PART1)
                mstore(add(_pPairing, 416), alphax_PART2)
                mstore(add(_pPairing, 448), alphay_PART1)
                mstore(add(_pPairing, 480), alphay_PART2)

                // beta2 G2 point order: x1, x0, y1, y0
                mstore(add(_pPairing, 512), betax1_PART1) // x0_PART1
                mstore(add(_pPairing, 544), betax1_PART2) // x0_PART2
                mstore(add(_pPairing, 576), betax2_PART1) // x1_PART1
                mstore(add(_pPairing, 608), betax2_PART2) // x1_PART2
                mstore(add(_pPairing, 640), betay1_PART1) // y0_PART1
                mstore(add(_pPairing, 672), betay1_PART2) // y0_PART2
                mstore(add(_pPairing, 704), betay2_PART1) // y1_PART1
                mstore(add(_pPairing, 736), betay2_PART2) // y1_PART2

                // vk_x (48-byte format from G1 point) - PAIR 2 G1
                mstore(add(_pPairing, 768), mload(add(pMem, pVk))) // x_PART1
                mstore(add(_pPairing, 800), mload(add(pMem, add(pVk, 32)))) // x_PART2
                mstore(add(_pPairing, 832), mload(add(pMem, add(pVk, 64)))) // y_PART1
                mstore(add(_pPairing, 864), mload(add(pMem, add(pVk, 96)))) // y_PART2

                // gamma2 G2 point order: x1, x0, y1, y0
                mstore(add(_pPairing, 896), gammax1_PART1) // x1_PART1
                mstore(add(_pPairing, 928), gammax1_PART2) // x1_PART2
                mstore(add(_pPairing, 960), gammax2_PART1) // x0_PART1
                mstore(add(_pPairing, 992), gammax2_PART2) // x0_PART2
                mstore(add(_pPairing, 1024), gammay1_PART1) // y1_PART1
                mstore(add(_pPairing, 1056), gammay1_PART2) // y1_PART2
                mstore(add(_pPairing, 1088), gammay2_PART1) // y0_PART1
                mstore(add(_pPairing, 1120), gammay2_PART2) // y0_PART2

                // C (48-byte BLS12-381 format) - PAIR 3 G1
                mstore(add(_pPairing, 1152), calldataload(pC)) // _pC[0][0] (x_PART1)
                mstore(add(_pPairing, 1184), calldataload(add(pC, 32))) // _pC[0][1] (x_PART2)
                mstore(add(_pPairing, 1216), calldataload(add(pC, 64))) // _pC[1][0] (y_PART1)
                mstore(add(_pPairing, 1248), calldataload(add(pC, 96))) // _pC[1][1] (y_PART2)

                // delta2 G2 point order: x1, x0, y1, y0
                mstore(add(_pPairing, 1280), deltax1_PART1) // x0_PART1
                mstore(add(_pPairing, 1312), deltax1_PART2) // x0_PART2
                mstore(add(_pPairing, 1344), deltax2_PART1) // x1_PART1
                mstore(add(_pPairing, 1376), deltax2_PART2) // x1_PART2
                mstore(add(_pPairing, 1408), deltay1_PART1) // y0_PART1
                mstore(add(_pPairing, 1440), deltay1_PART2) // y0_PART2
                mstore(add(_pPairing, 1472), deltay2_PART1) // y1_PART1
                mstore(add(_pPairing, 1504), deltay2_PART2) // y1_PART2

                let success := staticcall(sub(gas(), 2000), 0x0f, _pPairing, 1536, _pPairing, 0x20)

                isOk := and(success, mload(_pPairing))
            }

            let pMem := mload(0x40)
            mstore(0x40, add(pMem, pLastMem))

            // Check the pairing
            let ic1_addr := sload(icContract1.slot)
            let ic2_addr := sload(icContract2.slot)
            let isValid := checkPairing(_pA, _pB, _pC, _pubSignals, pMem, ic1_addr, ic2_addr)
            
            mstore(0, isValid)
            return(0, 0x20)
        }
    }

    // Backward-compatible overload for legacy tests expecting 257 public signals.
    function verifyProof(
        uint256[4] calldata _pA,
        uint256[8] calldata _pB,
        uint256[4] calldata _pC,
        uint256[257] calldata _pubSignals
    ) external view returns (bool) {
        uint256[259] memory expanded;
        for (uint256 i = 0; i < 257; i++) {
            expanded[i] = _pubSignals[i];
        }
        return this.verifyProof(_pA, _pB, _pC, expanded);
    }
}
