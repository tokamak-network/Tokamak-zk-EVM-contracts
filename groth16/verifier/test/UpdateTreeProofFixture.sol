// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library UpdateTreeProofFixture {
    function pA() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x000000000000000000000000000000000db326cef14c00b65d580b7d61c71c23),
            uint256(0x032aa43f98af01865f5afb042e9256ddcde98d538bb950cd3965c4df4eca287b),
            uint256(0x00000000000000000000000000000000155b871a57d757e530b044a258ad3e24),
            uint256(0x4fd56ac1e71c72d868e90e027cb71f1a6c86939c4c560dc6076b12d3ea6b0075)
        ];
    }

    function pB() internal pure returns (uint256[8] memory values) {
        values = [
            uint256(0x0000000000000000000000000000000015585e995ee9101af71ff54b585e09b6),
            uint256(0xe297f43ba3f6d08aae704b60ef74a43aa21c3f57811b2835ef352c7be21e2ea2),
            uint256(0x0000000000000000000000000000000007de3432b8b3ba3e3f778b9e271baafa),
            uint256(0x6d7e436190aaf33eda8bba8c64d3f7aae7e39c3742edd1bd5cf076a962f69167),
            uint256(0x00000000000000000000000000000000041d01ccc71601168d547e39e68005ab),
            uint256(0xb0377bf31e2e19d7a6db7adf03dd462af9a08a37125435ca7738a1173fce371e),
            uint256(0x00000000000000000000000000000000155fd16f613f018309b9f42f7e23c760),
            uint256(0xe66dafd0da8caa072dcc507940964a08afce16bdb909dd80e59ef1f609b3ce99)
        ];
    }

    function pC() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x000000000000000000000000000000000d0bb9f6f09a5a4b169edbf04f5ba3ff),
            uint256(0xfbe8bab87d67a2244210e821bb2fa1765ebea58f934126f6650a3e2c9b42059a),
            uint256(0x000000000000000000000000000000000ad48d6ad7e731ebdef8725f5d0401f1),
            uint256(0xf6dfc937628a92cfcf03b26f5e4e86980f4b13e45bb536596102d8dce4c83465)
        ];
    }

    function pubSignals() internal pure returns (uint256[5] memory values) {
        values = [
            uint256(24945907954024293787177432702322299921976142807026898956788601490926336931348),
            uint256(11491148064932883221377359773083833348868990225682934625748592324693145747493),
            uint256(111),
            uint256(0),
            uint256(10)
        ];
    }
}
