// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library DepositGrothProofFixture {
    function pA() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x000000000000000000000000000000000fd60ce59cdc9891344bf623d2789a32),
            uint256(0xd2278a26d2548d32b58447f929f37ddef39fa57a90519ec0933709ffa0966aae),
            uint256(0x0000000000000000000000000000000018c4fa2b07a18eaa29b4e327a213e263),
            uint256(0xafac899c1ead635716631053b2f0e92e5e2c6e0fdc53ddc54cef68069ec1afe1)
        ];
    }

    function pB() internal pure returns (uint256[8] memory values) {
        values = [
            uint256(0x000000000000000000000000000000000d68670833dea4728373daab708c8ddb),
            uint256(0x7aca9fe3f5adaa6e3cb32966f96d794e670d51330644f11309c47f12c17e64e7),
            uint256(0x0000000000000000000000000000000002a5f097f24192a7ee0af998ee4e2544),
            uint256(0xaaccb651a4db313ea4b2b4b2213dd1606ca5fcbb953c7cae5ed3244d798cbfb6),
            uint256(0x00000000000000000000000000000000056e9d2d32a5849cdaa91f7dca5374bc),
            uint256(0x321ba74e8f9fb363591f3348f4758fe791a27c8518c356b52268e0e3f94401bd),
            uint256(0x0000000000000000000000000000000017d86aea4b1f43e00b5cac7a825aaae7),
            uint256(0x7146c3cce8fa1e7f056fff81baf27220c6ba7a7222767aa3ac92ab08cc86a964)
        ];
    }

    function pC() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x000000000000000000000000000000000bbbfe50727cb56fd2cc3ad957546097),
            uint256(0x6a97968d601181c9be50381bb8fa94059bdc8ad73a613356c2cc7ee4b721508e),
            uint256(0x000000000000000000000000000000000bcc61517734538bfe322cddd1e87108),
            uint256(0x804b913a9b1df796320d274220a96e968a04b3227e4f1d559b6a09159e627b1a)
        ];
    }
}

library WithdrawGrothProofFixture {
    function pA() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x000000000000000000000000000000001974e6981d26d5052864d6e9fa8d797d),
            uint256(0xacbc704872d200819d0201d105972a69c9a181bbf5a563ee54068a4d70827747),
            uint256(0x000000000000000000000000000000001380af4feaa3369694cd1a97b75e5e01),
            uint256(0x9363c1d11d58cf98a50c854197939890294ed7e3b19a4a46c6b7ff53941ee76c)
        ];
    }

    function pB() internal pure returns (uint256[8] memory values) {
        values = [
            uint256(0x000000000000000000000000000000000fbaa4a225e9b55bfcf86a4bcefb3add),
            uint256(0x4c689d61173bf5cb94da2cfac2854e67b5f0b0afaf04bf1af607a8fa96b24773),
            uint256(0x0000000000000000000000000000000011f1cd7ee066d1ec9448feeb3ab9ace7),
            uint256(0xcd51515183793065d078e2563bbb20bc992761b6b4c19531ea6f8b4f06fec54d),
            uint256(0x000000000000000000000000000000000a9c813ae79a8f369715540158191ce5),
            uint256(0xffc623365fb4e67e0f41fa5df342c623bf3aaf48c7ac40d2ca891c49c2fc7b2f),
            uint256(0x0000000000000000000000000000000001ae99ee1a53e6e63525f38c4d53613e),
            uint256(0x10e2a9e960117eb5dc1be2674fb6d6a619a20a1ced8c1dafff28408bb523dd66)
        ];
    }

    function pC() internal pure returns (uint256[4] memory values) {
        values = [
            uint256(0x000000000000000000000000000000001884eeeba0baab880451465f854c7aa0),
            uint256(0x4fc9bfe0da038f090836f357c52deae0326c1f010c22b8e232aa4b7b1d42cb77),
            uint256(0x0000000000000000000000000000000005eaf1d7f4065809104d574977e53206),
            uint256(0xe08867f457e47f441290c349df72d59e549ce1220b107d63dea960eae2049edf)
        ];
    }
}
