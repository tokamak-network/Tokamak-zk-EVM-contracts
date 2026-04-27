// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library UpdateTreeProofFixture {
    function pA() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x0000000000000000000000000000000006a7f8d15933c2e10233df1a29ee3490),
            uint256(0x053f07803ebecc9cca28ff4c84a5d04bb163f5bd93aa7aa18e72577a335abaa1),
            uint256(0x000000000000000000000000000000000d872501e30016c8d2b2bae675435031),
            uint256(0x576055a94da28003133792ca10963ea073bda6de21019c3ad6276133d7b44236)
        ];
    }

    function pB() internal pure returns (uint256[8] memory values) {
        values = [
            uint256(0x0000000000000000000000000000000002bca9d242979c04b8b26d5a641acac0),
            uint256(0x7318a83ce3fdf6e86ff48d8ecb5122b63d0b016e24401d1c60f3c2431bd5a9b7),
            uint256(0x00000000000000000000000000000000011e90ae82c88e6ff59f9bdab0f4951f),
            uint256(0x745a99472949c2e4c04df848e8c2b40c2d2291ee44c72b6012a3363c7bee0ee3),
            uint256(0x000000000000000000000000000000000532dac12b606525223bdfa976d9802c),
            uint256(0xf89b8a020882779870f892b1b9fc4a3ea960abda313094563f6cf6a3db8b38a8),
            uint256(0x00000000000000000000000000000000185cf02330ee4dde19c1107418bda414),
            uint256(0x7f6de3d2cd82e3e55bc00b922285175b54f89c9abc820ed9d2bb4645b81f9d84)
        ];
    }

    function pC() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x0000000000000000000000000000000004bb00f351ae4904e98e400adfa10e4d),
            uint256(0x0e87c725b07bdb65ec17597caea5b8b7195e507365f4addac106c46f87383faf),
            uint256(0x00000000000000000000000000000000180bc00e99ff8f6a4e3bc442d7084ba0),
            uint256(0xbae0288b080b1033f5bf7c16ce01f7932310ab0b12cc18cf112b2eaa8a93c96f)
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
