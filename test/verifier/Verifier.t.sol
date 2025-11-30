// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {TokamakVerifier} from "../../src/verifier/TokamakVerifier.sol";

import "forge-std/console.sol";

contract testTokamakVerifier is Test {
    address owner;

    TokamakVerifier verifier;

    uint128[] public serializedProofPart1;
    uint256[] public serializedProofPart2;
    uint128[] public preprocessedPart1;
    uint256[] public preprocessedPart2;
    uint256[] public publicInputs;
    uint256 public smax;

    function setUp() public virtual {
        verifier = new TokamakVerifier();

        owner = makeAddr("owner");
        vm.startPrank(owner);
        vm.stopPrank();

        // serializedProofPart1: First 16 bytes (32 hex chars) of each coordinate
        // serializedProofPart2: Last 32 bytes (64 hex chars) of each coordinate
        // preprocessedPart1: First 16 bytes (32 hex chars) of each preprocessed committment coordinate
        // preprocessedPart2: last 32 bytes (64 hex chars) of each preprocessed committment coordinate


        /*
        {
  "preprocess_entries_part1": [
    "0x0009bbc7b057876cfc754a192e990683",
    "0x1508f2445c632c43eb3f9df4fc2f1894",
    "0x155cb5eeafb6e4cf7147420e1ce64b17",
    "0x150e9343bcaa1cac0acb160871c5c886"
  ],
  "preprocess_entries_part2": [
    "0x2516192ae1c6b963f3f8e0a1a88b9d669ddbb70cce11452260f4a7c0e71bdbd7",
    "0x60754cda6595f02b2696e5fad29df24e0c9343af6ef16804484b7253261564da",
    "0x6637521519a48e13f11e77f2f3b61bd40ea0a7c2d8d6455b908cd0d943fefa65",
    "0x5bab1505911b91f98e0a7515340ca6bf507c7b7286aff2c079d64acc3a9a26f8"
  ]
}
        */

        // PREPROCESSED PART 1 (First 16 bytes - 32 hex chars)
        preprocessedPart1.push(0x0009bbc7b057876cfc754a192e990683);
        preprocessedPart1.push(0x1508f2445c632c43eb3f9df4fc2f1894);
        preprocessedPart1.push(0x155cb5eeafb6e4cf7147420e1ce64b17);
        preprocessedPart1.push(0x150e9343bcaa1cac0acb160871c5c886);

        // PREPROCESSED PART 2 (Last 32 bytes - 64 hex chars)
        preprocessedPart2.push(0x2516192ae1c6b963f3f8e0a1a88b9d669ddbb70cce11452260f4a7c0e71bdbd7);
        preprocessedPart2.push(0x60754cda6595f02b2696e5fad29df24e0c9343af6ef16804484b7253261564da);
        preprocessedPart2.push(0x6637521519a48e13f11e77f2f3b61bd40ea0a7c2d8d6455b908cd0d943fefa65);
        preprocessedPart2.push(0x5bab1505911b91f98e0a7515340ca6bf507c7b7286aff2c079d64acc3a9a26f8);

        // SERIALIZED PROOF PART 1 (First 16 bytes - 32 hex chars)
        serializedProofPart1.push(0x121663f41d6fa5c8cb9cd49c8fcae320);
        serializedProofPart1.push(0x1333f45f71fbcad419367b462ad0e90f);
        serializedProofPart1.push(0x112e18661808e31a337cc7d5a79edbf9);
        serializedProofPart1.push(0x0eaea5127fd4d75bd943061728d5cde4);
        serializedProofPart1.push(0x1996ae953020a851b0003b6d50fd164e);
        serializedProofPart1.push(0x02f55c316255c1e9782a54afae438de8);
        serializedProofPart1.push(0x19c8d9eb89b417e6ea0680e59371ca1c);
        serializedProofPart1.push(0x0ff1af66fe6c958fb3c6be6dc48be4a4);
        serializedProofPart1.push(0x0179e53a02e36a2daaa01bb877f8da51);
        serializedProofPart1.push(0x10b498feb37b670825920a43573b9142);
        serializedProofPart1.push(0x122747d3854e82a1c6afcb0db2c21ae5);
        serializedProofPart1.push(0x0a4d79138ce50f430ff41afc6a206c8d);
        serializedProofPart1.push(0x0838b54a737fea11fed3ceb89e070a5b);
        serializedProofPart1.push(0x06c4c50dcf1c1d9c9e2f51cd11316956);
        serializedProofPart1.push(0x10b3e8d3f4961c6d8d2fe01d16def310);
        serializedProofPart1.push(0x117c46df613424b756b8853933331770);
        serializedProofPart1.push(0x09d8eeafad65649718c39c7c2528128a);
        serializedProofPart1.push(0x16695f86b881a42a3b4da021d40dc620);
        serializedProofPart1.push(0x19975643c79ca34372eb303d0186620a);
        serializedProofPart1.push(0x0cf72c8c7f890c874e43180a4d24f12d);
        serializedProofPart1.push(0x0bce3b3f1be238339293d2c9a3b3db82);
        serializedProofPart1.push(0x0cf82999b647fbd41553b072d489191d);
        serializedProofPart1.push(0x0d917e89d545555e715924b9c29a58ea);
        serializedProofPart1.push(0x050194b4e0e0c6c2faf75c51f20b61ad);
        serializedProofPart1.push(0x02d0c2bee80fdd0e7c27131af55d4920);
        serializedProofPart1.push(0x05bbf9d1cd69378923d56d26be264b94);
        serializedProofPart1.push(0x0bd2e5685527871301a5b067bc317717);
        serializedProofPart1.push(0x113dead20cf5cefaa00262a2050fc8a1);
        serializedProofPart1.push(0x14a749704d6b9cdbb614f4750a2074f9);
        serializedProofPart1.push(0x08eaa426f763715df29be1420fc00fba);
        serializedProofPart1.push(0x12dd663342c13b7908f588620aeee6f2);
        serializedProofPart1.push(0x10b08fb0156d94d5d6a001e429a7046c);
        serializedProofPart1.push(0x14a749704d6b9cdbb614f4750a2074f9);
        serializedProofPart1.push(0x08eaa426f763715df29be1420fc00fba);
        serializedProofPart1.push(0x13159b2f873ef370b1b193c6450cf12c);
        serializedProofPart1.push(0x0ddf69843e1e095b00ba231036396046);
        serializedProofPart1.push(0x0ab5942c5bb66e34e4734be6d44f3e68);
        serializedProofPart1.push(0x13804eb0ea936b578b4f9dc913489055);

        // SERIALIZED PROOF PART 2 (Last 32 bytes - 64 hex chars)
        serializedProofPart2.push(0x997ff8d20d3e32eb45cc8e5596b4015580120048c97e03ab4bb3db8986f6ec07);
        serializedProofPart2.push(0xc3ebbf2e66143e6f9adc26a14e1ac50df1556f7c9d5205457bea00772276e12b);
        serializedProofPart2.push(0x514a8b6cae4478068588b3b58a413464063c9184f31bf67619ea25c379de90dd);
        serializedProofPart2.push(0x012fd5e73eafb1335b8b316694ae7625a658b40d505f44c953a50936fc042baf);
        serializedProofPart2.push(0xd003e00a1bc97f58ca36d16c7362be3639654d857e4d3140ea099dbcac405b71);
        serializedProofPart2.push(0x346e3faf0c03d62fe304872cbc903235ca365f97598db2b8b7881a25876d47c2);
        serializedProofPart2.push(0x38b9ab8a06a929e0f61bcaaf885933896585ebe2e918f38d6fad1ee65a4d373d);
        serializedProofPart2.push(0x490c19e8d9326c3a8fa9f03d9597fc5addbe762f35f3de1f595448199a0b4631);
        serializedProofPart2.push(0x6690b1bad825eb0bdc46080e95a247e0a5f8a405dbcbca5174dd862abeb6df5a);
        serializedProofPart2.push(0x7bdf405fa2a3650c4a60bb94fccf24c166ea273080a3b3a87a21b213e94e6178);
        serializedProofPart2.push(0x99d5cd956df8f5aeea1340d3b51afe6baafefb0e6c73c76b0d226d50487d876b);
        serializedProofPart2.push(0x94540f2a828a2746ad9f4f867cf3aeab6eb2a2c3e66c298cfeac4f3c769be6f7);
        serializedProofPart2.push(0xd05d497e431a9db22a10ecdb61ae6bcac983364d94e9377911db4efdff55fd43);
        serializedProofPart2.push(0xc1400a43e4ac37f74fb03787ea4460bcd5dcda061ac54db315dbe68fecf79f12);
        serializedProofPart2.push(0xca02e6bb6f5f2c4c8650699b34cdfa65a9012c14649f8d0dc5b4460c2c65b228);
        serializedProofPart2.push(0xaf8f6b82cac7437e3243dddb476bdfcbe1250c471a64487a7fd1e357b0c29ffc);
        serializedProofPart2.push(0xb06d61bd52d053682e9089dc8f5fde5be1ce0739924448741e47d450e0b5d702);
        serializedProofPart2.push(0x5136283a39db431aaee068ec14a536f700c364920428ade4b231f18cc77fabf8);
        serializedProofPart2.push(0x35befef343dbb07d0401231031fb957f77720fa6cec03ca3c285cba6d0ddb212);
        serializedProofPart2.push(0x4c14248c8633e3f1aff55b7fad07bc9457bfa7d544707434e30b537e69787ec3);
        serializedProofPart2.push(0xd64baa0a649afdf600ef2704e4bc8fdb53aff62ad749b9f3890d4f38d821e33d);
        serializedProofPart2.push(0xc36ce523a2b97f90bd45b3613a4f91697b09af6ba3bc8c79a430bca8a6d91b0b);
        serializedProofPart2.push(0xa897b1362944f8f6781e81b9997fb5a32e21161328873b059e999f722a1dcf8d);
        serializedProofPart2.push(0x54729d520813dae91f01cb82ad9c386f416aef7204c69afa2308ff0aea137b2d);
        serializedProofPart2.push(0xb570036f66a324c207b08f9910fc8147b014c57f91e380844225284ded1d6d93);
        serializedProofPart2.push(0xeba059d2faa29dc3d4b87f797ba5be7768d05421d9bd5cd3e21b157acb36217b);
        serializedProofPart2.push(0xc41723058815ed945546b14ba946e1f9c6f75d4bc601a0b101cf2b576171b468);
        serializedProofPart2.push(0xb3cbeae9e2439fe235809b71858f4fe21c9bb91041651d2ddb6706f48cca4d62);
        serializedProofPart2.push(0xa134f24c3de1dcbbbb8160554770de132ca8ad9d7c0160118c86a5a0a0a021b5);
        serializedProofPart2.push(0x9e8e4632733e21d564ea3c937932e44db6247a883884c501c5083218bc433948);
        serializedProofPart2.push(0xd627617ad0bcb23db5a427761dde7ec93b21e4baffe9f88180b0ecf652d2e693);
        serializedProofPart2.push(0x5fdf6acdeec054e74dd3a70fd7425705681be09ffcf9e3f025146665d996c1b4);
        serializedProofPart2.push(0xa134f24c3de1dcbbbb8160554770de132ca8ad9d7c0160118c86a5a0a0a021b5);
        serializedProofPart2.push(0x9e8e4632733e21d564ea3c937932e44db6247a883884c501c5083218bc433948);
        serializedProofPart2.push(0xa80efe411a61d2281bfdc22add2fd9e53fa6cb5a7aece13aaaf49cd60aee46e2);
        serializedProofPart2.push(0x497a65fab4a9efd55b9cad72b115b3e780fc1ce8f64733b39756e1fa32ebbff4);
        serializedProofPart2.push(0x4e5216d3202a3dcded4b2db04104a8288c77e13f68fc3b703f570379408d9c97);
        serializedProofPart2.push(0x8dd1254d421f2ce4e5dd6abea5b9cfd9378d4ce211ae7f97bcd926fc160c6025);
        serializedProofPart2.push(0x2d17c855ae09ce3f48accfcf39ff767fc92f4dcfdd01e3b996b00a7b430a300e);
        serializedProofPart2.push(0x3975e11824c9f9b64be14fa78658358b0f6629dbca2e0a1e6b6598c70e4edd0a);
        serializedProofPart2.push(0x6359eecc2f5368c0df6465d31ce4fb94fada1d39a2feb547093733d054d24f67);
        serializedProofPart2.push(0x0d34e0919fa1b33bc4dfe613e2cee9463119be4041f9d4b566af48af1b478b8e);


        // PUBLIC INPUTS (concatenated from instance.json: a_pub_user + a_pub_block + a_pub_function - 512 total)
        publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x5c1103c2056371f62b88ecd6b08b7b3b);
          publicInputs.push(0x531702f2c7452fc52ecdbd305c08929f);
          publicInputs.push(0x89a9a9e9ccdff791c018ef5b70111143);
          publicInputs.push(0x0d35f1c31abb040057c5ed5057e7c501);
          publicInputs.push(0xb912f1ca83ccebe1002cf4577b45aab8);
          publicInputs.push(0x05261c8e6eaf32927fceed5da1d7b015);
          publicInputs.push(0x85b8f5c0457dbc3b7c8a280373c40044);
          publicInputs.push(0xa30fe402);
          publicInputs.push(0xa9059cbb);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          // End of a_pub_user (40 elements)
          publicInputs.push(0x4e7256340cc820415a6022a7d1c93a35);
          publicInputs.push(0x5cc0dde1);
          publicInputs.push(0x69297a5c);
          publicInputs.push(0x00);
          publicInputs.push(0x945f42);
          publicInputs.push(0x00);
          publicInputs.push(0xed1d198cdf26159e6cf92dc4f6e67000);
          publicInputs.push(0xbaa19ce7139c80e3cf389172f7fab4b6);
          publicInputs.push(0x03938700);
          publicInputs.push(0x00);
          publicInputs.push(0xaa36a7);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x127db5fdfb3e243ef252656e332a2b68);
          publicInputs.push(0x02bb8ff49694774d0518c5ce72998f1d);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          // End of a_pub_block (24 elements)
          publicInputs.push(0x01);
          publicInputs.push(0xffffffffffffffffffffffffffffffff);
          publicInputs.push(0xffffffff);
          publicInputs.push(0xe72f6afd7d1f72623e6b071492d1122b);
          publicInputs.push(0x11dafe5d23e1218086a365b99fbf3d3b);
          publicInputs.push(0x3e26ba5cc220fed7cc3f870e59d292aa);
          publicInputs.push(0x1d523cf1ddab1a1793132e78c866c0c3);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x01);
          publicInputs.push(0x00);
          publicInputs.push(0x80);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x200000);
          publicInputs.push(0x04);
          publicInputs.push(0x00);
          publicInputs.push(0x44);
          publicInputs.push(0x00);
          publicInputs.push(0x010000);
          publicInputs.push(0xe0);
          publicInputs.push(0x00);
          publicInputs.push(0x08000000);
          publicInputs.push(0x20);
          publicInputs.push(0x00);
          publicInputs.push(0x10000000);
          publicInputs.push(0xe0);
          publicInputs.push(0x00);
          publicInputs.push(0x10000000);
          publicInputs.push(0x70a08231);
          publicInputs.push(0x00);
          publicInputs.push(0x020000);
          publicInputs.push(0x98650275);
          publicInputs.push(0x00);
          publicInputs.push(0x020000);
          publicInputs.push(0xaa271e1a);
          publicInputs.push(0x00);
          publicInputs.push(0x020000);
          publicInputs.push(0x98650275);
          publicInputs.push(0x00);
          publicInputs.push(0x100000);
          publicInputs.push(0xa457c2d7);
          publicInputs.push(0x00);
          publicInputs.push(0x100000);
          publicInputs.push(0xa9059cbb);
          publicInputs.push(0x00);
          publicInputs.push(0x100000);
          publicInputs.push(0x04);
          publicInputs.push(0x00);
          publicInputs.push(0x44);
          publicInputs.push(0x00);
          publicInputs.push(0x08);
          publicInputs.push(0x40);
          publicInputs.push(0x00);
          publicInputs.push(0x010000);
          publicInputs.push(0x200000);
          publicInputs.push(0x02);
          publicInputs.push(0xffffffffffffffffffffffffffffffff);
          publicInputs.push(0xffffffff);
          publicInputs.push(0x20);
          publicInputs.push(0x00);
          publicInputs.push(0x02);
          publicInputs.push(0x20);
          publicInputs.push(0x00);
          publicInputs.push(0x02);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0xffffffffffffffffffffffffffffffff);
          publicInputs.push(0xffffffff);
          publicInputs.push(0xffffffffffffffffffffffffffffffff);
          publicInputs.push(0xffffffff);
          publicInputs.push(0x100000);
          publicInputs.push(0x200000);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0xffffffffffffffffffffffffffffffff);
          publicInputs.push(0xffffffff);
          publicInputs.push(0xffffffffffffffffffffffffffffffff);
          publicInputs.push(0xffffffff);
          publicInputs.push(0x100000);
          publicInputs.push(0x200000);
          publicInputs.push(0x60);
          publicInputs.push(0x00);
          publicInputs.push(0x02);
          publicInputs.push(0x20);
          publicInputs.push(0x00);
          publicInputs.push(0x02);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0xffffffffffffffffffffffffffffffff);
          publicInputs.push(0xffffffff);
          publicInputs.push(0xffffffffffffffffffffffffffffffff);
          publicInputs.push(0xffffffff);
          publicInputs.push(0x20);
          publicInputs.push(0x00);
          publicInputs.push(0x02);
          publicInputs.push(0x20);
          publicInputs.push(0x00);
          publicInputs.push(0x02);
          publicInputs.push(0x1da9);
          publicInputs.push(0x00);
          publicInputs.push(0xffffffff);
          publicInputs.push(0x00);
          publicInputs.push(0x020000);
          publicInputs.push(0x200000);
          publicInputs.push(0x08);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0xffffffffffffffffffffffffffffffff);
          publicInputs.push(0xffffffff);
          publicInputs.push(0xffffffffffffffffffffffffffffffff);
          publicInputs.push(0xffffffff);
          publicInputs.push(0x20);
          publicInputs.push(0x00);
          publicInputs.push(0x02);
          publicInputs.push(0x20);
          publicInputs.push(0x00);
          publicInputs.push(0x02);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0xffffffffffffffffffffffffffffffff);
          publicInputs.push(0xffffffff);
          publicInputs.push(0xffffffffffffffffffffffffffffffff);
          publicInputs.push(0xffffffff);
          publicInputs.push(0x20);
          publicInputs.push(0x00);
          publicInputs.push(0x02);
          publicInputs.push(0x20);
          publicInputs.push(0x00);
          publicInputs.push(0x02);
          publicInputs.push(0x1acc);
          publicInputs.push(0x00);
          publicInputs.push(0xffffffff);
          publicInputs.push(0x00);
          publicInputs.push(0x02);
          publicInputs.push(0x010000);
          publicInputs.push(0x200000);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0xffffffffffffffffffffffffffffffff);
          publicInputs.push(0xffffffff);
          publicInputs.push(0xffffffffffffffffffffffffffffffff);
          publicInputs.push(0xffffffff);
          publicInputs.push(0x20);
          publicInputs.push(0x00);
          publicInputs.push(0x02);
          publicInputs.push(0x20);
          publicInputs.push(0x00);
          publicInputs.push(0x02);
          publicInputs.push(0xffffffffffffffffffffffffffffffff);
          publicInputs.push(0xffffffff);
          publicInputs.push(0xffffffffffffffffffffffffffffffff);
          publicInputs.push(0xffffffff);
          publicInputs.push(0x20);
          publicInputs.push(0x00);
          publicInputs.push(0x02);
          publicInputs.push(0x08);
          publicInputs.push(0x15);
          publicInputs.push(0x00);
          publicInputs.push(0x0100);
          publicInputs.push(0x00);
          publicInputs.push(0x01);
          publicInputs.push(0x00);
          publicInputs.push(0x10);
          publicInputs.push(0xff);
          publicInputs.push(0x00);
          publicInputs.push(0x200000);
          publicInputs.push(0x200000);
          publicInputs.push(0x01);
          publicInputs.push(0x00);
          publicInputs.push(0x200000);
          publicInputs.push(0x200000);
          publicInputs.push(0x200000);
          publicInputs.push(0x200000);
          publicInputs.push(0x20);
          publicInputs.push(0x00);
          publicInputs.push(0x02);
          publicInputs.push(0x08);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          publicInputs.push(0x00);
          // End of a_pub_function (448 elements)

        
        smax = 256;
    }

    function testVerifier() public {
        uint256 gasBefore = gasleft();
        
        // Use low-level call to get the actual bytes returned
        (bool success, bytes memory returnData) = address(verifier).call(
            abi.encodeWithSignature(
                "verify(uint128[],uint256[],uint128[],uint256[],uint256[],uint256)",
                serializedProofPart1, serializedProofPart2, preprocessedPart1, preprocessedPart2, publicInputs, smax
            )
        );
        
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        
        console.log("Gas used:", gasUsed);
        assert(success == true);
    }

    function testWrongProof_shouldRevert() public {
        serializedProofPart1[4] = 0x0cf3e4f4ddb78781cd5740f3f2a1a3db; // Wrong U_X part1
        serializedProofPart1[5] = 0x0f4b46798d566e5f6653c4fe4df20e83; // Wrong U_Y part1

        serializedProofPart2[4] = 0xd3e45812526acc1d689ce05e186d3a8b9e921ad3a4701013336f3f00c654c908; // Wrong U_X part2
        serializedProofPart2[5] = 0x76983b4b6af2d6a17be232aeeb9fdd374990fdcbd9b1a4654bfbbc5f4bba7e13; // Wrong U_X part2
        vm.expectRevert(bytes("finalPairing: pairing failure"));
        verifier.verify(
            serializedProofPart1, serializedProofPart2, preprocessedPart1, preprocessedPart2, publicInputs, smax
        );
    }

    function testEmptyPublicInput_shouldRevert() public {
        uint256[] memory newPublicInputs;
        vm.expectRevert(bytes("finalPairing: pairing failure"));
        verifier.verify(
            serializedProofPart1, serializedProofPart2, preprocessedPart1, preprocessedPart2, newPublicInputs, smax
        );
    }

    function testWrongSizeProof_shouldRevert() public {
        serializedProofPart1.push(0x0d8838cc826baa7ccd8cfe0692e8a13d); // new point X
        serializedProofPart1.push(0x103aeb959c53fdd5f13b70a350363881); // new point Y
        serializedProofPart2.push(0xbbae56c781b300594dac0753e75154a00b83cc4e6849ef3f07bb56610a02c828); // new point X
        serializedProofPart2.push(0xf3447285889202e7e24cd08a058a758a76ee4c8440131be202ad8bc0cc91ee70); // new point Y

        vm.expectRevert(bytes("loadProof: Proof is invalid"));
        verifier.verify(
            serializedProofPart1, serializedProofPart2, preprocessedPart1, preprocessedPart2, publicInputs, smax
        );
    }

    function testEmptyProof_shouldRevert() public {
        uint128[] memory newSerializedProofPart1;
        uint256[] memory newSerializedProofPart2;

        vm.expectRevert(bytes("loadProof: Proof is invalid"));
        verifier.verify(
            newSerializedProofPart1, newSerializedProofPart2, preprocessedPart1, preprocessedPart2, publicInputs, smax
        );
    }
}