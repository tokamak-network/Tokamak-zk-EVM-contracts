// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library DepositGrothProofFixture {
    function pA() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x0000000000000000000000000000000000d9ba0b1bf1019fd858aee6da3c95b8),
            uint256(0xedb8d42f3c3ec7df554aaee13dccaec9fc6e597523c09b762339ed53fde56818),
            uint256(0x000000000000000000000000000000001801fa71593ed68582366f7beddb8c8b),
            uint256(0x30348ad5d73304ac579663e7e0cea6835909cda0044f6428e3fab53588c8b510)
        ];
    }

    function pB() internal pure returns (uint256[8] memory values) {
        values = [
            uint256(0x000000000000000000000000000000001011b87b0589b1dda5d8ba645c6392df),
            uint256(0x3e1ab4f52ee03c35e21b4a5a2be01862c7d51e96dd72096a9e8dd096499484b9),
            uint256(0x0000000000000000000000000000000009b76ee56a6c649201827191920babcc),
            uint256(0x8d9167d5f6536557d2bbf0d67b938e66667e1bfcf7505300b8c2fdfc219ffe1f),
            uint256(0x0000000000000000000000000000000014a03fd52eebde198b29820e7ed8c9d1),
            uint256(0xb4d598db81e9fee8c8e54b0bd0cd983168994ec19525fe0b141316f92ae6d19d),
            uint256(0x000000000000000000000000000000001134aaf8e08bfdfefd2c1f32ef5936b6),
            uint256(0xe1d895e72bdb051b7e1ffb8b6e75e9f8161ef24a843a480bad3f34ff18baa021)
        ];
    }

    function pC() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x000000000000000000000000000000000c0d51fb298627bd6d9a9e2752c7a6bf),
            uint256(0xadee39dd4e865944227726df3460c9996b77123eefe15b08dfb7a12e7bd6c2e6),
            uint256(0x000000000000000000000000000000000defeba9cdea7a9a63296296995d31fb),
            uint256(0x595eb69cd419850b62bf984b5ab503039781226df8e7ca5a9d2fa1e804a4e047)
        ];
    }
}

library WithdrawGrothProofFixture {
    function pA() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x0000000000000000000000000000000002a6247e8dbc03355fcb60e099ffb3b7),
            uint256(0x349f113f9d1d79776d94afcca65895e061f19f9e6155dba0e39e0c6df88be712),
            uint256(0x0000000000000000000000000000000008635b96db3ecb0785fdaff3e9018c5e),
            uint256(0x413de0dd7847e96bf623b2b0dbe20f9b47f23a34b537669f1c451ef7dfaa02f3)
        ];
    }

    function pB() internal pure returns (uint256[8] memory values) {
        values = [
            uint256(0x000000000000000000000000000000000d7b4820f3e68f714fbdc10478d27849),
            uint256(0xaceffe3e0139930c03f68ea6a663ba2f11479191f6cb837546c39bd6418b3a32),
            uint256(0x0000000000000000000000000000000016311a37393a9a37e54e12a8150c37c6),
            uint256(0xea85a62a52aa2c3374d69d0ea2c96a2d7277bf82e6d502d6f642c50c7fe79e32),
            uint256(0x0000000000000000000000000000000010083f9a598287efe87b7fe377edeb81),
            uint256(0x05ce84c2a7d2581a4bd7e2c57e29fe4f590cc9caaed2fcda5acdd60ff2c7f6ab),
            uint256(0x000000000000000000000000000000000059f7ee595b683a3230a2bf254538bf),
            uint256(0x573072380a0b7fdb0ef9c2b03a9ae8d977063042b8d73b1bab17b13e4163400d)
        ];
    }

    function pC() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x00000000000000000000000000000000030b4705f424630fef74403ec50ba08c),
            uint256(0xca632c714467204b099f9982604553779d3908f41f97e69ed75897bdaa91a1fb),
            uint256(0x000000000000000000000000000000001492d3857ca16530100389007f287680),
            uint256(0xed6ca46986a9e49e1599c10b1f2f5c9d675ff10a17e0d9a5d24aa5f292b64a79)
        ];
    }
}
