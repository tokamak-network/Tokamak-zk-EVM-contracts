// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library UpdateTreeProofFixture {
    function pA() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x00000000000000000000000000000000026365722b366c6df4f076791acc6f8c),
            uint256(0x5056144a9a4d6b773d8615baa84529fac9fb55f97d7c51e89acdb4767fa71bf8),
            uint256(0x000000000000000000000000000000001679363f20543d4d8f103616c37cb8f7),
            uint256(0x8b2ff4a8f0a2de3d04dd14a038e3ecbe27e367a5ceeafe021b97616585651b7e)
        ];
    }

    function pB() internal pure returns (uint256[8] memory values) {
        values = [
            uint256(0x0000000000000000000000000000000010082c4e9127b4979dac24639e1f9bc3),
            uint256(0xf4176dfe1cd1fb279dbe71cafaf809b9437dec4c532e9e67e7e55a15c481c055),
            uint256(0x0000000000000000000000000000000018b538089a8bc7eff723a4323a9b1bf3),
            uint256(0x2d2ddd3c247b654cb5f10c16a6e2d168ea7945993476c67f61248c0ab0c21099),
            uint256(0x000000000000000000000000000000000f29b7b7e33bca2020451b614c8844f1),
            uint256(0xd38057244aea38d89439e7a76c9d98878064c2defb21d63b5f0941d007d37342),
            uint256(0x00000000000000000000000000000000112bd0d591aaf60610fbab2edca5a16d),
            uint256(0xc5230fa9550b1248b4962a79b47c9ca8c63bba97c86468c4fcd55589ee6b86e8)
        ];
    }

    function pC() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x0000000000000000000000000000000016c3c0acaa86058464829ab1bbc2a898),
            uint256(0x851d5904ef090445fff7bd52dbb9dba982ce3f5a63d737de9fd99c68389e6917),
            uint256(0x0000000000000000000000000000000009dc14ee3e358748a3a8e4b9c9eb9799),
            uint256(0x053dc61b5af845712464f9d4211a00aade787e1a317ea32a80daab1fce35b348)
        ];
    }

    function pubSignals() internal pure returns (uint256[5] memory values) {
        values = [
            uint256(17652037977464836264079014691140456808166939095961837218105254669963832997725),
            uint256(32329471076278628194139248846839881930558157276338660520225203111849212182963),
            uint256(111),
            uint256(0),
            uint256(10)
        ];
    }
}
