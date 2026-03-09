// SPDX-License-Identifier: GPL-3.0
/*
    Copyright 2021 0KIMS association.

    This file is generated with [snarkJS](https://github.com/iden3/snarkjs).

    snarkJS is a free software: you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    snarkJS is distributed in the hope that it will be useful, but WITHOUT
    ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
    or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public
    License for more details.

    You should have received a copy of the GNU General Public License
    along with snarkJS. If not, see <https://www.gnu.org/licenses/>.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier16Leaves {
    // BLS12-381 Scalar field modulus (r)
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    // BLS12-381 Base field modulus (q) - split into two parts for 48-byte representation
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    // Verification Key data - split into PART1/PART2 for BLS12-381 format
    uint256 constant alphax_PART1 = 0x0000000000000000000000000000000019df117428d6209b35175c2f17efafe4;
    uint256 constant alphax_PART2 = 0xe450152a225c773f71256fd0b6cb00b6361afac3ca588df0ca43d1c523062d63;
    uint256 constant alphay_PART1 = 0x00000000000000000000000000000000014abb7d34799248932222e650bfa336;
    uint256 constant alphay_PART2 = 0xee7524a6cbf0e52efbd93a779c4374d80a6339c6f97c4d2c0bda733daa549838;
    uint256 constant betax1_PART1 = 0x0000000000000000000000000000000012646561fabc56a886f1d90cef4038d1;
    uint256 constant betax1_PART2 = 0x30051a9549614a0b507f7669679658ce59ef2ebbf1bcb348f63205ad7f3aaf0e;
    uint256 constant betax2_PART1 = 0x00000000000000000000000000000000061eef3f522852aa16a76287334ac1b7;
    uint256 constant betax2_PART2 = 0xb692587a5f5e0077e861626084a351f7ec76e25f330cbf53d8c6cfef10dacd0c;
    uint256 constant betay1_PART1 = 0x0000000000000000000000000000000018724e57498c87b761e361e5df060703;
    uint256 constant betay1_PART2 = 0xe4147c3cba9fd694a29c8ffe02712eb9db274fd1d847c867cd5e071a8e36c6a3;
    uint256 constant betay2_PART1 = 0x000000000000000000000000000000000a767683c4e1592eaa00783291289fa4;
    uint256 constant betay2_PART2 = 0x3371ea0d895d18364a737c5559a7a82734a1913c12f9d92295dd246976996818;
    uint256 constant gammax1_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 constant gammax1_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 constant gammax2_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 constant gammax2_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 constant gammay1_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 constant gammay1_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 constant gammay2_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 constant gammay2_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    uint256 constant deltax2_PART1 = 0x000000000000000000000000000000000d570fb7ea4577cfd8b7e4c570a05571;
    uint256 constant deltax2_PART2 = 0x19a1a67a0550d09759c0b3916c9eeed17b3bbfad5de8a9980481575f67b12754;
    uint256 constant deltax1_PART1 = 0x000000000000000000000000000000000284bcbcfe2cc1c07cbca6b2ea428056;
    uint256 constant deltax1_PART2 = 0x425f8aa1f197f305a5efde3840ab85c42e1154709a78a8580e557a8647d5104e;
    uint256 constant deltay2_PART1 = 0x0000000000000000000000000000000018e05348bf04fefbe97f4ddc87f560fc;
    uint256 constant deltay2_PART2 = 0x702cf9197803951e5ff52c114c773607ea1720660e830e656d8dc95c8d90b45d;
    uint256 constant deltay1_PART1 = 0x000000000000000000000000000000000372bb20e14213b5e2c0058063b7a42a;
    uint256 constant deltay1_PART2 = 0xd2e7645aef948fe3bb1132de6ec3c9e3ee0d77d7e7defd8ad71b3a809a50170d;

    // IC Points - split into PART1/PART2 for BLS12-381 format

    uint256 constant IC0x_PART1 = 0x000000000000000000000000000000000c5b9587dbdb202411ce7024a82af7c4;
    uint256 constant IC0x_PART2 = 0x6d92127f4d7e7f6046a77da8ee5eaaeadf6df45d92f9b98446a41cf7e7a55a1d;
    uint256 constant IC0y_PART1 = 0x0000000000000000000000000000000000bd748077228d54d9efa03a16dcbf3f;
    uint256 constant IC0y_PART2 = 0x54b7a89deb3f2755db122df64251be468e5746616382a0e8b3c68065e2099f94;
    //
    uint256 constant IC1x_PART1 = 0x0000000000000000000000000000000010a05855e58fabeb9776e5541183e563;
    uint256 constant IC1x_PART2 = 0x471b896aa44bfd06c9d7a66f9234a2027ab5d535583064f5b00cd18de8e48f8e;
    uint256 constant IC1y_PART1 = 0x000000000000000000000000000000000026341f29b7b91d5e55050c36c1b70f;
    uint256 constant IC1y_PART2 = 0x4ca6649719ef621f7e689254db2ffb13e95136d4ada43f5c5bfc242c77f3867c;

    uint256 constant IC2x_PART1 = 0x000000000000000000000000000000001663fd13d308a0acb443939c06f51fdb;
    uint256 constant IC2x_PART2 = 0xbfde651a8fc153611a24a92b420496af268a835d027a3d38e896d92e57116e0a;
    uint256 constant IC2y_PART1 = 0x0000000000000000000000000000000012fa2282bb1e5e0fb531e53243ed8ac8;
    uint256 constant IC2y_PART2 = 0xdfd9763102a0722fb3aad2ae16d04190920bcf4f50a96cbb57bebc64069c880b;

    uint256 constant IC3x_PART1 = 0x000000000000000000000000000000000085712075ff3413f4085a97d65abde8;
    uint256 constant IC3x_PART2 = 0xa70399a19c36b2c97a34af6b3b78aaab0060f4bda838a5972d132d5f23dec951;
    uint256 constant IC3y_PART1 = 0x0000000000000000000000000000000013e0ac0add23e0426da5290d8dceb8aa;
    uint256 constant IC3y_PART2 = 0x3330f206bf4fa00b35206ef41564937ab901606f5c8cdbb5d9b94fbc91d1d450;

    uint256 constant IC4x_PART1 = 0x000000000000000000000000000000000d3704d1fa439474d84c1d8bc1e0f79b;
    uint256 constant IC4x_PART2 = 0x1619987380009dd7d940f0b5a78f9d85e21ac178f2f422f6cf00c59e5aa78022;
    uint256 constant IC4y_PART1 = 0x000000000000000000000000000000000610bef9a78c800b8ffcc7751e78d913;
    uint256 constant IC4y_PART2 = 0x56f993157355c81617599a1923f934b9d376d80452ec71504ca6fd631239c9c3;

    uint256 constant IC5x_PART1 = 0x0000000000000000000000000000000010b4bfc5bdc3ac7d7d774814c5b8469b;
    uint256 constant IC5x_PART2 = 0x4d3aaf6eb15350bfe056adfca088e37040352555fe96877cf27f62a608ccdd12;
    uint256 constant IC5y_PART1 = 0x0000000000000000000000000000000002b2393b2147ae2240e8e6642a757e39;
    uint256 constant IC5y_PART2 = 0x2165512d5f45cf1645f547c7fec34346c014160fb5c01c36014ad58ab3778ad3;

    uint256 constant IC6x_PART1 = 0x000000000000000000000000000000000f22f37781890ab295e7673b4e1a9d09;
    uint256 constant IC6x_PART2 = 0xd8bdaa0692363f2b89fd4e84fd2db0cf45f8f72b83160e92067f3eee50d3bfa2;
    uint256 constant IC6y_PART1 = 0x000000000000000000000000000000000b98908daeacdf0a62601b044e6f8e70;
    uint256 constant IC6y_PART2 = 0x654fb02840e93344784620c4c0577da1e4de0fe493871177d70a49227c76b13b;

    uint256 constant IC7x_PART1 = 0x000000000000000000000000000000001196218f50c4cb8f11dcb4fb98139f8c;
    uint256 constant IC7x_PART2 = 0xa47d27573247cebec3c28cd70001d1e59b2b9bb173ff5288966be642ec94631b;
    uint256 constant IC7y_PART1 = 0x00000000000000000000000000000000114fdd622d665e29975099b0043ce2e4;
    uint256 constant IC7y_PART2 = 0x3c12d90ee3cd8da750711f680b899d7a79b0602a677242986ec5b2f13d6a53d4;

    uint256 constant IC8x_PART1 = 0x000000000000000000000000000000000ea54065c55f7bf279694e95512be477;
    uint256 constant IC8x_PART2 = 0xd42ac0c90e444aabea2ce4be63dcd3d7b6d74af1c3f3d475fb9ff4b6e2b0be1b;
    uint256 constant IC8y_PART1 = 0x0000000000000000000000000000000010bc256c25861d88330e1e42b159e35a;
    uint256 constant IC8y_PART2 = 0x3f9ac38fb4d0e181d1ab392679d5749dc7e572affebdfbddb8ed2ea7427c7472;

    uint256 constant IC9x_PART1 = 0x000000000000000000000000000000000f38207d2f851d124bd28789dd5f464d;
    uint256 constant IC9x_PART2 = 0xeb1cfd18dbb2a07a17688fa3e24818270acca6d3da35f17948678521712e9c9e;
    uint256 constant IC9y_PART1 = 0x000000000000000000000000000000000d304d17c4fefd7a78667936a7bdd8e8;
    uint256 constant IC9y_PART2 = 0x2a9d0b23c683a5122e7683ec358db5944df9803f8ea1c5f480174db92130ed19;

    uint256 constant IC10x_PART1 = 0x00000000000000000000000000000000035b25e53d6cbf45f1a2664ed0c71ac3;
    uint256 constant IC10x_PART2 = 0x74e30da61fe0a5ab3a0134bb231a2731dfdc0386bafc18c1b3674632286abeca;
    uint256 constant IC10y_PART1 = 0x000000000000000000000000000000001424477479442e64529947ffeb2fe8df;
    uint256 constant IC10y_PART2 = 0x40543006d0c9bd1a92a6f7e12bdceb14268ab38721fd95d369492fbab0c29454;

    uint256 constant IC11x_PART1 = 0x0000000000000000000000000000000013c71df95f24911eb7f51b5fa34f8c90;
    uint256 constant IC11x_PART2 = 0x8cd0087f98ae589f3694e7372c409b105692b2a3c6936ea130445b2f50087d26;
    uint256 constant IC11y_PART1 = 0x000000000000000000000000000000000c4c1fa9967cce79e206aa02288dc36d;
    uint256 constant IC11y_PART2 = 0x52aa078b49b3b20f9b698bf86c0cc82cf10c4cd41c8312659c743338c912d239;

    uint256 constant IC12x_PART1 = 0x00000000000000000000000000000000178d40f5ebd7ba5b91aa83631972f29a;
    uint256 constant IC12x_PART2 = 0x8f582ac5cb6a088842722d3e570f90997b6a5797a80c2513f5a43799bfeac762;
    uint256 constant IC12y_PART1 = 0x0000000000000000000000000000000017693f44442a213006b943c4435cbb74;
    uint256 constant IC12y_PART2 = 0x47700d698774e0b10720abc52dc49b89a458c801e5a24456ff5ce39ba1c05c32;

    uint256 constant IC13x_PART1 = 0x000000000000000000000000000000000309dd8b492f5e639141651605b7d682;
    uint256 constant IC13x_PART2 = 0x911c42fba8cc073e2b494642da20a74deaef70c3e8c9bcf10b01fc2949d2c095;
    uint256 constant IC13y_PART1 = 0x00000000000000000000000000000000189bbf018b62a9e37146e52b56371ac9;
    uint256 constant IC13y_PART2 = 0xd5bdd79236dd91be31bf6be48039fbaaa12404a8617c9e538ddd7fdb6f24d6ec;

    uint256 constant IC14x_PART1 = 0x00000000000000000000000000000000016a083c0f9cd61629c56ee069f54756;
    uint256 constant IC14x_PART2 = 0x14a0bcd14255027e6cb47a6beee85d6a8db235566869871de9a9a8bead71e7e8;
    uint256 constant IC14y_PART1 = 0x00000000000000000000000000000000188f43d08f552b4b098cd3ffec057566;
    uint256 constant IC14y_PART2 = 0x2bd11ce786b4ef6ae7aa60492ce5310e62bc8bcfa645e63db6b6d553a004c836;

    uint256 constant IC15x_PART1 = 0x0000000000000000000000000000000003c29acb4a567dfbb46d9795cbe3fffe;
    uint256 constant IC15x_PART2 = 0xa51362c3168156ceb47ff8e9afe61f143dc115bc27f60a202bf82a16d0247893;
    uint256 constant IC15y_PART1 = 0x0000000000000000000000000000000016ae85892b291d50453327749795d6df;
    uint256 constant IC15y_PART2 = 0xb1d690d9d205c0c7ad70a648d114c9c492e63b8fc7bc07b7435f426d1395aaf5;

    uint256 constant IC16x_PART1 = 0x000000000000000000000000000000001570b666f18e238a570df52ea73d695f;
    uint256 constant IC16x_PART2 = 0xc505014ac52f11251cbf2e9f06e4d05cb6d427e521e2436cc8a236d9751e7c23;
    uint256 constant IC16y_PART1 = 0x00000000000000000000000000000000104104348625ac6743ddc9e7835cf104;
    uint256 constant IC16y_PART2 = 0x207fe65336e94a734682e47f8cb7da2ea3cfbcd34a8c4df7090174174ced9960;

    uint256 constant IC17x_PART1 = 0x0000000000000000000000000000000005106c27aad2d795846882895772c82b;
    uint256 constant IC17x_PART2 = 0x3e31a05c25aa46e8edbb09d46112102e89f86d6e5e5cea769d9b16796a1bfe10;
    uint256 constant IC17y_PART1 = 0x0000000000000000000000000000000011382243f5e9b76da06a6259ebe55328;
    uint256 constant IC17y_PART2 = 0x15f61f111ab9cdb5c5e4d4b38f9e00645a33f2e45359d1e1ae29e0e9064aa041;

    uint256 constant IC18x_PART1 = 0x000000000000000000000000000000000799f4421039525f8b9c8eafec14e76a;
    uint256 constant IC18x_PART2 = 0xb3ce22411742878b04922bda532f68b0dd0f7be214a0bd7199be48735f27a4b8;
    uint256 constant IC18y_PART1 = 0x000000000000000000000000000000000c2654dc6ff9083578e151f3e44f32e0;
    uint256 constant IC18y_PART2 = 0xc80f49f809f53a6a0b8b92965a9bf4c47948d1610198cfd20bd0d99d5b9949d1;

    uint256 constant IC19x_PART1 = 0x000000000000000000000000000000000b785757f4600e6b43d906717d01f1ee;
    uint256 constant IC19x_PART2 = 0x3c17df668d103399856ebabfedc7274a01011ef567f159f3bb7e5ba1ac2c6fa5;
    uint256 constant IC19y_PART1 = 0x00000000000000000000000000000000001aea0f4d7d8d4f65f720e3bde41b1b;
    uint256 constant IC19y_PART2 = 0xc402e1a562f7aeb443f58c8426aed7536f033b3420efeb11d649fafd5e75fe29;

    uint256 constant IC20x_PART1 = 0x000000000000000000000000000000000ea5f4f26a548598383fda3fc379b834;
    uint256 constant IC20x_PART2 = 0x43e203748b2f9e7915b1d9a99ff190a3d184878a913a3b550bb016de0de70914;
    uint256 constant IC20y_PART1 = 0x0000000000000000000000000000000008504d56ea5c797d1ab0ac4e88ed984d;
    uint256 constant IC20y_PART2 = 0xf5acf3c857249d8af97dce6a1280cf935896e0a4f1030d1529dabc96b1a82cc6;

    uint256 constant IC21x_PART1 = 0x0000000000000000000000000000000001178be2273a47d5a87b657cdad786f2;
    uint256 constant IC21x_PART2 = 0x1351a4449617e9869173b4aea9d9cd8d873b0a691e9625435be1debf872ce385;
    uint256 constant IC21y_PART1 = 0x0000000000000000000000000000000006b4d869343e157b032b02190e2432ed;
    uint256 constant IC21y_PART2 = 0xb526acc1f42be4d707bfb7ae57b7d9278bb9d0f84984850cb339144bb82deaa0;

    uint256 constant IC22x_PART1 = 0x000000000000000000000000000000000f13706c09c5e8f6857fb70d217bb183;
    uint256 constant IC22x_PART2 = 0x6c3ca62e09da71b2104260a53e1b90d398a92bcef33c304281bb54dfcc72eb94;
    uint256 constant IC22y_PART1 = 0x000000000000000000000000000000000692b983b7569367382e076caf8cccbf;
    uint256 constant IC22y_PART2 = 0xad911eda16f9127b644d8b45e8e4ffb4fb3738480bbc2fb39b4cee462f49c962;

    uint256 constant IC23x_PART1 = 0x0000000000000000000000000000000009f4f09805256f443e43b40c610391ad;
    uint256 constant IC23x_PART2 = 0x1d0927172d223f54a911e6d1b63edfcd65cd54a0389e323a7ff012335d6c53d8;
    uint256 constant IC23y_PART1 = 0x00000000000000000000000000000000030677026ccdcb221981d134dcf1195e;
    uint256 constant IC23y_PART2 = 0xa26c2ebd86f07dba7ee125c69daf3108999e1c60e545faa355140e9a7837c36f;

    uint256 constant IC24x_PART1 = 0x000000000000000000000000000000000549eec6506512d8ab31f2707fdc7c7f;
    uint256 constant IC24x_PART2 = 0x976a0fe903db19679cf1e6ee70314936b1116e575b30f992002ef697b381ff7d;
    uint256 constant IC24y_PART1 = 0x00000000000000000000000000000000076d2f331795dfdabbc11352d8d3ce60;
    uint256 constant IC24y_PART2 = 0x4906b3fa1d63d9d463426d5be2979be5ce3a6f7323329eebc78ba3c8113451d2;

    uint256 constant IC25x_PART1 = 0x00000000000000000000000000000000146fc7d0fbf4125b471d0637d97f4391;
    uint256 constant IC25x_PART2 = 0xe31708eeba2821e2c6a7dda56971c836d79c223c2e3a6a18de47fdc4180d44fa;
    uint256 constant IC25y_PART1 = 0x000000000000000000000000000000001517e54261488981875e720eee03bf6d;
    uint256 constant IC25y_PART2 = 0x8384e43214ff2f095d41e165e7a07ab6eb44e2590a490e4c2dbd451d2bbe000d;

    uint256 constant IC26x_PART1 = 0x000000000000000000000000000000001572757993ce8014e79d3cad3027786c;
    uint256 constant IC26x_PART2 = 0x19088afd16f9e561c2c55420620078b0c0ab693c650d5987c6db0863ab2d6cbd;
    uint256 constant IC26y_PART1 = 0x000000000000000000000000000000000605b61c14f6d294b196ccf6fb86dc75;
    uint256 constant IC26y_PART2 = 0xa80fb8c50f2ae06677d511f9347c53de5462dcc7d223a6afe723648ff14de54f;

    uint256 constant IC27x_PART1 = 0x00000000000000000000000000000000023c56c0a07fa876d51d06f00e3ab108;
    uint256 constant IC27x_PART2 = 0x5f94510e426d843d4318bab5533c377d9ec5ae3a17fe76c2a51667a8c9fc4821;
    uint256 constant IC27y_PART1 = 0x00000000000000000000000000000000020af97fe1fe874fef61a85dd737ea5b;
    uint256 constant IC27y_PART2 = 0x11a0dc903e4e06da3460c04195f48bd015de722cedcf78a7ea639d25d2c190a3;

    uint256 constant IC28x_PART1 = 0x000000000000000000000000000000001804abe8e64449fe61f8443d7d5ef0b9;
    uint256 constant IC28x_PART2 = 0xbe5f9a3a51adf73746458722ca55fe064d046c9f94c5945e812db1d0aa47b7ad;
    uint256 constant IC28y_PART1 = 0x0000000000000000000000000000000005eec3835aacb0b2335c69503a731fcc;
    uint256 constant IC28y_PART2 = 0xbadce42685aca3e8ff851eb9beb165f0bb267af3088e3c6429505cd7cbd41fc7;

    uint256 constant IC29x_PART1 = 0x000000000000000000000000000000000e57320a8d8e7a85560b7addfec48967;
    uint256 constant IC29x_PART2 = 0x874670297df5f7414dc76772149bcd666a13095901445f657139a57ff2c15976;
    uint256 constant IC29y_PART1 = 0x000000000000000000000000000000000f633c495e0ac018804d9e37a693f406;
    uint256 constant IC29y_PART2 = 0xfa53d59e0712f34c373fbb6d3d87504d1cdf8f1018b3668149c021dc5552dc77;

    uint256 constant IC30x_PART1 = 0x0000000000000000000000000000000001f8897fbeb26ecd34e7bd22aadf02b0;
    uint256 constant IC30x_PART2 = 0x3b40cd1cda9280456da7c0aee64b3927ab9b0a41133e781f179f3fbae000efde;
    uint256 constant IC30y_PART1 = 0x000000000000000000000000000000001425f9e72dceed9c2182f3311f4f95cb;
    uint256 constant IC30y_PART2 = 0xaabe04b78076f6f43ad90cda81eb7075625c21b2bb9625eddb29536badcfaa56;

    uint256 constant IC31x_PART1 = 0x00000000000000000000000000000000015e6b504766ade9e76aa07946f4d617;
    uint256 constant IC31x_PART2 = 0xce417457efa53aad3217362b926b4276a8e2019078b58f5df5bff0f9e25fad9e;
    uint256 constant IC31y_PART1 = 0x000000000000000000000000000000000104a4f63eb3d2c2c8c3273a2e7f79d4;
    uint256 constant IC31y_PART2 = 0x0e7cf24dfd7391ff99846951de562b63625844351051f28c553b9c37d713675b;

    uint256 constant IC32x_PART1 = 0x000000000000000000000000000000001760f5fb8e6648c17d421bdc0e253ba8;
    uint256 constant IC32x_PART2 = 0x73e10644849de70e8ebe892839356689e8e99527672e592abab142709426d46d;
    uint256 constant IC32y_PART1 = 0x00000000000000000000000000000000030aa2f95f6590f64f4bc558ed674372;
    uint256 constant IC32y_PART2 = 0x2b769a63e184bdf0a3f786c30ee08b3c48a031616f758705145173eff748084a;

    uint256 constant IC33x_PART1 = 0x000000000000000000000000000000000aebf4293fe911e2e9473f6be0d523fd;
    uint256 constant IC33x_PART2 = 0x734be905d8bed8d5f4d2465b7d235fd9037fe0f08f046002820e2d9a2e46725c;
    uint256 constant IC33y_PART1 = 0x000000000000000000000000000000000e41363f04b540b2ba99a4de0b05805a;
    uint256 constant IC33y_PART2 = 0xd4e17fd00c265ca9840e7b147af9cc5e5a5ffbb0c0d2274608a09898e7735836;

    uint256 constant IC34x_PART1 = 0x0000000000000000000000000000000010a4f4d7e92a409610cc2263ae78363d;
    uint256 constant IC34x_PART2 = 0x3c63debbb557d1c23827a378d33fe9bcefc78816c78d5a94e0c509a47522a4ca;
    uint256 constant IC34y_PART1 = 0x00000000000000000000000000000000168a19d2f9aa689e3f98c46dfdd5b2e4;
    uint256 constant IC34y_PART2 = 0x24c84aed3b025fd603e0dc3de3a6b421fe7fcaad71e04eb8f94c64dcec0bc706;

    uint256 constant IC35x_PART1 = 0x000000000000000000000000000000001495f19c35fe990ceebef98df375a756;
    uint256 constant IC35x_PART2 = 0x1eed35a0b2c0808955c5c9e107cc8b9a30dd6a73ba5d2ca0e1f1a87417a5c4c2;
    uint256 constant IC35y_PART1 = 0x0000000000000000000000000000000008ea5279e086b6ed8bf16caa5670ea7d;
    uint256 constant IC35y_PART2 = 0x28b12ecc662fa022bcf892778f4c8e459b3f4611f63c6eea0abfb7f8279d86cc;

    // Memory data
    uint16 constant pVk = 0;
    uint16 constant pPairing = 128;

    uint16 constant pLastMem = 1664;

    function verifyProof(
        uint256[4] calldata _pA,
        uint256[8] calldata _pB,
        uint256[4] calldata _pC,
        uint256[35] calldata _pubSignals
    ) public view returns (bool) {
        assembly {
            function checkField(v) {
                if iszero(lt(v, R_MOD)) {
                    mstore(0, 0)
                    return(0, 0x20)
                }
            }

            // G1 function to multiply a G1 value(x,y) to value in an address
            function g1_mulAccC(pR, x0, x1, y0, y1, s) {
                let success
                let mIn := mload(0x40)
                mstore(mIn, x0)
                mstore(add(mIn, 32), x1)
                mstore(add(mIn, 64), y0)
                mstore(add(mIn, 96), y1)
                mstore(add(mIn, 128), s)

                success := staticcall(sub(gas(), 2000), 0x0c, mIn, 160, mIn, 128)

                if iszero(success) {
                    mstore(0, 0)
                    return(0, 0x20)
                }

                mstore(add(mIn, 128), mload(pR))
                mstore(add(mIn, 160), mload(add(pR, 32)))
                mstore(add(mIn, 192), mload(add(pR, 64)))
                mstore(add(mIn, 224), mload(add(pR, 96)))

                success := staticcall(sub(gas(), 2000), 0x0b, mIn, 256, pR, 128)

                if iszero(success) {
                    mstore(0, 0)
                    return(0, 0x20)
                }
            }

            function checkPairing(pA, pB, pC, pubSignals, pMem) -> isOk {
                let _pPairing := add(pMem, pPairing)
                let _pVk := add(pMem, pVk)

                // Initialize vk_x with IC0 (the constant term)
                mstore(_pVk, IC0x_PART1)
                mstore(add(_pVk, 32), IC0x_PART2)
                mstore(add(_pVk, 64), IC0y_PART1)
                mstore(add(_pVk, 96), IC0y_PART2)

                // Compute the linear combination vk_x = IC0 + IC1*pubSignals[0] + IC2*pubSignals[1] + ...

                g1_mulAccC(_pVk, IC1x_PART1, IC1x_PART2, IC1y_PART1, IC1y_PART2, calldataload(add(pubSignals, 0)))

                g1_mulAccC(_pVk, IC2x_PART1, IC2x_PART2, IC2y_PART1, IC2y_PART2, calldataload(add(pubSignals, 32)))

                g1_mulAccC(_pVk, IC3x_PART1, IC3x_PART2, IC3y_PART1, IC3y_PART2, calldataload(add(pubSignals, 64)))

                g1_mulAccC(_pVk, IC4x_PART1, IC4x_PART2, IC4y_PART1, IC4y_PART2, calldataload(add(pubSignals, 96)))

                g1_mulAccC(_pVk, IC5x_PART1, IC5x_PART2, IC5y_PART1, IC5y_PART2, calldataload(add(pubSignals, 128)))

                g1_mulAccC(_pVk, IC6x_PART1, IC6x_PART2, IC6y_PART1, IC6y_PART2, calldataload(add(pubSignals, 160)))

                g1_mulAccC(_pVk, IC7x_PART1, IC7x_PART2, IC7y_PART1, IC7y_PART2, calldataload(add(pubSignals, 192)))

                g1_mulAccC(_pVk, IC8x_PART1, IC8x_PART2, IC8y_PART1, IC8y_PART2, calldataload(add(pubSignals, 224)))

                g1_mulAccC(_pVk, IC9x_PART1, IC9x_PART2, IC9y_PART1, IC9y_PART2, calldataload(add(pubSignals, 256)))

                g1_mulAccC(_pVk, IC10x_PART1, IC10x_PART2, IC10y_PART1, IC10y_PART2, calldataload(add(pubSignals, 288)))

                g1_mulAccC(_pVk, IC11x_PART1, IC11x_PART2, IC11y_PART1, IC11y_PART2, calldataload(add(pubSignals, 320)))

                g1_mulAccC(_pVk, IC12x_PART1, IC12x_PART2, IC12y_PART1, IC12y_PART2, calldataload(add(pubSignals, 352)))

                g1_mulAccC(_pVk, IC13x_PART1, IC13x_PART2, IC13y_PART1, IC13y_PART2, calldataload(add(pubSignals, 384)))

                g1_mulAccC(_pVk, IC14x_PART1, IC14x_PART2, IC14y_PART1, IC14y_PART2, calldataload(add(pubSignals, 416)))

                g1_mulAccC(_pVk, IC15x_PART1, IC15x_PART2, IC15y_PART1, IC15y_PART2, calldataload(add(pubSignals, 448)))

                g1_mulAccC(_pVk, IC16x_PART1, IC16x_PART2, IC16y_PART1, IC16y_PART2, calldataload(add(pubSignals, 480)))

                g1_mulAccC(_pVk, IC17x_PART1, IC17x_PART2, IC17y_PART1, IC17y_PART2, calldataload(add(pubSignals, 512)))

                g1_mulAccC(_pVk, IC18x_PART1, IC18x_PART2, IC18y_PART1, IC18y_PART2, calldataload(add(pubSignals, 544)))

                g1_mulAccC(_pVk, IC19x_PART1, IC19x_PART2, IC19y_PART1, IC19y_PART2, calldataload(add(pubSignals, 576)))

                g1_mulAccC(_pVk, IC20x_PART1, IC20x_PART2, IC20y_PART1, IC20y_PART2, calldataload(add(pubSignals, 608)))

                g1_mulAccC(_pVk, IC21x_PART1, IC21x_PART2, IC21y_PART1, IC21y_PART2, calldataload(add(pubSignals, 640)))

                g1_mulAccC(_pVk, IC22x_PART1, IC22x_PART2, IC22y_PART1, IC22y_PART2, calldataload(add(pubSignals, 672)))

                g1_mulAccC(_pVk, IC23x_PART1, IC23x_PART2, IC23y_PART1, IC23y_PART2, calldataload(add(pubSignals, 704)))

                g1_mulAccC(_pVk, IC24x_PART1, IC24x_PART2, IC24y_PART1, IC24y_PART2, calldataload(add(pubSignals, 736)))

                g1_mulAccC(_pVk, IC25x_PART1, IC25x_PART2, IC25y_PART1, IC25y_PART2, calldataload(add(pubSignals, 768)))

                g1_mulAccC(_pVk, IC26x_PART1, IC26x_PART2, IC26y_PART1, IC26y_PART2, calldataload(add(pubSignals, 800)))

                g1_mulAccC(_pVk, IC27x_PART1, IC27x_PART2, IC27y_PART1, IC27y_PART2, calldataload(add(pubSignals, 832)))

                g1_mulAccC(_pVk, IC28x_PART1, IC28x_PART2, IC28y_PART1, IC28y_PART2, calldataload(add(pubSignals, 864)))

                g1_mulAccC(_pVk, IC29x_PART1, IC29x_PART2, IC29y_PART1, IC29y_PART2, calldataload(add(pubSignals, 896)))

                g1_mulAccC(_pVk, IC30x_PART1, IC30x_PART2, IC30y_PART1, IC30y_PART2, calldataload(add(pubSignals, 928)))

                g1_mulAccC(_pVk, IC31x_PART1, IC31x_PART2, IC31y_PART1, IC31y_PART2, calldataload(add(pubSignals, 960)))

                g1_mulAccC(_pVk, IC32x_PART1, IC32x_PART2, IC32y_PART1, IC32y_PART2, calldataload(add(pubSignals, 992)))

                g1_mulAccC(
                    _pVk, IC33x_PART1, IC33x_PART2, IC33y_PART1, IC33y_PART2, calldataload(add(pubSignals, 1024))
                )

                g1_mulAccC(_pVk, IC34x_PART1, IC34x_PART2, IC34y_PART1, IC34y_PART2, calldataload(add(pubSignals, 1056)))

                g1_mulAccC(_pVk, IC35x_PART1, IC35x_PART2, IC35y_PART1, IC35y_PART2, calldataload(add(pubSignals, 1088)))

                // -A (48-byte BLS12-381 format with proper base field negation)
                mstore(_pPairing, calldataload(pA)) // _pA[0][0] (x_PART1)
                mstore(add(_pPairing, 32), calldataload(add(pA, 32))) // _pA[0][1] (x_PART2)

                // Negate y-coordinate using proper BLS12-381 base field arithmetic: q - y
                let y_high := calldataload(add(pA, 64)) // y_PART1 (high part)
                let y_low := calldataload(add(pA, 96)) // y_PART2 (low part)

                let neg_y_high, neg_y_low
                let borrow := 0

                // Correct BLS12-381 field negation: q - y where q = Q_MOD_PART1 || Q_MOD_PART2
                // Handle the subtraction properly with borrowing
                switch lt(Q_MOD_PART2, y_low)
                case 1 {
                    // Need to borrow from high part
                    neg_y_low := sub(Q_MOD_PART2, y_low)
                    neg_y_low := add(neg_y_low, not(0)) // Add 2^256
                    neg_y_low := add(neg_y_low, 1)
                    borrow := 1
                }
                default {
                    neg_y_low := sub(Q_MOD_PART2, y_low)
                    borrow := 0
                }

                // Subtract high part with borrow
                neg_y_high := sub(sub(Q_MOD_PART1, y_high), borrow)

                mstore(add(_pPairing, 64), neg_y_high) // _pA[1][0] (-y_PART1)
                mstore(add(_pPairing, 96), neg_y_low) // _pA[1][1] (-y_PART2)

                // B (48-byte BLS12-381 format)
                // B G2 point order: x1, x0, y1, y0
                mstore(add(_pPairing, 128), calldataload(add(pB, 64))) // x1_PART1
                mstore(add(_pPairing, 160), calldataload(add(pB, 96))) // x1_PART2
                mstore(add(_pPairing, 192), calldataload(pB)) // x0_PART1
                mstore(add(_pPairing, 224), calldataload(add(pB, 32))) // x0_PART2
                mstore(add(_pPairing, 256), calldataload(add(pB, 192))) // y1_PART1
                mstore(add(_pPairing, 288), calldataload(add(pB, 224))) // y1_PART2
                mstore(add(_pPairing, 320), calldataload(add(pB, 128))) // y0_PART1
                mstore(add(_pPairing, 352), calldataload(add(pB, 160))) // y0_PART2

                // alpha1 (48-byte format) - PAIR 4 G1
                mstore(add(_pPairing, 384), alphax_PART1)
                mstore(add(_pPairing, 416), alphax_PART2)
                mstore(add(_pPairing, 448), alphay_PART1)
                mstore(add(_pPairing, 480), alphay_PART2)

                // beta2 G2 point order: x1, x0, y1, y0
                mstore(add(_pPairing, 512), betax1_PART1) // x0_PART1
                mstore(add(_pPairing, 544), betax1_PART2) // x0_PART2
                mstore(add(_pPairing, 576), betax2_PART1) // x1_PART1
                mstore(add(_pPairing, 608), betax2_PART2) // x1_PART2
                mstore(add(_pPairing, 640), betay1_PART1) // y0_PART1
                mstore(add(_pPairing, 672), betay1_PART2) // y0_PART2
                mstore(add(_pPairing, 704), betay2_PART1) // y1_PART1
                mstore(add(_pPairing, 736), betay2_PART2) // y1_PART2

                // vk_x (48-byte format from G1 point) - PAIR 2 G1
                mstore(add(_pPairing, 768), mload(add(pMem, pVk))) // x_PART1
                mstore(add(_pPairing, 800), mload(add(pMem, add(pVk, 32)))) // x_PART2
                mstore(add(_pPairing, 832), mload(add(pMem, add(pVk, 64)))) // y_PART1
                mstore(add(_pPairing, 864), mload(add(pMem, add(pVk, 96)))) // y_PART2

                // gamma2 G2 point order: x1, x0, y1, y0
                mstore(add(_pPairing, 896), gammax2_PART1) // x1_PART1
                mstore(add(_pPairing, 928), gammax2_PART2) // x1_PART2
                mstore(add(_pPairing, 960), gammax1_PART1) // x0_PART1
                mstore(add(_pPairing, 992), gammax1_PART2) // x0_PART2
                mstore(add(_pPairing, 1024), gammay2_PART1) // y1_PART1
                mstore(add(_pPairing, 1056), gammay2_PART2) // y1_PART2
                mstore(add(_pPairing, 1088), gammay1_PART1) // y0_PART1
                mstore(add(_pPairing, 1120), gammay1_PART2) // y0_PART2

                // C (48-byte BLS12-381 format) - PAIR 3 G1
                mstore(add(_pPairing, 1152), calldataload(pC)) // _pC[0][0] (x_PART1)
                mstore(add(_pPairing, 1184), calldataload(add(pC, 32))) // _pC[0][1] (x_PART2)
                mstore(add(_pPairing, 1216), calldataload(add(pC, 64))) // _pC[1][0] (y_PART1)
                mstore(add(_pPairing, 1248), calldataload(add(pC, 96))) // _pC[1][1] (y_PART2)

                // delta2 G2 point order: x1, x0, y1, y0
                mstore(add(_pPairing, 1280), deltax1_PART1) // x0_PART1
                mstore(add(_pPairing, 1312), deltax1_PART2) // x0_PART2
                mstore(add(_pPairing, 1344), deltax2_PART1) // x1_PART1
                mstore(add(_pPairing, 1376), deltax2_PART2) // x1_PART2
                mstore(add(_pPairing, 1408), deltay1_PART1) // y0_PART1
                mstore(add(_pPairing, 1440), deltay1_PART2) // y0_PART2
                mstore(add(_pPairing, 1472), deltay2_PART1) // y1_PART1
                mstore(add(_pPairing, 1504), deltay2_PART2) // y1_PART2

                let success := staticcall(sub(gas(), 2000), 0x0f, _pPairing, 1536, _pPairing, 0x20)

                isOk := and(success, mload(_pPairing))
            }

            let pMem := mload(0x40)
            mstore(0x40, add(pMem, pLastMem))

            // Validate that all evaluations ∈ F

            checkField(calldataload(add(_pubSignals, 0)))

            checkField(calldataload(add(_pubSignals, 32)))

            checkField(calldataload(add(_pubSignals, 64)))

            checkField(calldataload(add(_pubSignals, 96)))

            checkField(calldataload(add(_pubSignals, 128)))

            checkField(calldataload(add(_pubSignals, 160)))

            checkField(calldataload(add(_pubSignals, 192)))

            checkField(calldataload(add(_pubSignals, 224)))

            checkField(calldataload(add(_pubSignals, 256)))

            checkField(calldataload(add(_pubSignals, 288)))

            checkField(calldataload(add(_pubSignals, 320)))

            checkField(calldataload(add(_pubSignals, 352)))

            checkField(calldataload(add(_pubSignals, 384)))

            checkField(calldataload(add(_pubSignals, 416)))

            checkField(calldataload(add(_pubSignals, 448)))

            checkField(calldataload(add(_pubSignals, 480)))

            checkField(calldataload(add(_pubSignals, 512)))

            checkField(calldataload(add(_pubSignals, 544)))

            checkField(calldataload(add(_pubSignals, 576)))

            checkField(calldataload(add(_pubSignals, 608)))

            checkField(calldataload(add(_pubSignals, 640)))

            checkField(calldataload(add(_pubSignals, 672)))

            checkField(calldataload(add(_pubSignals, 704)))

            checkField(calldataload(add(_pubSignals, 736)))

            checkField(calldataload(add(_pubSignals, 768)))

            checkField(calldataload(add(_pubSignals, 800)))

            checkField(calldataload(add(_pubSignals, 832)))

            checkField(calldataload(add(_pubSignals, 864)))

            checkField(calldataload(add(_pubSignals, 896)))

            checkField(calldataload(add(_pubSignals, 928)))

            checkField(calldataload(add(_pubSignals, 960)))

            checkField(calldataload(add(_pubSignals, 992)))

            checkField(calldataload(add(_pubSignals, 1024)))

            checkField(calldataload(add(_pubSignals, 1056)))

            checkField(calldataload(add(_pubSignals, 1088)))

            // Validate all evaluations
            let isValid := checkPairing(_pA, _pB, _pC, _pubSignals, pMem)

            mstore(0, isValid)
            return(0, 0x20)
        }
    }

    // Backward-compatible overload for legacy tests expecting 33 public signals.
    function verifyProof(
        uint256[4] calldata _pA,
        uint256[8] calldata _pB,
        uint256[4] calldata _pC,
        uint256[33] calldata _pubSignals
    ) external view returns (bool) {
        uint256[35] memory expanded;
        for (uint256 i = 0; i < 33; i++) {
            expanded[i] = _pubSignals[i];
        }
        return this.verifyProof(_pA, _pB, _pC, expanded);
    }
}
