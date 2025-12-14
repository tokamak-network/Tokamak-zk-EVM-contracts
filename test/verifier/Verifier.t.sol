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

        // serializedserializedProofPart1: First 16 bytes (32 hex chars) of each coordinate
        // serializedserializedProofPart2: Last 32 bytes (64 hex chars) of each coordinate
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
        preprocessedPart1.push(0x1136c7a73653af0cbdc9fda441a80391);
        preprocessedPart1.push(0x007c86367643476dcdb0e9bcf1617f1c);
        preprocessedPart1.push(0x18c9e2822155742dd5fbd050aa293be5);
        preprocessedPart1.push(0x00b248168d62853defda478a7a46e0a0);

        // PREPROCESSED PART 2 (Last 32 bytes - 64 hex chars)
        preprocessedPart2.push(0xc4383bb8c86977fc45c94bc42353e37b39907e30b52054990083a85cf5256c22);
        preprocessedPart2.push(0x8fc97f11906d661f0b434c3c49d0ec8b3cac2928f6ff6fac5815686d175d2e87);
        preprocessedPart2.push(0xf84798df0fcfbd79e070d2303170d78e438e4b32975a4ebf6e1ff32863f2cc3e);
        preprocessedPart2.push(0xc6b05d5e144de6e3b25f09093b9ba94c194452d8decf3af3390cfa46df134c0e);

        // SERIALIZED PROOF PART 1 (First 16 bytes - 32 hex chars)
        serializedProofPart1.push(0x15815614b1d3cfda780a76f38debd7a8);
        serializedProofPart1.push(0x15b853b4b6eda1d03dc7425ff8de2ab8);
        serializedProofPart1.push(0x1579e2d3f28e91954ea7f08662b1cf3c);
        serializedProofPart1.push(0x1193fdc21cf50013a57a04b95a980e70);
        serializedProofPart1.push(0x0ef6fa45a824d55e6ab0242e79346af4);
        serializedProofPart1.push(0x0579570790721e06f618e9b435e99fcc);
        serializedProofPart1.push(0x0712c6c5aaa97978302ea53ed788bb9f);
        serializedProofPart1.push(0x0fd202428e1846b62b08551224fc44fa);
        serializedProofPart1.push(0x192da2abb37a61d57edd3cb783519fff);
        serializedProofPart1.push(0x037fecce4bb5d2c935aea5d5dce3eb69);
        serializedProofPart1.push(0x188d99fd3fa3fb713313356e80d011a5);
        serializedProofPart1.push(0x00a815a29deb9b4c2b7f59fad3d0aa70);
        serializedProofPart1.push(0x0dd23c7c26c943439e5793ec06d24027);
        serializedProofPart1.push(0x13af2ab494a3a28b5a9329fcc15e3358);
        serializedProofPart1.push(0x16d79ba31faebbd9be3c5d6ec33405b6);
        serializedProofPart1.push(0x041cb373ead122e1a5755f5e7e11b52a);
        serializedProofPart1.push(0x144bd4c7d0d646d7a50710a2408d10f1);
        serializedProofPart1.push(0x14035301f93670a1083c4bf0410ed855);
        serializedProofPart1.push(0x1106f645a82f2e3098a2d184d5ecce06);
        serializedProofPart1.push(0x12a69c3983176f94b3af657430db1c47);
        serializedProofPart1.push(0x10247238a26ae53c84ad57577454ed6b);
        serializedProofPart1.push(0x1552e5c50974761247a91ad853b5831f);
        serializedProofPart1.push(0x0ed5ac16f53d550faa94b3f89e7c3068);
        serializedProofPart1.push(0x0de8107eff76583c9db6296e542e6f72);
        serializedProofPart1.push(0x059d13674332bae80788f4aad61a36bb);
        serializedProofPart1.push(0x11928ff2162df1dee7bd651f1f06b247);
        serializedProofPart1.push(0x17a05db254eda53ead06061a27b8051a);
        serializedProofPart1.push(0x09cb514bf0ba929adabafa7898023cf3);
        serializedProofPart1.push(0x13eb334743fa8f040a1d288c03872162);
        serializedProofPart1.push(0x1882f3c85de4b5e36314f849a9a35d6c);
        serializedProofPart1.push(0x085686e98ae7c7a0d4ad61f7e1fc2207);
        serializedProofPart1.push(0x0445f9424f1f95b4d831006e7a13f0f0);
        serializedProofPart1.push(0x13eb334743fa8f040a1d288c03872162);
        serializedProofPart1.push(0x1882f3c85de4b5e36314f849a9a35d6c);
        serializedProofPart1.push(0x1674357a821eb6fbd29b19d2bc46bf11);
        serializedProofPart1.push(0x090838093c14b593a824dfe2f491af72);
        serializedProofPart1.push(0x0bf54da2ebdc1f4d8cf126c88c579e2a);
        serializedProofPart1.push(0x04fef23658e5ec9ac987a183ba44f153);

        // SERIALIZED PROOF PART 2 (Last 32 bytes - 64 hex chars)
        serializedProofPart2.push(0x218a2513b9f5d2f07da97b9c001c29cfd1def3795cdc67c7a55aae80d6fa1739);
        serializedProofPart2.push(0x870afac1b023aeb155cd0407035ede2b91c0411f25f3e814419af37045549bf2);
        serializedProofPart2.push(0xb803b959f341ba8d0df34277acf806a22987ee4405bfdb8a6075abab622d8938);
        serializedProofPart2.push(0x4cf5ef5575cc65795c91a41bedd329a870d531132d4c01c0daacfa21ae9d0c9b);
        serializedProofPart2.push(0x5cff38c52fa19d052a230f004a5767cd06f0ee607f235dee61c279901e1eb334);
        serializedProofPart2.push(0x903044616e6a82670d4f0e7da1c2acce49b2f2fdb4bec4d892a6c61a605dabe7);
        serializedProofPart2.push(0x238c8319cab91bf944028e56fdc53fac686912eddb2681bb31da98de1a45046f);
        serializedProofPart2.push(0x72751b0b8849f28e90a043496f8e3c721a9a2c11dc37dfb4b8eb2e51617b838f);
        serializedProofPart2.push(0x1786cc8744ba3c625faf3e425d6efb7fb7a8843f3e7bf849c5bb91aeda51039b);
        serializedProofPart2.push(0xb44c14a62ea7274bfaaeef7f9d177295533ca16b8424c570f40d336f750899c5);
        serializedProofPart2.push(0x0b7e53ae849ff813c770b7fa067c015db95084df6ccfc2d08d7ed344106e9446);
        serializedProofPart2.push(0x903f8c62ade1fe442f896656ccd601dea9f6b884de44ca50179e95b69d7e9278);
        serializedProofPart2.push(0x1a576bce68d74c7f45d2099e21c03ba18b785d4443ca24664a4358b5b4492b07);
        serializedProofPart2.push(0x706a7e78137f8ab4bb6fab55cb7829e4dcd332e07db3233827d57b974ba772c7);
        serializedProofPart2.push(0x08608535f35ba479cbdf98ec4117f1d6d0d5bbbc7120d15975db81ef47084bb1);
        serializedProofPart2.push(0x7a41b65ce8cea584d8903d0e7d311b291df68e8b5cbb2f03aec78b1f632859f3);
        serializedProofPart2.push(0xb51ec8eabaef042a70a4993bae881b2352090b550a0b778918cfa65affcafeb4);
        serializedProofPart2.push(0xab74f4e1b4bb1455e8f57881cc861f7dab291441b019bf6b2b42edff13ab4ff8);
        serializedProofPart2.push(0xd8717ef8b4c49967258125a65a627ffb1039a70986016de2326013298fdad205);
        serializedProofPart2.push(0xb910ebe08c152b86b2cc202f10b89f09bb995327673800c6ff6960cee9fe0fa6);
        serializedProofPart2.push(0x51a0b49263eb04d442553649aa8ba2bff8bf08395e94a40aaf2d6cdf4de5e200);
        serializedProofPart2.push(0x2deddc72de9bd7c8539eb2dbffc05c6d0c6d3dc082211da6b9d2cf6261c5b95c);
        serializedProofPart2.push(0xe90764e8c3c608909905317d1db45264d115e53ff1f5560812e9ad9a712a1aef);
        serializedProofPart2.push(0xf3f16f05a8ac974202fca819ad30654566669e877c575b752e6f2844e8bf811d);
        serializedProofPart2.push(0x7074d02532f74b37b3bf2e2e80e6efd74a59d9c2be7014205f8b0a68da5cf660);
        serializedProofPart2.push(0xb5cb826a1ede3b7eaf370442e4c37560272964a6cacf8d5b7f16a37c376289c9);
        serializedProofPart2.push(0x895f9fab7c3b6d2d2f4c8abab824bce78ebb829d678c9c7893938b1be37797da);
        serializedProofPart2.push(0xe2b5b0dc5b4927868448b343b342c3cbdcc5ed11ec5ca34cafd05d8e1a7d30e5);
        serializedProofPart2.push(0x24a58a466697866ac22e9279dab43ac2b643e6752eedf664396ece2bb61e3e99);
        serializedProofPart2.push(0x4906165f727bdc79f02b6a0b717bacff91e4d980566e205199160e1b84237097);
        serializedProofPart2.push(0x1ae0176fd63ecfa263c5f019842cee0fb2b00c92cdfae64746dd78fc0dd8f58d);
        serializedProofPart2.push(0xf2f32da4b9ea674a98015718df38ef40fd8d4187f23a738ec8fd70902be929d2);
        serializedProofPart2.push(0x24a58a466697866ac22e9279dab43ac2b643e6752eedf664396ece2bb61e3e99);
        serializedProofPart2.push(0x4906165f727bdc79f02b6a0b717bacff91e4d980566e205199160e1b84237097);
        serializedProofPart2.push(0x6ec7a66b4c594cc793e83b44f4da30ad8dd9184f02414a35da49deacc2aeae29);
        serializedProofPart2.push(0x61a58def048a6f157c8c269ce1ff0f622a851eac19fab9060f6cb2e33599eac2);
        serializedProofPart2.push(0x55cc89b9e9e4a9a7c389845c00289a0b8471efb1d4a0bb58c39accb4dc0794a8);
        serializedProofPart2.push(0x2919e53d947ef94f43e16675e04a66b6746bbea448cd8ef68b1c477fa86fc4e9);
        serializedProofPart2.push(0x17fbc25ff5a04b607706778a88332341049268460ee170d1cf06cd64634ee20a);
        serializedProofPart2.push(0x6ead56bfcbba4c416108882629c6c61b940ea05f76cce26606537b96506e15e6);
        serializedProofPart2.push(0x447fff7ec6e9996301a21dbae35881d00d3fc12c7226ba85ff28245be34db010);
        serializedProofPart2.push(0x32fe3527e7bac897c0083e5362f707898d66b4ac5c52bd5004afbe7d713bf6c9);


        // PUBLIC INPUTS (concatenated from instance.json: a_pub_user + a_pub_block + a_pub_function - 512 total)
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x697f6a98de69bdc71426efe52f459cfc);
        publicInputs.push(0x7380218991c8a0feb79bb9715fd26e2a);
        publicInputs.push(0x85e43e3f03778631a09942dd08cf2e8d);
        publicInputs.push(0x4f3d75526b4d4b109e87539730a792e4);
        publicInputs.push(0xe21d7692eebc6214c1585134fda4b0d6);
        publicInputs.push(0x0c8ba5023657fe4b7d7c4edb122894ba);
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
        
        // a_pub_block (indices 42-65)
        publicInputs.push(0x29dec4629dfb4170647c4ed4efc392cd);
        publicInputs.push(0xf24a01ae);
        publicInputs.push(0x6939333c);
        publicInputs.push(0x00);
        publicInputs.push(0x95abdc);
        publicInputs.push(0x00);
        publicInputs.push(0x19959c1873750220732ca5148bab3254);
        publicInputs.push(0xa0c5ba1cddaf068fc86d068a534eb367);
        publicInputs.push(0x039386c7);
        publicInputs.push(0x00);
        publicInputs.push(0xaa36a7);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0xb29b7b4ce683591d957141ca7e4bbc9d);
        publicInputs.push(0x151ac8176283d1313ff21b9d60ad82ce);
        // Rest are zeros (60-65)
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        
        // a_pub_function (indices 66-517) - All the function instance data
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
        publicInputs.push(0x07);
        publicInputs.push(0x00);
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
        // Rest are all zeros (247-511)
        for (uint256 i = 247; i < 512; i++) {
            publicInputs.push(0x00);
        }

        
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
        uint128[] memory newserializedProofPart1;
        uint256[] memory newserializedProofPart2;

        vm.expectRevert(bytes("loadProof: Proof is invalid"));
        verifier.verify(
            newserializedProofPart1, newserializedProofPart2, preprocessedPart1, preprocessedPart2, publicInputs, smax
        );
    }
}