// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library DepositGrothProofFixture {
    function pA() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x000000000000000000000000000000000ef1bd2d6a2bd84924cc34df4f82bb02),
            uint256(0x6f9dbce60ddebcfa4c8d23c51a12ec64419473c854b598517f261c74a242b7ea),
            uint256(0x000000000000000000000000000000001029dbf1c5840f5b342dc1e691e7aeda),
            uint256(0x6ea2cd1480667dec1d882c585dcd0db84ca4b2a3c695c7daf3bb28cf4f7e7021)
        ];
    }

    function pB() internal pure returns (uint256[8] memory values) {
        values = [
            uint256(0x00000000000000000000000000000000152c3a5b70d101e9c9b58edb7d2c7954),
            uint256(0x621729c0c85ed60a7f4b96b4f5363625c61f7694555cfb885e5f5132dd5dbae8),
            uint256(0x0000000000000000000000000000000002ff7f1598a1a31b06a96148ae8d3312),
            uint256(0x46476fcd27df2a1bdfab1355c6a735e10255ac80443265ee6764457fbe4e1cec),
            uint256(0x000000000000000000000000000000000d105718f34a3e1e11395a4c9eb04490),
            uint256(0xd17cb7bda54a496a2265c6b68758e6f5ac74022bbb947e1e2d81149aae47e6e0),
            uint256(0x000000000000000000000000000000000118edcb14e7a306fa350560f00aa97c),
            uint256(0x1c81bf7be17db3e5d8fd3fbc64f46f75d4a0ae04ff4f6e1ed9d835d7b28099e8)
        ];
    }

    function pC() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x000000000000000000000000000000000998e3a717143800ea01a6c080c333b5),
            uint256(0xb5bcb8dd39a4dbb16cfd4ff957232e27daa49b5732e90b990130dfdac8a05099),
            uint256(0x000000000000000000000000000000000ce4b3fe9e61d656b5b0c30fc2cbb4cd),
            uint256(0x14b0f37022d4786f56b882b2067eef171b8c3fca3c33da3b1dce05d916b86a5b)
        ];
    }
}

library WithdrawGrothProofFixture {
    function pA() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x0000000000000000000000000000000008d59b51cc9b8f85a4df14a0e423c657),
            uint256(0x2d97045ac01ff61b5aeb73e94ba506a3a84ae86ef11945c864579abccecb8479),
            uint256(0x000000000000000000000000000000000ffced2ad4b6be082711c0edf7404164),
            uint256(0x583a0e7818fc247f6c65df162028281377800fc72e3234887b87f912cf18cc12)
        ];
    }

    function pB() internal pure returns (uint256[8] memory values) {
        values = [
            uint256(0x00000000000000000000000000000000124c1897e2f5208230275e384fd5248c),
            uint256(0x817e6061d7cd769fb02b2c9707b36c9cc4df91588d19319f474e3421b5e4ed57),
            uint256(0x00000000000000000000000000000000171b2cbb46be9486e6c42fe86a6efb3c),
            uint256(0xd93b1800394c71d869a0cc23b90a88b3e75f6af0eb73be03f079fee54f842191),
            uint256(0x00000000000000000000000000000000021dd2c589e9dff5bcafc335b705a34a),
            uint256(0x536d61d351dafe9cdd477e30084eb4c298fac084cd85ac9b27977dc6a7ce1ff3),
            uint256(0x00000000000000000000000000000000125b592de3f0bd0a3e265ec22fbb9676),
            uint256(0x70f39035d1ca729ca7a2cb4018afa8137dd6e7c70e6e19e1167f605640a774fd)
        ];
    }

    function pC() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x000000000000000000000000000000000d19e8329c039bd8c95404e4db916c8b),
            uint256(0x31b6dccef2ec90b7c89a030322f1c3d736abb98467c7a309631664a212431fb8),
            uint256(0x0000000000000000000000000000000012d7b7aad7d110acf6c4f9fa8ac6fe1f),
            uint256(0x60938e2f58a85c72838182f7c52d5d7968647d5fce08d7ce5c9ad660f306154a)
        ];
    }
}
