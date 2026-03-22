// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library UpdateTreeProofFixture {
    function pA() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x0000000000000000000000000000000019a5a4231e7a14480952840448c28d91),
            uint256(0x886e07d5680ca539eb82f3882a9449254067627bcc1f180fa4c8c43312dfbc9c),
            uint256(0x000000000000000000000000000000001159a55215c308dca5c6573a4faad82d),
            uint256(0x6ef78c60a1906ed261b1eb40feccada90d8f7af00fb81d59d2fc9df9bc5227d9)
        ];
    }

    function pB() internal pure returns (uint256[8] memory values) {
        values = [
            uint256(0x000000000000000000000000000000000d090fb64958bc2083221557ca8cabae),
            uint256(0x187122284480d7c0698ede958f708a9398ce97e692243514a2fe78e69022cf23),
            uint256(0x000000000000000000000000000000000f91ffdb3fe6bc9081cc410114de04d2),
            uint256(0x83bb4bfd1850e85a139a6c88dbdebbc87e201a00ef15f4cf188d55c94d70af25),
            uint256(0x0000000000000000000000000000000011f7fc792c113c0ca1ac5fe52df5dfbb),
            uint256(0x3bd88802c5167c4f58835757da5e47ebb0049235788aae8710d9c78b99aaddbe),
            uint256(0x00000000000000000000000000000000128f144d7b24eff79f10c6eacbd23a8f),
            uint256(0xd1ebdac743bf944be6be8685be43ff633e6a0e3ea746ade4cd13fa05dc083e9c)
        ];
    }

    function pC() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x0000000000000000000000000000000016b92fe62035a3bc21aee966cf3de39d),
            uint256(0x3b009690613dd1f16d3f687f47d8c252c05b5b8a861693e1d6dfdfbdf4d60b62),
            uint256(0x000000000000000000000000000000000c25211b60a2d4416cbf2afa5409135d),
            uint256(0x1e0961141489e6f7ea5ec492256be77277f4324dcb0d011d4ef94d9644f1f6ce)
        ];
    }

    function pubSignals() internal pure returns (uint256[7] memory values) {
        values = [
            uint256(44531616947785316141458048536843290934428652898050174825548578130187460526044),
            uint256(1256772619741781574832071795141552311568607260746174091637092412903694395436),
            uint256(111),
            uint256(111),
            uint256(7),
            uint256(111),
            uint256(10)
        ];
    }
}
