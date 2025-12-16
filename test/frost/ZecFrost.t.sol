// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {ZecFrost} from "../../src/library/ZecFrost.sol";

contract ZecFrostTest is Test {
    ZecFrost zecFrost;

    function setUp() public {
        zecFrost = new ZecFrost();
    }

    function test_Verify01() public view {
        bytes32 message = 0x4141414141414141414141414141414141414141414141414141414141414141;

        uint256 px = 0x4F6340CFDD930A6F54E730188E3071D150877FA664945FB6F120C18B56CE1C09;
        uint256 py = 0x802A5E67C00A70D85B9A088EAC7CF5B9FB46AC5C0B2BD7D1E189FAC210F6B7EF;

        uint256 rx = 0x501DCFE29D881AA855BF25979BD79F751AA9536AF7A389403CD345B02D1E6F25;
        uint256 ry = 0x839AD3B762F50FE560F4688A15A1CAED522919F33928567F95BC48CBD9B8C771;

        uint256 z = 0x4FDEA9858F3E6484F1F0D64E7C17879C25F68DA8BD0E82B063CF7410DDF5A886;

        address addr;
        assembly ("memory-safe") {
            mstore(0x00, px)
            mstore(0x20, py)
            addr := and(keccak256(0x00, 0x40), sub(shl(160, 1), 1))
        }

        uint256 gasStart = gasleft();
        address result = zecFrost.verify(message, px, py, rx, ry, z);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used by FROST.verify:", gasUsed);

        assertEq(result, addr);
    }

    function test_VerifyWithInvalidPublicKey() public view {
        // bug originally found here:
        // https://github.com/chronicleprotocol/scribe/issues/56
        // merkleplant raised this topic in X and on forum:
        // https://ethresear.ch/t/you-can-kinda-abuse-ecrecover-to-do-ecmul-in-secp256k1-today/2384/19

        bytes32 message = 0x4141414141414141414141414141414141414141414141414141414141414141;

        // this bug with ecrecover happens when public key X
        // in range `[0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F)`
        // this can happen with `1 / 2^128` chance

        uint256 px = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141; // public key x >= Secp256k1.N
        uint256 py = 0x98F66641CB0AE1776B463EBDEE3D77FE2658F021DB48E2C8AC7AB4C92F83621E;

        uint256 rx = 0x0000000000000000000000000000000000000000000000000000000000000001;
        uint256 ry = 0x4218F20AE6C646B363DB68605822FB14264CA8D2587FDD6FBC750D587E76A7EE;

        uint256 z = 0x4242424242424242424242424242424242424242424242424242424242424242;

        assertEq(zecFrost.verify(message, px, py, rx, ry, z), address(0));
        assertFalse(zecFrost.isValidPublicKey(px, py));
    }

    function test_VerifyCustomParameters() public view {
        bytes32 message = 0x91be4311c2af6d02623ae6bc08eed804a9394c0ebe344a273cacc4fa06c6e80b;
        
        uint256 px = 0x65ceb565a2028bcc940074da00994958c1965a0f801fc1a06811a1195426db0b;
        uint256 py = 0x767293b33676de95ce3d0acf97e1bb0326fe7e2896d17c4df5d7055b4699445c;
        
        uint256 rx = 0x00d1c2066f3cfb50b1882a2f85655c64fa1518edb27585ac64c9c1f853383a04;
        uint256 ry = 0x475633b801338dcd6167a445926dc0e20f051266e9038be76b433c0004ff2f9c;
        
        uint256 z = 0x4ed729ad86526f2599577c051225e9c15c0cd85861872c153b338da05b0bb946;

        address expectedAddr;
        assembly ("memory-safe") {
            mstore(0x00, px)
            mstore(0x20, py)
            expectedAddr := and(keccak256(0x00, 0x40), sub(shl(160, 1), 1))
        }

        uint256 gasStart = gasleft();
        address result = zecFrost.verify(message, px, py, rx, ry, z);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used by FROST.verify (custom params):", gasUsed);
        console.log("Expected address:", expectedAddr);
        console.log("Verified address:", result);
        console.logBytes32(message);

        assertTrue(zecFrost.isValidPublicKey(px, py), "Public key should be valid");
        assertEq(result, expectedAddr, "FROST signature should verify to expected address");
    }

    function test_AddressComputationDiscrepancy() public pure {
        uint256 px = 0x65ceb565a2028bcc940074da00994958c1965a0f801fc1a06811a1195426db0b;
        uint256 py = 0x767293b33676de95ce3d0acf97e1bb0326fe7e2896d17c4df5d7055b4699445c;

        // FROST/ZecFrost way: keccak256(px || py) -> truncate to 160 bits
        address frostAddr;
        assembly ("memory-safe") {
            mstore(0x00, px)
            mstore(0x20, py)
            frostAddr := and(keccak256(0x00, 0x40), sub(shl(160, 1), 1))
        }

        // BridgeCore way: keccak256(abi.encodePacked(px, py)) -> truncate to 160 bits
        bytes32 h = keccak256(abi.encodePacked(px, py));
        address bridgeCoreAddr = address(uint160(uint256(h)));

        console.log("FROST computed address:", frostAddr);
        console.log("BridgeCore computed address:", bridgeCoreAddr);
        console.log("BridgeCore expected (from issue):", address(0x86278a8c51E0789a19F19D84ed17bCdcaB1aC9b4));

        // They should be the same since abi.encodePacked(px, py) == px || py for uint256s
        assertEq(frostAddr, bridgeCoreAddr, "Address computation should be identical");
    }
}
