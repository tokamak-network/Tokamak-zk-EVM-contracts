// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library UpdateTreeProofFixture {
    function pA() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x0000000000000000000000000000000007f7f7b58483164ee873eabeb376aed1),
            uint256(0xfc7a798f5dd4f33a40ba8cb8c807ae488bbd9fabe3de26619f1f1ad30facd43b),
            uint256(0x00000000000000000000000000000000089618a76e13590142892870e398e46d),
            uint256(0x26554612a3281e5a99d64057c8dccabb51b8ea1ec3d9725ac8e1bc2a1d34c5aa)
        ];
    }

    function pB() internal pure returns (uint256[8] memory values) {
        values = [
            uint256(0x000000000000000000000000000000000ca3eab978516dcfd9cdc860d2bfaa9b),
            uint256(0x231ba86789548b9cf327df3feafede44444dacbed5fcab53c9dcb7cac923c4e5),
            uint256(0x000000000000000000000000000000000dfc600c9db1bad77fb5edec09b425c4),
            uint256(0x4bec77c7279958d4996dee3442ed7b59363cf379786a10ae49d013faa38d0df8),
            uint256(0x0000000000000000000000000000000011e9756903d4bb76b27d0d8cce4f6a77),
            uint256(0x7ca8e3bd9d6ec2224d344394a88e1b5178d3a395b559266f7084cf4bc773ae52),
            uint256(0x0000000000000000000000000000000008976f905fb89ad32a1cadc0cb181dfa),
            uint256(0x6d6a40f25cb40d6ee82a5f47eeb7703b04e2e47f4c54a0a7bbead094c6db30cf)
        ];
    }

    function pC() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x000000000000000000000000000000000f9d8ee1542fbaea1628733ab0492943),
            uint256(0x87c3761742e50afb922622949089178a9f8bf6f4cb614b41590a8b7966c02d55),
            uint256(0x000000000000000000000000000000000fecbc5bc1238cccef08b9acdd5b7c5f),
            uint256(0x04f3fc97e3720290fcf3c56efa12a7b7e37854705381cef6b114637df0496dce)
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
