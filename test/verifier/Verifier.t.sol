// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {Verifier} from "../../src/verifier/Verifier.sol";

import "forge-std/console.sol";

contract testTokamakVerifier is Test {
    address owner;

    Verifier verifier;

    uint128[] public serializedProofPart1;
    uint256[] public serializedProofPart2;
    uint128[] public preprocessedPart1;
    uint256[] public preprocessedPart2;
    uint256[] public publicInputs;
    uint256 public smax;

    function setUp() public virtual {
        verifier = new Verifier();

        owner = makeAddr("owner");
        vm.startPrank(owner);
        vm.stopPrank();

        // serializedProofPart1: First 16 bytes (32 hex chars) of each coordinate
        // serializedProofPart2: Last 32 bytes (64 hex chars) of each coordinate
        // preprocessedPart1: First 16 bytes (32 hex chars) of each preprocessed committment coordinate
        // preprocessedPart2: last 32 bytes (64 hex chars) of each preprocessed committment coordinate

        // PREPROCESSED PART 1 (First 16 bytes - 32 hex chars)
        preprocessedPart1.push(0x1186b2f2b6871713b10bc24ef04a9a39);
        preprocessedPart1.push(0x02b36b71d4948be739d14bb0e8f4a887);
        preprocessedPart1.push(0x18e54aba379045c9f5c18d8aefeaa8cc);
        preprocessedPart1.push(0x08df3e052d4b1c0840d73edcea3f85e7);

        // PREPROCESSED PART 2 (Last 32 bytes - 64 hex chars)
        preprocessedPart2.push(0x7e084b3358f7f1404f0a4ee1acc6d254997032f77fd77593fab7c896b7cfce1e);
        preprocessedPart2.push(0xe2dfa30cd1fca5558bfe26343dc755a0a52ef6115b9aef97d71b047ed5d830c8);
        preprocessedPart2.push(0xf68408df0b8dda3f529522a67be22f2934970885243a9d2cf17d140f2ac1bb10);
        preprocessedPart2.push(0x4b0d9a6ffeb25101ff57e35d7e527f2080c460edc122f2480f8313555a71d3ac);

        // SERIALIZED PROOF PART 1 (First 16 bytes - 32 hex chars)
        serializedProofPart1.push(0x1236d4364cc024d1bb70d584096fae2c);
        serializedProofPart1.push(0x14caedc95bee5309da79cfe59aa67ba3);
        serializedProofPart1.push(0x0573b8e1fe407ab0e47f7677b3333c8b);
        serializedProofPart1.push(0x0b4a0b22cbea8b0e92c90d65f2d2eb57);
        serializedProofPart1.push(0x0f05d6f9f8d90891c0d9885d5a8b3dce);
        serializedProofPart1.push(0x091d21a7b62e312796931eb6ba0cc810);
        serializedProofPart1.push(0x0c1c9f2b440618cd80ffc68a14559aac);
        serializedProofPart1.push(0x197314b7857dd5fbad45dbf34878d675);
        serializedProofPart1.push(0x03b4e9b71f05081b59bf9e1112e5a667);
        serializedProofPart1.push(0x0b30a9b1c509db26df1a299e56e62272);
        serializedProofPart1.push(0x04fffae927d7a9d9914e42203aa03692);
        serializedProofPart1.push(0x0185be457591c9c6b11c106add9d62be);
        serializedProofPart1.push(0x090303ab1724b71758062ff4dc2c1da0);
        serializedProofPart1.push(0x026da799b5c02de6229060e0bed5ece5);
        serializedProofPart1.push(0x09781600275ede5c4b5a2db154bd142c);
        serializedProofPart1.push(0x105346c772199060310f36313d15e5ba);
        serializedProofPart1.push(0x0ef5d60c26871f94e1b9d172c2ba0e9d);
        serializedProofPart1.push(0x098d4e8655cdc6819deb56aef2ff42aa);
        serializedProofPart1.push(0x0cd2cdadbe300634208a30bbfc88bdb3);
        serializedProofPart1.push(0x199cf445ad58377b94b3430c9c597750);
        serializedProofPart1.push(0x15520ed9c503f7fe6bfed55e60091b23);
        serializedProofPart1.push(0x0858cbc81ce8bdb7876efc9b7225d253);
        serializedProofPart1.push(0x135d4abaa1e96b2c41e511da50746d1e);
        serializedProofPart1.push(0x1470193b3bccc9a821d10281bc154777);
        serializedProofPart1.push(0x0ae7ec720fb7ff80618a1e1bedc505cc);
        serializedProofPart1.push(0x0d337319259f04c8c6c14231a58f77fb);
        serializedProofPart1.push(0x003d23310314e9d975c46f56ad439311);
        serializedProofPart1.push(0x0ed9b1cea085ae4f0ed7245153d44351);
        serializedProofPart1.push(0x13579a09b2ae2900f0237521524a6e9c);
        serializedProofPart1.push(0x0c76da67f3808d851385caf2e3dc2cfa);
        serializedProofPart1.push(0x0a36eb8c4c918ea3356bc740ad117a43);
        serializedProofPart1.push(0x15fa53d71a9d682982ee27b4abe0bc96);
        serializedProofPart1.push(0x13579a09b2ae2900f0237521524a6e9c);
        serializedProofPart1.push(0x0c76da67f3808d851385caf2e3dc2cfa);
        serializedProofPart1.push(0x0f028db2a0e1048fd5b47d7598b0e5cd);
        serializedProofPart1.push(0x0f776ce8b238fc163c0b1aa8113d0908);
        serializedProofPart1.push(0x004fd73b11ac3d8956b72d5b0d6093b1);
        serializedProofPart1.push(0x081eb0d1bd168c6d30235d758caa900f);

        // SERIALIZED PROOF PART 2 (Last 32 bytes - 64 hex chars)
        serializedProofPart2.push(0xd107861dd8cac07bc427c136bc12f424521b3e3aaab440fdcdd66a902e22c0a4);
        serializedProofPart2.push(0x27d4a95a71f8b939514a0e455984f5c90b9fdcf5702a3da9a8d73f7f93292c23);
        serializedProofPart2.push(0x08393216d4961ef999d5938af832fd08b8ff691f4a25cd77786485e9891e2389);
        serializedProofPart2.push(0x497128bfba07e0f4244381c1700d6077598a28d1be5dae2a8e39fa6bd93000eb);
        serializedProofPart2.push(0x21d37a6c1f275d5192cfae389ec36af3257e746b3436589937f9bf16951c96a3);
        serializedProofPart2.push(0xbd49edca77d31e9fb7e8409a7409de741291698c0616967dcd7df1f5f34f6212);
        serializedProofPart2.push(0xf8a09978de0b6da6a9adc14ae826a5f05ee59b8ef17cfc26f93a104a664772e4);
        serializedProofPart2.push(0x1e214b4474e3e3b12789687f6bb6aa21df83b8434c49503bb929e8776e25869a);
        serializedProofPart2.push(0x4827419fee6540682017f10cd025c5f529a538ae600e3da543df57f25c85410f);
        serializedProofPart2.push(0x689880618d70f83eb0327c25608b48e750683430af117c0794d1ea7d4c05d295);
        serializedProofPart2.push(0x2836b43a9e6186487d363806eef564668eea8450dd58003abb4493d03bb239dd);
        serializedProofPart2.push(0x5784ab6a90aeb6fc6902b8d1ec1333ebf7e47f5c878eed1760843022a12a0727);
        serializedProofPart2.push(0xe688f506550d58aabd9be1051f4c42e928daa3bff57d2ebbd51bcd8be9b8e6b5);
        serializedProofPart2.push(0x2d268da230515168ffe241f350b12b6327dbea40126a0bc42629d047bdd13899);
        serializedProofPart2.push(0x6ec471068192170ecba808f5e99d94fd0729aff5fa411259b8d0d15dc9014658);
        serializedProofPart2.push(0x1357efc6c11cecf08c707228c6ac1b7a085e58ec52fb0468e3d2c60c4e2f6d23);
        serializedProofPart2.push(0x9788ba6df5cd36366e117ee97617b9cbdbfdb6eb8d1992b466767c6054e0150b);
        serializedProofPart2.push(0x5bb7a72c58d95800908e97c120ea98d22dce8893be18c43141b395a1071435ff);
        serializedProofPart2.push(0x7b90461c75d2910f36ce7b0aa1ad2343ba3981a4f272bedd13ce7e6952464f7c);
        serializedProofPart2.push(0xf68adfcea0d40e2a213e9c79208868f3e1989bbd6c3b9fdcc8eadc01d8a27e9f);
        serializedProofPart2.push(0xeab4846d491d118102a4ed96b1f24e5561ba10b3da8d683ed4ce44101e43c90d);
        serializedProofPart2.push(0x0e63557fb84b1d30339c9887f73d25c36f4242f35f9f581c473c82771e1f02e6);
        serializedProofPart2.push(0x4a155e92ca9b3a04afd3d444144bc3fd159d8c59fc5b3818d4f6ef32b0a954d9);
        serializedProofPart2.push(0xc041580ce190738da7afed0950af2564dd4a1b37a00cee090693a6a51868ae05);
        serializedProofPart2.push(0xb694bced949e4bfa188aaafaff65104501baea71861641881912533fef4e8686);
        serializedProofPart2.push(0xd33831c8ac7db381c8d9b1794bcfb57e472233dacef7c772b7c341c25ea934a4);
        serializedProofPart2.push(0x9182967105641eb087fb623c18d123574ef7b607d9f0ecf482ba80f8956d5bba);
        serializedProofPart2.push(0x53c804d5c258cb2ccbef3b7ae770df1959f5e573e134549ad269bd0e0e48fb3b);
        serializedProofPart2.push(0x922902030906773420f0a580e9cd488ae85c6569af6aebf3fcfd4f7b5ca8cdef);
        serializedProofPart2.push(0x19f360efa956bff46082f20b08e0d8298d8f630b6e58ca4da38113e2da32c0ee);
        serializedProofPart2.push(0xedea4fc1fa3627585cb54ac465ebabf4800ef8eb883ac267b382ff16b4af00aa);
        serializedProofPart2.push(0x10614258c22d18a6d52790e267c11b6dc6c7c38121322590df3f8fa3ca048e0b);
        serializedProofPart2.push(0x922902030906773420f0a580e9cd488ae85c6569af6aebf3fcfd4f7b5ca8cdef);
        serializedProofPart2.push(0x19f360efa956bff46082f20b08e0d8298d8f630b6e58ca4da38113e2da32c0ee);
        serializedProofPart2.push(0x33f065ca773908e0413e0797833584d46117ec49d309e4029b6b721637d01b3f);
        serializedProofPart2.push(0x3d58946048c0a8069237279ab514c6668679e47d403ff97ffdd0f28324216a35);
        serializedProofPart2.push(0xb89db416a80924c391ac012c1090ee4a91a1c5b1ecee12b992be5421190f3b6e);
        serializedProofPart2.push(0x7666a2dd1ec1bdd49e18df33d671ee4a7b22a5cb861df2d50bcd69fe2332b2a4);
        serializedProofPart2.push(0x14fd3c88e1cda3469c81fae671cf5ff501f5e671c9d6f537763f168b8a4c0a13);
        serializedProofPart2.push(0x67e12eb4b5beb06f83dcba323de6a3e366c307edc2a869f0930138da26a5fc48);
        serializedProofPart2.push(0x046accff92294fc236fcc0182d158388d53a75a1f4d5fe75c17f13a59aed9f06);
        serializedProofPart2.push(0x49fe17d694f683e5b941fe406857e2527b16573bd693d3e8b1125d20f480e987);

        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        ///////////////////////////////////             PUBLIC INPUTS             ////////////////////////////////////////////////
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

        publicInputs.push(0x00000000000000000000000000000000d9bb52200d942752f44a41d658ee82de);
        publicInputs.push(0x00000000000000000000000000000000000000000000000000000000cfc387b2);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x00000000000000000000000000000000d9bb52200d942752f44a41d658ee82de);
        publicInputs.push(0x00000000000000000000000000000000000000000000000000000000cfc387b2);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000049238da5803c4d4348d4b9e8fa15ef77);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000039921773);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000049238da5803c4d4348d4b9e8fa15ef77);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000039921773);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x00000000000000000000000000000000c96fb81fd761249696c372ec513d9e37);
        publicInputs.push(0x00000000000000000000000000000000f4b8e02bbf4c61201ef9f213934d9b3f);
        publicInputs.push(0x00000000000000000000000000000000c96fb81fd761249696c372ec513d9e37);
        publicInputs.push(0x00000000000000000000000000000000f4b8e02bbf4c61201ef9f213934d9b3f);
        publicInputs.push(0x00000000000000000000000000000000a769b91007adaa1fab75629d82eae4c2);
        publicInputs.push(0x0000000000000000000000000000000011cecbbf11187acad2789e79c034b854);
        publicInputs.push(0x00000000000000000000000000000000a769b91007adaa1fab75629d82eae4c2);
        publicInputs.push(0x0000000000000000000000000000000011cecbbf11187acad2789e79c034b854);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);

        smax = 512;
    }

    function testVerifier() public view {
        uint256 gasBefore = gasleft();
        bool success = verifier.verify(
            serializedProofPart1, serializedProofPart2, preprocessedPart1, preprocessedPart2, publicInputs, smax
        );
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        console.log("Gas used:", gasUsed);
        assert(success);
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
