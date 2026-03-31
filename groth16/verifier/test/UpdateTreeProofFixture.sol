// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library UpdateTreeProofFixture {
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

    function pubSignals() internal pure returns (uint256[5] memory values) {
        values = [
            uint256(5829984778942235508054786484586420582947187778500268001993713384889194068958),
            uint256(12649971214846735256928973055327082315338775527920953067671803034981096374020),
            uint256(111),
            uint256(0),
            uint256(10)
        ];
    }
}
