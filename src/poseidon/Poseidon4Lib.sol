// SPDX-License-Identifier: MIT
pragma solidity >=0.8.8;

import {Poseidon4Field} from "./Poseidon4Field.sol";

// Uses BLS12-381 scalar Poseidon4Field and 5-element state (t=5)
library Poseidon4Lib {
    using Poseidon4Field for *;

    uint256 constant t = 5; // State size: 4 inputs + 1 capacity
    uint256 constant rFull = 8; // Full rounds
    uint256 constant rPartial = 56; // Partial rounds
    uint256 constant RATE = 4; // Rate for sponge

    struct Constants {
        Poseidon4Field.Type[320] round_constants; // Total round constants for t=5
        Poseidon4Field.Type[5][5] mds_matrix; // MDS matrix for t=5
    }

    /**
     * Takes 4 inputs and returns first element of permutation
     */
    function poseidon4Direct(Poseidon4Field.Type[4] memory inputs) internal pure returns (Poseidon4Field.Type) {
        Poseidon4Field.Type[5] memory state;
        state[0] = Poseidon4Field.Type.wrap(0); // Initialize first element to 0
        state[1] = inputs[0];          // First input
        state[2] = inputs[1];          // Second input
        state[3] = inputs[2];          // Third input
        state[4] = inputs[3];          // Fourth input
        
        Constants memory constants = load();
        Poseidon4Field.Type[5] memory result = poseidonPermutation(
            state,
            rFull,
            rPartial,
            constants.round_constants,
            constants.mds_matrix
        );
        
        return result[0]; // Return first element as per npm library implementation
    }

    /**
     * This implements the correct Poseidon2 specification with proper modulo operations
     */
    function poseidonPermutation(
        Poseidon4Field.Type[5] memory inputs,
        uint256 _rFull,
        uint256 _rPartial,
        Poseidon4Field.Type[320] memory roundConstants,
        Poseidon4Field.Type[5][5] memory mds
    ) internal pure returns (Poseidon4Field.Type[5] memory) {
        Poseidon4Field.Type[5] memory state = inputs;

        uint256 roundConstantsCounter = 0;
        uint256 rFullHalf = _rFull / 2;

        // First half of full rounds
        for (uint256 i = 0; i < rFullHalf; i++) {
            // Add round constants
            for (uint256 j = 0; j < t; j++) {
                state[j] = state[j].add(roundConstants[roundConstantsCounter]);
                roundConstantsCounter++;
            }

            // S-box (x^5) with proper modulo
            for (uint256 j = 0; j < t; j++) {
                state[j] = sBox(state[j]);
            }

            // MDS matrix multiplication
            state = matrixMultiplication(state, mds);
        }

        // Partial rounds
        for (uint256 i = 0; i < _rPartial; i++) {
            // Add round constants
            for (uint256 j = 0; j < t; j++) {
                state[j] = state[j].add(roundConstants[roundConstantsCounter]);
                roundConstantsCounter++;
            }

            // S-box only on first element
            state[0] = sBox(state[0]);

            // MDS matrix multiplication
            state = matrixMultiplication(state, mds);
        }

        // Second half of full rounds
        for (uint256 i = 0; i < rFullHalf; i++) {
            // Add round constants
            for (uint256 j = 0; j < t; j++) {
                state[j] = state[j].add(roundConstants[roundConstantsCounter]);
                roundConstantsCounter++;
            }

            // S-box (x^5) with proper modulo
            for (uint256 j = 0; j < t; j++) {
                state[j] = sBox(state[j]);
            }

            // MDS matrix multiplication
            state = matrixMultiplication(state, mds);
        }

        return state;
    }

    /**
     * S-box function: x^5 mod p
     */
    function sBox(Poseidon4Field.Type x) private pure returns (Poseidon4Field.Type) {
        return x.pow(5);
    }

    /**
     * Matrix multiplication with 5x5 MDS matrix
     */
    function matrixMultiplication(Poseidon4Field.Type[5] memory input, Poseidon4Field.Type[5][5] memory mds)
        private
        pure
        returns (Poseidon4Field.Type[5] memory)
    {
        Poseidon4Field.Type[5] memory result;

        for (uint256 i = 0; i < 5; i++) {
            result[i] = Poseidon4Field.Type.wrap(0);
            for (uint256 j = 0; j < 5; j++) {
                result[i] = result[i].add(mds[i][j].mul(input[j]));
            }
        }

        return result;
    }

    /**
     * Load constants from the off-chain library
     */
    function load() internal pure returns (Constants memory constants) {
        // Round constants from the off-chain implementation
        constants.round_constants = [
            Poseidon4Field.Type.wrap(0x5c5bec06aa43ca811a9c78919fe505276e4625b2dc92b86947cc4d7726c77d3d),
            Poseidon4Field.Type.wrap(0x6268bc5f9031edb5b6bc2edbbe091cce714d51abbba4301fa0a19319da4ca232),
            Poseidon4Field.Type.wrap(0x4572aeff3e581883c3333a4fcb784afdd0f4b81f0d34e36835fd9a2644342b6a),
            Poseidon4Field.Type.wrap(0x2c44402b93c5ac82bc8bb58e947fca107e865d85b1cb0f1f32f0c05cdaf439f8),
            Poseidon4Field.Type.wrap(0x023eb54d53e89505d0c9258bee0de17bb0a11e451b48d22d88549e05e2018403),
            Poseidon4Field.Type.wrap(0x5c3c49994dfe7863f506ee54719e6ee22a8136da7b276fd95b222de90b48feec),
            Poseidon4Field.Type.wrap(0x349b3f7366f89983b3858e40a22f53fa2e62ad46932303ce85d42591ca5141a3),
            Poseidon4Field.Type.wrap(0x0b383428a756701b8c1c1c38c9c3abbb4df3b6fbb5a581fe9bba326455776e91),
            Poseidon4Field.Type.wrap(0x6814d01a7834e8f1f53b89bae25702ed6c864c49ffba3820e6106185e81a85e1),
            Poseidon4Field.Type.wrap(0x382d39c6bdbba256b12d3fa4476187c14c4867255ea999c6503e92f520e9a918),
            Poseidon4Field.Type.wrap(0x507aa38edca7a8d6925c668abc3a17a3252efb8f94740a7775db0bb328d1061e),
            Poseidon4Field.Type.wrap(0x3bd1bbe1f40eb3fa7def818257305e9c50a675d756e6aed051fc4e7b7b132d8b),
            Poseidon4Field.Type.wrap(0x4ddaf59374164d01c4c07ac09d306653f607cb880ab16330c680994321df3f4a),
            Poseidon4Field.Type.wrap(0x36a92b9f74005c1802eb60930a7135d4af73fc20a535506093f98fa0aa1fbd91),
            Poseidon4Field.Type.wrap(0x1eeb8e80a4a1382bda0c063aa61dad5da57fa80865d0beeb2b9e69a07b5965f4),
            Poseidon4Field.Type.wrap(0x245c1c6d6f21bf7dd2abd1626514169678fa53bd900f6bd2cd854a9a965cb77b),
            Poseidon4Field.Type.wrap(0x4fee9d33743fa477a4fe71f77e5c95778db9c7efee51846f4a2d369e18a15cdd),
            Poseidon4Field.Type.wrap(0x1a1492b84929e7080f0b6c8b1c46e9164beed12136837032670d44165d269c69),
            Poseidon4Field.Type.wrap(0x64f9e3fa689c48974257c4e505827bb9c0babbe89366dfcbb3162eafab4e8b07),
            Poseidon4Field.Type.wrap(0x0b0a1a2b2762612d71d2f2d692c632218b5e47f3f0e38d638cfd365c313dbd48),
            Poseidon4Field.Type.wrap(0x05b20208ea0377139f322767d36fea854d28ccedb083ab8901f4054f822c5101),
            Poseidon4Field.Type.wrap(0x0710c608d8a48043e99dd94a0b1d22906b67dafb6bc5b95adf8c2f24ce81b0cd),
            Poseidon4Field.Type.wrap(0x68e5bf430d23864f21836ccefc1fac4801bdc00cc43de2608532d788c7fb45e7),
            Poseidon4Field.Type.wrap(0x09221b8a932a7820912b20bf5b919b7e0a22b3c9d2a1f0d9832ca03b0fc0ed9f),
            Poseidon4Field.Type.wrap(0x65ac3ba4cbab3d2622b373ef54c1dfb299e7fb992555478d5c1c44ee78632953),
            Poseidon4Field.Type.wrap(0x114be59c06f561e8324e306a28896fb1dd3802773891f54f0b8243718ef12542),
            Poseidon4Field.Type.wrap(0x61d96c0b2e0683a2d7ffcd9e0b3a58b86fb3ecca7941391e597efc13f38ff503),
            Poseidon4Field.Type.wrap(0x103454e35e0f4d690d8d1ab122b4c5c92e0512004f1af1e3140694c686cbeba9),
            Poseidon4Field.Type.wrap(0x2d2d628ded9373dcfc3ad59072a51b9a2d6c8c470753066195b77ca3a821fe47),
            Poseidon4Field.Type.wrap(0x2b0bf337fd4454a5e38344e0e711b9ae2281545fd99ad3fe46da2e1e4b9c98ce),
            Poseidon4Field.Type.wrap(0x0575c431f72a40242de5963e47cc7dad1aced5d9a1c9de5ac7ab5c22fad3cd67),
            Poseidon4Field.Type.wrap(0x0ec8f181daf128e716d3d7726dcf8ecbdddadca0063dc726196baec197eb3612),
            Poseidon4Field.Type.wrap(0x33779259084a94462f31c2650f6affd717ea200e62d2349f07fba50dd64b4875),
            Poseidon4Field.Type.wrap(0x122bdda32a00e4a3335a55fb2af4a24044fe2b223bebbbde2b32e09ef1add101),
            Poseidon4Field.Type.wrap(0x14884ad16b1f79e5ba9d3c24b2f3f76272411ddfaa9bafb421ef4d583ba736bc),
            Poseidon4Field.Type.wrap(0x323f85cbba64efc38ccc35c5fa9d673fef3ff652da7f2f93e176a40de61e1e70),
            Poseidon4Field.Type.wrap(0x1a3fac3af20c37aed0e41f6fa6f1a488401f16c61fc3a4e86cda951a0e3795e3),
            Poseidon4Field.Type.wrap(0x1d927c14cd47e25613656bc80171954894d2e882e35a4dc804cbc0803d47a814),
            Poseidon4Field.Type.wrap(0x22f1a2a2ade490e188fea20d062700568123e4b54290ab6a695584f3ec971eab),
            Poseidon4Field.Type.wrap(0x2c04db231c81645f30937dc5546efb30690acea9ef5769ce42000f486f893a45),
            Poseidon4Field.Type.wrap(0x21385b6f914a8c6f421629278dfa84f2ccdcf621b05013247341438237ad3fc1),
            Poseidon4Field.Type.wrap(0x2f00090ff1cb76eaf3b6cf23718ae736af07c34cac823388e0234420247e3160),
            Poseidon4Field.Type.wrap(0x455e8b0828f3667021a434761d5b6a5fb2e90635a6b038e4315f8a30dda4af00),
            Poseidon4Field.Type.wrap(0x028b320c702e077887d5556c7c879c7d54c6c681497a1d4fa5f2045fc553211f),
            Poseidon4Field.Type.wrap(0x2502f751749978112c96e7321ff1c0b76b3ff74190dadba0b67eac15462079f4),
            Poseidon4Field.Type.wrap(0x0a02577f723a21ced13408ed76b38ad8bbdfcc8132bb6dfbbbea8ece52e0e810),
            Poseidon4Field.Type.wrap(0x55d052b889557f2fc0e61e83b82261a759b75cfbec4c6f97b1104301163753b7),
            Poseidon4Field.Type.wrap(0x450a0821b86175e4877ccb7e8b1918bbe3e88819bc9ed36ce30cca14b8eeb911),
            Poseidon4Field.Type.wrap(0x4a399ec4758d73d11ab365f26081aea3a61d156ec6f0185a18702e8ee1631f18),
            Poseidon4Field.Type.wrap(0x1305a1f607f37901c0a88b2b7f23672efec118296f4550a058f4f94c25b66092),
            Poseidon4Field.Type.wrap(0x08e98ff1f10c0092b41a881d5663d8d85b081830f3f5bc904dc9b2a88969344d),
            Poseidon4Field.Type.wrap(0x1a986478818b795d1a509aff8d2ac2588342e320b77c1ebda86c5be7b0389487),
            Poseidon4Field.Type.wrap(0x3a68e478946a5cfc6c3a21c7416ad4afa64f7130ddf8986935942d6835665edd),
            Poseidon4Field.Type.wrap(0x115b2ef9469d91408b6e1d46e671d335aabac9d8882cdf17d1afb385b1051e3e),
            Poseidon4Field.Type.wrap(0x0b7fe376d67252e90d9f06b43947fca03a50072c24d8598b7248fbc8b0d64e9e),
            Poseidon4Field.Type.wrap(0x621fba0544792a4910a92402dc5c56630bbdc50cad3edc99ee6e5466b7295042),
            Poseidon4Field.Type.wrap(0x47ea2bb0150f7e51992433be07d695f5ee93a948cdee6fe573b5ddd9702ac19f),
            Poseidon4Field.Type.wrap(0x3333d094869d1f23f0ae3787ad1c105122e8338b51b7a970260ea700d409d55e),
            Poseidon4Field.Type.wrap(0x36291942b0c4d1329fa0db7230b3ef9be3e8e4b1b51897631bed81ef4d405327),
            Poseidon4Field.Type.wrap(0x548bdc2c8e44774efaa30d0df03cd307b25ef86fe73bfd7de1c16116afa8d432),
            Poseidon4Field.Type.wrap(0x2ff0b6bb42027bb7b5eff8a312df92db0928c4fd5f47b6cdd87a13c5983b50b5),
            Poseidon4Field.Type.wrap(0x4765640bd361f949a2ba640706c1f1436dc29d769c57a31b027bd6dd4c1c799b),
            Poseidon4Field.Type.wrap(0x311b329ed3aafeae007cabd2bd3cf506698ea4248dc684145e0d2a2fd789a8b8),
            Poseidon4Field.Type.wrap(0x18cf391449564ad053c4af0b0734e6c1f1de59d415ede6c4ded5a29e64420565),
            Poseidon4Field.Type.wrap(0x030053d7aa258bd41e80bc261fbea820091418b2fe5121ce24e12c1ad57cfe12),
            Poseidon4Field.Type.wrap(0x347d2cc8b97eca81ed23167c5c2f6cb214972cc54cb86f93e5e49b52ab79ef81),
            Poseidon4Field.Type.wrap(0x73e40cea4c8924cc70d7555087c7384af177bf4ba4fcd4d923c3bd78072bf437),
            Poseidon4Field.Type.wrap(0x5d26bfff868d80acb7185d70543557aca3886e17dc537ca7997b834939f34525),
            Poseidon4Field.Type.wrap(0x41ebe1430659e09fcb9a8ae6be869b51bb1261dfda863efc4ccb60ab9d2d3dea),
            Poseidon4Field.Type.wrap(0x32f72f5fabe91e618ef627a08e9d8667a9180a22c10aa859d70b80239bfc8cc6),
            Poseidon4Field.Type.wrap(0x0ffdf50ad0cb49c17906f3cc43ee935b6a82cd5ac4574beb8d9df72eab4e806c),
            Poseidon4Field.Type.wrap(0x61374dc1b440ea38ca2bc3c49d6060f4f0e32ba7669040e30388caf2ab833e11),
            Poseidon4Field.Type.wrap(0x27ec5217fa23b99f059a21d5ef05e9e477bd68025545246edce72bd7d70acb4b),
            Poseidon4Field.Type.wrap(0x6a91bd2230a5d48e7496d52dc84436e077f89f44bd08d883e74257df856440ce),
            Poseidon4Field.Type.wrap(0x4988f6b46cff4106095f3a8b6e07fc1a50f8f419b0778645b564e69638fb7e34),
            Poseidon4Field.Type.wrap(0x5255dfc95d1c0ca86a7ed39bbe02112cf62e4ee518b40901768e0ea5a2c30bcf),
            Poseidon4Field.Type.wrap(0x35491d836b717f64d348e449d958bada0f89479479c18787c9046c846261de24),
            Poseidon4Field.Type.wrap(0x5f28561407a056594276543ccfbfedb72892cadd7eb63c4fe00d3120372e1922),
            Poseidon4Field.Type.wrap(0x397ccc5ef29caa6de873609650e9bea17ac048e52e4f8c86cbfdbbdc9f5eea9a),
            Poseidon4Field.Type.wrap(0x6431baeb99d486abd0c30bd23eedbb7aaf863dfe32cdc6ea6a29a62a49ec5fa2),
            Poseidon4Field.Type.wrap(0x09afe5011abd7c99753eec059463d6cd5c91dd494afe903b1ddbd0fa74cd1753),
            Poseidon4Field.Type.wrap(0x28f1cec0ec97fe7aa7d4642897e1c51ce50fe46b5f28650bc41e523b370033d5),
            Poseidon4Field.Type.wrap(0x0cb26f0ca4624dddbdf19003dae43f28d0e2b75e2df657d9acea9140d860e51a),
            Poseidon4Field.Type.wrap(0x373bf8d7205b2684fbf374dc8d8535d7f278815f7cfd857f6ee064e8c96c3454),
            Poseidon4Field.Type.wrap(0x42927ab0937f41bce0d6f843b523605c78e4d283bad74f846fbe8b8d7abf1ef5),
            Poseidon4Field.Type.wrap(0x5ee3c0e954d211a4bdd47823cfdb7bca087c95b7a4d250200a9754d316f59aff),
            Poseidon4Field.Type.wrap(0x678615cf67212c3a2993577659d4263655b9dd58708ccfa20afe9083b6ecb662),
            Poseidon4Field.Type.wrap(0x3c54727f944cca495d23c1777e7536c6321f871326092e6beb94d87444157ddc),
            Poseidon4Field.Type.wrap(0x53c65020af3f5abda95860ad9383f77f10d5a8e7dc1975b74346db78de0b49eb),
            Poseidon4Field.Type.wrap(0x5f5dd3df34ccc64f794d16acbc63bed0c4ce2cd38089e11dc95c9871c2a7ae31),
            Poseidon4Field.Type.wrap(0x09637e652e915ae0bc1d62b7da1c9d8b973bf8f23f4322bab6bcc7b4a4406a9f),
            Poseidon4Field.Type.wrap(0x546b9e395dee0a9466918ed255f76df4cd2c7c19681f2f712d4c16107b461351),
            Poseidon4Field.Type.wrap(0x18cb6e5d6d0959114085a657a62004d6d4bac25ae567ca63501cd280f915de1d),
            Poseidon4Field.Type.wrap(0x58782afd4a8a938bed95f04b985f4711efb2dacb8427fd6f8de78eb619ae9cad),
            Poseidon4Field.Type.wrap(0x072db66d8b16ae3aeb6d9e932e4de43e2e5cbfaaf34c7a0aa24dd9cf2a8e41b9),
            Poseidon4Field.Type.wrap(0x577832f774c67cddd7505cf603ca2e8fec342531bd0a1dbdde6d2e0728d565ec),
            Poseidon4Field.Type.wrap(0x08c6f1218fd35bfd0e6b5b50735a0c9a6d284f4051672f41c0fe39465f0a3af2),
            Poseidon4Field.Type.wrap(0x0eba8169994d61a6f1d3f5a7be72a0229f10693847f87734cd5305b77749240c),
            Poseidon4Field.Type.wrap(0x04851fb71ef33d8a5df10bf40b43519035055256714de067c7d845304d464145),
            Poseidon4Field.Type.wrap(0x2a5da7e9bf73c9479fa6e5f71288d31cefb6894921ac1e76d1e82be69ec4fed3),
            Poseidon4Field.Type.wrap(0x58a009a0ea2c67b5923aa87f30a79f448b66d6c21507d07354991eef394c7d1a),
            Poseidon4Field.Type.wrap(0x580d5aa604771bdf66ce0092f4c7174819c96b5e92499f48fe0199c4200060c0),
            Poseidon4Field.Type.wrap(0x72542655258cd87a0d0044f4e93d58584e6cf0009edb87f8175eb9c4e5778f85),
            Poseidon4Field.Type.wrap(0x22fc306957bf2306ac57ac3301b2d32dccdc860a7c0ceaddafd6727747e42034),
            Poseidon4Field.Type.wrap(0x47ea3e54e528ddc6e63b7ee7f14f80082b1df4719a68c4c9444a4aa640b21fa6),
            Poseidon4Field.Type.wrap(0x2e237e775ea78f7f7b0843e916f0837b99e5f2543628d0b9050be31e16fffaf0),
            Poseidon4Field.Type.wrap(0x254faafb9e2c37d7918e6a9f7b627db4f5317e83cd293ee6d62acc483806a7ca),
            Poseidon4Field.Type.wrap(0x20efada29ea259911ca23420027e98b8c5af2a2f202903c7149a7167d6b0ce6c),
            Poseidon4Field.Type.wrap(0x184a55e01875861e661289b3ad905293239eeae97ee5db99332b37e8f6c307e1),
            Poseidon4Field.Type.wrap(0x6acbe53e7aced8a5a614cf26a175397f136c25f2fb2e7b0a58caa97b1009f1ea),
            Poseidon4Field.Type.wrap(0x264991a53ef2e9918551c6b90ef7bb8339cd2f898e2322f44acff18b9b9a66d6),
            Poseidon4Field.Type.wrap(0x5078f86a7da7702a4cc8a3223da343beab035793b9434c39321da9d3691f999a),
            Poseidon4Field.Type.wrap(0x39a8104ab4e2622b9523a3a9f9ee3b41a8397ea953823e419e06269fb3d2c1eb),
            Poseidon4Field.Type.wrap(0x35728c2b81c712a34f3fe53c4393021ae73795035bcf1e631c0a99f44bf5639b),
            Poseidon4Field.Type.wrap(0x41d7615f8bd97f178282eac27dbdc3215b7a2606a86122827c44bad1e42c67e9),
            Poseidon4Field.Type.wrap(0x233bd5884457b5a4e1b4d1298f4695e172e6193afc096e78af06c474e85b13fa),
            Poseidon4Field.Type.wrap(0x2f967109b61b2b2eb441e9a7132308cf975724cdc241eb94655d5480b6a45cae),
            Poseidon4Field.Type.wrap(0x64f73e5667bde7037ddb61a224bfca795a61fbf0f78ea04019183161b0237c77),
            Poseidon4Field.Type.wrap(0x3829281d031f932f1ae9a2067bf6513dc51d5455b6dfa2955b16373596a7989b),
            Poseidon4Field.Type.wrap(0x52954070f8e0b8f4eb729b51e0c391101bcc120bb503d2578914d110355746d6),
            Poseidon4Field.Type.wrap(0x03b69267b12f495332d5c8a466cf1323221b891669924d118a44e89c0df8f1a4),
            Poseidon4Field.Type.wrap(0x1d33c92e7d3ee1749755786f52ec76c7bd7a9a4b772174702a35fad10d40b2e1),
            Poseidon4Field.Type.wrap(0x08d86c442959963e62deb44bd05d10e51e37c66c524c90b18fb3537ffc3fee70),
            Poseidon4Field.Type.wrap(0x24194a8ccf272dee642baf29a85cdb203bddf6da1348fa538abde1d28b1e170c),
            Poseidon4Field.Type.wrap(0x1c0b6f25101f49faa88022f8c83bac53ea9f160f62b6d19bbe321b5fede43ea9),
            Poseidon4Field.Type.wrap(0x5965df1635254bb73a2d95bdc456a1957c797f02a6351a3f7ff22e4b014bdb17),
            Poseidon4Field.Type.wrap(0x6fecddfd9ffaf803e45405fac3529a15a0093ac87afa05c50915bd154ef0cf6d),
            Poseidon4Field.Type.wrap(0x6c5a8175e24da73409ded2913dc27396cc1da85c947683186df43b33f92d55e2),
            Poseidon4Field.Type.wrap(0x40e211d645b6bdee48d4b4faa0f0b3180a6c6dc54ef620477c0384b0610fee60),
            Poseidon4Field.Type.wrap(0x42adc6f65f9df8036a34dd4fa987a26497a6526dda4b90f49de337c149748d70),
            Poseidon4Field.Type.wrap(0x73185cb8f8642b0eb4449590423d9e65bd29805945dacf6d59c8e8a0babd987f),
            Poseidon4Field.Type.wrap(0x1999004fd6cd12e05fabf2d5b9f0cfa062c0eb4a90413894e2d1b70e5b5d527e),
            Poseidon4Field.Type.wrap(0x4f89f26b5f08f1aab934b63ddc6a25942475ae3ed15b5c36c55ec579af3b0ecd),
            Poseidon4Field.Type.wrap(0x12a5fbf0400a087aba86a4226a836325339c3c95375a0cb09db74905ca5d968a),
            Poseidon4Field.Type.wrap(0x11a3fa42d518e20448aaeba3783c045f368a3d002723e10676a541a9e12a78ce),
            Poseidon4Field.Type.wrap(0x2f59f158b1c60bf12bbb4d956ff1dc9442aad7e876e2562d4438dfd2e2655ba0),
            Poseidon4Field.Type.wrap(0x48956231bc3a0c3581112417097659b50d06c16b511c535c2decc1a3bce340b3),
            Poseidon4Field.Type.wrap(0x2849b06e476443c43bd47dd906fccdf2728c537a7a5f0f6938e168bbd8149a0e),
            Poseidon4Field.Type.wrap(0x58d1184212a2fe71f72bb99b925e9c1432179bd4c8ff918daf4dfd7e7cee91ed),
            Poseidon4Field.Type.wrap(0x3fc33989242fa44cbd5172dc768de9a6c9d4a142d6fa7b99679735aea4e3cc61),
            Poseidon4Field.Type.wrap(0x04609e4a1be08e45a07d3cab7478c170a88cdbf32e124721cf6b8b1292be02c4),
            Poseidon4Field.Type.wrap(0x51a47f35ce630b8a01599a2f45d141496e6babe83c19f1e58f34cedae71a4819),
            Poseidon4Field.Type.wrap(0x011de2c7cafc96dc5d5919ae288780167e017d27067288f8c79bd2344700d97e),
            Poseidon4Field.Type.wrap(0x5505b08ca4fbe52ad9fe89d2a797f975bb9605b25b399741248aa4b29da00b66),
            Poseidon4Field.Type.wrap(0x0764417ff69a6cdf71ed5ca55be442dcf7b9c23364cedc4830ce28a8d31fe617),
            Poseidon4Field.Type.wrap(0x1ea443addd653c9a0eb5f9a7dfee8d543f3f4e413067c6bda7fe278f6f0a6994),
            Poseidon4Field.Type.wrap(0x30e8242b2eb26dde1277a06df6c4a335e18c3819df2e71cad28c1082a1c94dfc),
            Poseidon4Field.Type.wrap(0x4be93987573b6cfc6fd56c56cba5e12bb539818aa40f1fdc8c611d29f8048184),
            Poseidon4Field.Type.wrap(0x42b770b2264660e60e59d224e4a050d5d7f1f31a45690ff2577f28e3dbe29986),
            Poseidon4Field.Type.wrap(0x08a27e30763aad74f3d3f24b6e19d4a3bfabca120244698d3f4b7bb2ad4919a8),
            Poseidon4Field.Type.wrap(0x2cc5903961de4dcbbd0933b1961ce0f9e11eb86626dc332f1787954597b45627),
            Poseidon4Field.Type.wrap(0x47e985d487ee6e1e26bacd792ac5ba28d4509c9dd7c39ef7416951e9647a4dbc),
            Poseidon4Field.Type.wrap(0x2b93f9997e71be645215084ba7e08d2ff99b8f839f800caefe3a30661396ce61),
            Poseidon4Field.Type.wrap(0x712d0469727032af24d88a999b60638a9c04e2fad716a68868dd6d2f5c8bf1af),
            Poseidon4Field.Type.wrap(0x6bdaebef7927e6c195dc585eb0520a55d565a8c26107503341497c7a5098d7cd),
            Poseidon4Field.Type.wrap(0x66c00c9738eaa31d7b0b8a2fe0b1de81d8b42fc536383a40509079e97615197d),
            Poseidon4Field.Type.wrap(0x1fcfaf860b9f60eea753e8a2d79c344bf94384942cd898fd9a254acb40469c50),
            Poseidon4Field.Type.wrap(0x28b4dc5e4f2550e929ed53c414e2cfea1ca76b137f7ebec54533c4652105b938),
            Poseidon4Field.Type.wrap(0x472b0e17b62a901a4747be944d427c0e3a501de3403e4551c1cd29a04090e6aa),
            Poseidon4Field.Type.wrap(0x52f256eaa5ed5afc5b02bfd70dc7c70eaedbc3f89d72140b4374c36741c17f72),
            Poseidon4Field.Type.wrap(0x604a77f3a748eb226cf823c3ee35009d95a99eeae0d0b59513fef0356204b9b1),
            Poseidon4Field.Type.wrap(0x0b6e82f7e448979b1f794e2449f4cf865d12dd0515ce061ecc2de699ab8f9364),
            Poseidon4Field.Type.wrap(0x08ac469169f16f69d9953b3f0060e6356abcc7eaf46216a83146e6470d0f3407),
            Poseidon4Field.Type.wrap(0x593ae35f24590d6e1125e9a4e968e2a03424e6527173002e20f10da98739be87),
            Poseidon4Field.Type.wrap(0x1842a0080d610897631657769cfe98480828c5af6f8ab0454e1fc5181871abfb),
            Poseidon4Field.Type.wrap(0x1b4617ab22cbbeb10c39493e2dc4b465e17e795b82ebb9c986a18ea0c5f71312),
            Poseidon4Field.Type.wrap(0x12f49e7b20d1b518f36f2d3aea11fd8b60f19cf5b0a2416076f12a8b203f1854),
            Poseidon4Field.Type.wrap(0x2930f273fa05d398e9439d14b49ae806649b330696b98864d603dae3afb0ec37),
            Poseidon4Field.Type.wrap(0x0bd3c0be6e783e92b477cc3429c27de9c532f3269d540c49be9ea939d7a1a68b),
            Poseidon4Field.Type.wrap(0x58cca0bc2eaee337303a1035429216b5f5b23acdcafd5496e30b85806a64ed51),
            Poseidon4Field.Type.wrap(0x22f54df37e0c28d9ff08bfad67c572127f657256b93974992e90c362b84c142d),
            Poseidon4Field.Type.wrap(0x4f227e82309f2af0243a3840e8d3a457b328e00c00b6d58a76dd7ad245e792d7),
            Poseidon4Field.Type.wrap(0x4fa65b781e4c2ed965b74c201e8af52a835bc991db3ae610be9ece0778221fab),
            Poseidon4Field.Type.wrap(0x6168f0439fe970f7cc596c8a18bdf3e7285c9eb52e3372afa9084df3cbadcb2c),
            Poseidon4Field.Type.wrap(0x2ee0f0f1b7fae6d6ec9851629b8410c9b0d80ffa0e6bca06d6009c174b4cde76),
            Poseidon4Field.Type.wrap(0x463de84b0649f8fc6c262e00e6a950a656604a8ca21a527950f6eee511e7118a),
            Poseidon4Field.Type.wrap(0x5fb8be949ded20fddbca6db6105d2a0b64e527932a3924fad59a96a58b34bf8e),
            Poseidon4Field.Type.wrap(0x0c2e0aa86422baebfbd0e70123222cf86ab85010684f0d6d4b7fbf8e2b968001),
            Poseidon4Field.Type.wrap(0x5f8726f651ad2518b78c6fe100462dc0c13d8acf6e42651d682297cea73fc868),
            Poseidon4Field.Type.wrap(0x51c95bf666ff8fecf4e0b85bb58b834d2218d9f20170bf1be5d3c9aec43def38),
            Poseidon4Field.Type.wrap(0x3c4a879d04291aec2897628e731f3f63e04a8c7cd382a8c0fb014a62bbe8be61),
            Poseidon4Field.Type.wrap(0x4e3f2713561dd6e4b5071e0759eaa9545eab7b6335466e7c618d3988d1bad504),
            Poseidon4Field.Type.wrap(0x1158d86cddece49c18d48e32822fb977de5033e0e902c45601f8852193e4a604),
            Poseidon4Field.Type.wrap(0x02263730859a58ba2d3db60d5d7c7466824850b3207435e476ba35890a37fd2c),
            Poseidon4Field.Type.wrap(0x4d439b61a3703c36425888a3acf85639085b9a95429dcedd1b046c0a4a78acc5),
            Poseidon4Field.Type.wrap(0x1330cb0c5d2fa075aabb6bfb28276a9bbb44fb43306a63246aae25e1527868bd),
            Poseidon4Field.Type.wrap(0x16b95b643081cb043bdae50355f91df79c9b588c43e59038e6e6d0cc1698b5a5),
            Poseidon4Field.Type.wrap(0x1fb8d50108e2fb3ea1f80aa372da950a36eca4571240be90aa5b3fccfef3c321),
            Poseidon4Field.Type.wrap(0x4a53ec9735e16f6183934f1a7813d75cd11bbde409d8b262273bdfe5bc5dcc50),
            Poseidon4Field.Type.wrap(0x079ba56e1ca1d8c8eade23e8273e2db2a486901dbce8cd86caf41ae406fa21d5),
            Poseidon4Field.Type.wrap(0x38ed6aa3cc88a95fb845db9d5ef043ecacbfac58a8bb5cd9bce8e4d1e5967c68),
            Poseidon4Field.Type.wrap(0x2aae4dacc5a04fc32d1abd33601ee1c23c2986cc24dd63bf6d63be3a996fc5f4),
            Poseidon4Field.Type.wrap(0x4d34a394da7c0ecb24de0dff84192c35090ba8748d5690272f9948efd2d095b4),
            Poseidon4Field.Type.wrap(0x42b103442e734014097c5c63f509110dbc1872226e7db81b19c474c4c406aa18),
            Poseidon4Field.Type.wrap(0x48a2063c98229fdaa1768185d6a3f4dea3db1ce1de6b7b121794580993f5c78c),
            Poseidon4Field.Type.wrap(0x6ce4def3b2ebbdc1a4cf7f1a57d58467b1c48be6aa9c55c21696456dd58f03bb),
            Poseidon4Field.Type.wrap(0x195ce730b876d5929a76a7c5d69bf1911280dab5a69c2cd38ee4b61dadfc00e2),
            Poseidon4Field.Type.wrap(0x63bf1167c90f8dd2360d3e401c7fbed17da04b327ea2c94875739591bdc7d5dc),
            Poseidon4Field.Type.wrap(0x5db879cb0bbf165c80452e14073c8b96ab8fb608a22b43c3cf267419c0dbf3c8),
            Poseidon4Field.Type.wrap(0x472b50d6fb5d632e95ae0c5dd5f071ec8b6b4ee1407e5f3996a3b6e9c2a3d587),
            Poseidon4Field.Type.wrap(0x3cb873e98b29b2ed4d8066a06315d673bdff53c907b9adfbf52b37bd9799521c),
            Poseidon4Field.Type.wrap(0x0793192ee98e2f57a73911ddb781380b061b92218fb0d79416ff47ce679703c3),
            Poseidon4Field.Type.wrap(0x3c159af2d3c008156298b33d8cab5ec2e8cd70773d81414266812783cdabe19a),
            Poseidon4Field.Type.wrap(0x1c065141b64831c3ca0dcaf2d805bca7fa9473b9b163fa4c35fa3c83d2f933eb),
            Poseidon4Field.Type.wrap(0x23943e9e8a571aeb36c24eea0d3ee5f097aef800b3b8744189c74c6abe4f3407),
            Poseidon4Field.Type.wrap(0x3e9bf606619c174b6b417a2fd7bcf68269a082c5bd72fd8dd668bb3be7cbea16),
            Poseidon4Field.Type.wrap(0x480648a70c24e511be0e6d05d6d9a465877d3fd3428aa4b1a9e9e41de5c6b440),
            Poseidon4Field.Type.wrap(0x4324bdda4691820deb1481dbda3abb1cd5a05ccedf764b01317deabfd3e044f1),
            Poseidon4Field.Type.wrap(0x6f2915f09c70fb227bb6c0a4e7f134e85629d9a5b547de9a9cf74fb851384641),
            Poseidon4Field.Type.wrap(0x5f6d84cceaa1d3d3100a850dff27eb37f63db619532cf27291d5b35713ff215b),
            Poseidon4Field.Type.wrap(0x2fcbf6ae9d4cdb276ea017df3d2ebec767c2b7fe1bb8558e9a6e3322ae63a62b),
            Poseidon4Field.Type.wrap(0x408c45f73c4165b6cd00567331a72b4e26d79dfc305da5da9b8fd34311bcff9c),
            Poseidon4Field.Type.wrap(0x67799ccf850146c5f1ff10669a69189d943448ad0efea1c614133324e1505a5e),
            Poseidon4Field.Type.wrap(0x51ec52ac5329ecfed2a65bf7694212c04f47f4628de8c011d93afdad53ac9d4d),
            Poseidon4Field.Type.wrap(0x006e70e25eb8093bdcf955a5364a868b75d3729d057e78ad8358204ee3b1f8fb),
            Poseidon4Field.Type.wrap(0x50d01794d6f55e78fd516d212da55c3bb16f616032c3a8c284c60d61f877090f),
            Poseidon4Field.Type.wrap(0x1f74c3f88a37452f5fcd729af8fa1716e1d434d5a394e0457094f0563c31755b),
            Poseidon4Field.Type.wrap(0x019487e8c5dbb68aa598be6e60a580aa186baca856104373fce6ef6cd87fddce),
            Poseidon4Field.Type.wrap(0x4832ef55d38c938a015350f39b5b2185107dacce78ee4f85c47bbe5658e09ab8),
            Poseidon4Field.Type.wrap(0x4a85d06c39d9c8c00baa1c5dfb59ff29ba80099912a56e9e8add6884763cd068),
            Poseidon4Field.Type.wrap(0x41488ae48b74da505eb63124cc93220a6528420430bcc57338be26231ba3755b),
            Poseidon4Field.Type.wrap(0x21b5d82ddd050ecca07247349ae1aa49c63d1d52941fbab73e5060fe8595e30d),
            Poseidon4Field.Type.wrap(0x5c9b5273d97bbb50dc4cb6b754f15da0c9ff93a61d75f4395f02f0f4d173067a),
            Poseidon4Field.Type.wrap(0x0a062f37f718f4c37a8c2bf9ef2f7c4a2119ba043eb6ffed51e0b5c55b7a247c),
            Poseidon4Field.Type.wrap(0x159f9276bd128ed2d5b09f5fdaba71bf13806df7a17df30e6ed08086b8dace0e),
            Poseidon4Field.Type.wrap(0x397cf7ac45224459e819581c1f2ba6412dd078820337ecec0d6a883b83370198),
            Poseidon4Field.Type.wrap(0x32e654ddc435855db6a681a4134ce1a7f85525d0dde7a8e7365f36d6b8acb385),
            Poseidon4Field.Type.wrap(0x07245288af44bddd2f744d5e093ea7f100de626fa216bc3044516254939edd3e),
            Poseidon4Field.Type.wrap(0x61266cbaef88498a8255902e3a0efd2e45563158c8d47c75ec9af41d62fe128e),
            Poseidon4Field.Type.wrap(0x73157756a167275b89ecb982dc3d2fab484c7eee1d0800df9ea07712048c9d2d),
            Poseidon4Field.Type.wrap(0x0c0b409aaa3a87cf5c0504c624b23570dad7fc9ae30f1f056996bb6a7b2b5c53),
            Poseidon4Field.Type.wrap(0x03801ea9c955bbc5c32ff8d8d3174bcc2f4f3249b711090a4c963a784e06c554),
            Poseidon4Field.Type.wrap(0x17690270da56baeba4e614f7e8780b3b15201ac3d7ae406eb4dbe811f8b13956),
            Poseidon4Field.Type.wrap(0x0779f987f90f1c4f8e319418659d4bd33ac790e8eb07c153c28aa089775dcf38),
            Poseidon4Field.Type.wrap(0x2f74df84cb03f57ca5946f15f2fb134d42a3288f32a5d5ffb1a9fe1d2a391bfd),
            Poseidon4Field.Type.wrap(0x6ddaa41db23ce0405078e68938a27c0386674531648061bbd79359c91f32aac2),
            Poseidon4Field.Type.wrap(0x2f49ab87e23a5d392c5e457337342795f3066a07f987de091f325ac32b8ba72c),
            Poseidon4Field.Type.wrap(0x0efc38d20700d5b5a3b055be496dbdf82b0ab3e07dda2a0df3b16c07b02dabb4),
            Poseidon4Field.Type.wrap(0x6f5ab923c9d18fd41b977c0f544cb9af853dddd00734b01f9280145a1dc7cfc9),
            Poseidon4Field.Type.wrap(0x0903ed0675157f6629cff37a2055f827bdbea9801a09fa7ee01c66b108265b8b),
            Poseidon4Field.Type.wrap(0x700f5c0c5990d42434a15bc34c228500c52f0441de8419783a1509045d2aaf8b),
            Poseidon4Field.Type.wrap(0x6a0e3381e15190acf36abed91ee25dc7fde5c90a3c5154a4329b2662188c2cb8),
            Poseidon4Field.Type.wrap(0x4757ddbab350afd9c61e7a748d936388aa9ff3709c64a080ab9f28646d1d7181),
            Poseidon4Field.Type.wrap(0x60f9d0c0c463bffe9c08d557dfd5d1054a98f32c04eaa80c49290cd45897b2a7),
            Poseidon4Field.Type.wrap(0x0720379ef288498c5e6100d19258c915b32fd1f76a7878fd3575137b695e5789),
            Poseidon4Field.Type.wrap(0x2265c46e022a5ef8ff8e9293803aff7f15ce0814a9edee3b1d546c7865407e3c),
            Poseidon4Field.Type.wrap(0x1206dc6f2948499c0a2d173e0ce4850870a8b1957d362ce6aad3603084cfb48a),
            Poseidon4Field.Type.wrap(0x3497b1b2410e8b30f6c09dd43d54aa9755c4bdaa743f8af7df57486dc70786c2),
            Poseidon4Field.Type.wrap(0x1ac1322d723d7d2c9e8a475140bc3991e124c7752dbe38d83ee03985cab3ec06),
            Poseidon4Field.Type.wrap(0x06d7e810be67618152bb71fe9246ed8390e61d21fdaf4d357d67bb5de77df230),
            Poseidon4Field.Type.wrap(0x0ee137d56d3c1f10af868ae52affaa93f1900ef4b93656322c7f295f3949436f),
            Poseidon4Field.Type.wrap(0x21da6fd7aaca1d900c16ab0292cbda61f3c784d2ab0efe4fb1b87d443b54a76a),
            Poseidon4Field.Type.wrap(0x1db1c07b4c58b4bada79593314f41f0050a88831ff9f9073fb31114e0e67285d),
            Poseidon4Field.Type.wrap(0x5898c5429b336972114192ac64c5226082c3b2fee5a63a862fddba0789d6a473),
            Poseidon4Field.Type.wrap(0x6ce149f5c89369cbae1a7da096eb5b0ffdb885dc1916c9884dbbae22e6db34e8),
            Poseidon4Field.Type.wrap(0x312b1c75d7428aa4ddecc9229f9bfccfd4be6ef3ba7b16e04c6021255d1de0d5),
            Poseidon4Field.Type.wrap(0x08ac2c7ded2c05ddb49ae7ac6102c229dde9275c3589a88b40069c8c3cf236ee),
            Poseidon4Field.Type.wrap(0x1725748fd880aabb1d6453669335fba232e6b2d25e69f3d56a504a3e5b05d76e),
            Poseidon4Field.Type.wrap(0x248998a735f44fc524d9a3854e5d49e3dd1487e334ab8609558b89a5db585558),
            Poseidon4Field.Type.wrap(0x51327888436d6fa1820a24f5106403e6f3cf35a5b2ef9148ff6aa6eceef4656e),
            Poseidon4Field.Type.wrap(0x0c8b5a14aa194279b5d7676414246a40756786c8718d30a87d643d9320c4ec43),
            Poseidon4Field.Type.wrap(0x4dc96baa6c646df7036040dde9349b3f2ee384cafad6de954f4cd861069b2481),
            Poseidon4Field.Type.wrap(0x718209ea4f77c3f76ecb439d05adf0b70294bad752b6c7f9af5711ce87be65a1),
            Poseidon4Field.Type.wrap(0x639a0d20110526eaa343c723af04d126cd523ec21cf43d38b35398a0c56265b0),
            Poseidon4Field.Type.wrap(0x2532f06a0066838b5c4cb4ddbd2e619bd7a9a4e37d4def67d20cd24cb8e67206),
            Poseidon4Field.Type.wrap(0x6b6d6b0887e56bebac8bd69265d4ce6a00ba7470d0168d65a2d25523900917c0),
            Poseidon4Field.Type.wrap(0x49f013fd9c831d3bbb0a371937ccfc302a424cc46d4ec08b5f45ac52ac31e8cd),
            Poseidon4Field.Type.wrap(0x394e2a96c15cfa8f3ffcf5cb63264101b5c86f3fe92be4f842eb456d57295fe8),
            Poseidon4Field.Type.wrap(0x1ac743d177683ccc6719998182d6b7f431f1251f47a8446dc256830a359a789f),
            Poseidon4Field.Type.wrap(0x3e3e342fba7c149018bcd2cc36ccff80a7eb3284f044cb5dbb9fb325f3b4b9f4),
            Poseidon4Field.Type.wrap(0x3acc235e3731adafb4e9d9ef258e17f27329ac022a49b127205de91ea9322c8a),
            Poseidon4Field.Type.wrap(0x608afd9af0e5cfe07f12bf3316628eb8b9942121bfbd43ff7fe22a479aaad604),
            Poseidon4Field.Type.wrap(0x0ff89b10a1c9e65ef3a74ed5f7ac9892ac86faefc74731fd2b600834b186aac4),
            Poseidon4Field.Type.wrap(0x52f4e44f6d3341b5bf59399c6d53490fa8908e38e24a6142b90e5cbabae26292),
            Poseidon4Field.Type.wrap(0x38ee391b76fd73893fb64102547ca12c03cae780df15bf46727e57d07720575e),
            Poseidon4Field.Type.wrap(0x3aea1da1370f5f1a3e7bec277a3cb39f286f3f00e82b701a359c041bcf6d9b80),
            Poseidon4Field.Type.wrap(0x21527c01d8037ea85f26001543e0caaa27114f3d00a155fcd4038a1fef06f0d9),
            Poseidon4Field.Type.wrap(0x60fc95ccdb1cf5a2700a6d66c7178bab18c5aaafd1d84329ef0521f72a45ca71),
            Poseidon4Field.Type.wrap(0x5ab6a484d0d3ecfd4bf7d02da51f2d335fbc16bcc6d24beb6c2cd1730ed46c1a),
            Poseidon4Field.Type.wrap(0x4ea32259f9226d6e3d829d55ef0dfad8e8c7b83293358e0b9f899b54ad0bb82b),
            Poseidon4Field.Type.wrap(0x05b6e5b66f488a0378388224ad8c50eb6764df75505e02e713c95dfeb07da075),
            Poseidon4Field.Type.wrap(0x31712374e5e6154ad9e2c9d26e6b2b804755971130c2d1b9bacc151872e69e19),
            Poseidon4Field.Type.wrap(0x1e579ccdcfed1c91d2fbf8b171f7c5352a986493bf227e5a9b1b8128a512646c),
            Poseidon4Field.Type.wrap(0x2a2acebc6ea9b7b1170331b1f5fa73176ac647a25f590752552d88120ad535d0),
            Poseidon4Field.Type.wrap(0x49153077b745ebc3292e66fce38393f30524d2d3514b284aed7475e849d74e32),
            Poseidon4Field.Type.wrap(0x5375d9a81513c847f8c5f072049c59011dcacc7a8ded4dfb0ce8d89e3a997f14),
            Poseidon4Field.Type.wrap(0x435d971e1eb8e44821c6c1ba05116256fa79c35db080a09ef7e24f59f420dd45),
            Poseidon4Field.Type.wrap(0x58503b3a94f096941dad28f1caf856e5ce8f43a87505bc82ec4eab08149fd5d9),
            Poseidon4Field.Type.wrap(0x3875898530fddee93f088fff6afe6998548c24552e1ce79bfd6989a34f91dba1),
            Poseidon4Field.Type.wrap(0x19380c553178569b69ba13e029af8a40e2753db62df5a0a70c13b6105f1e3daf),
            Poseidon4Field.Type.wrap(0x1c00372679acb24658db79cde4b98711447ea35fe771de55c9addc7ccbcfcbfd),
            Poseidon4Field.Type.wrap(0x6b5dbfea22d86bd8bbfdb5d787f2d58830ae60032ff2e4639e1508c8fc6b5d80),
            Poseidon4Field.Type.wrap(0x4607d1076850ad704386a117a214e6e7cd0fe5ffa9d88eb0d26b3e803201e641),
            Poseidon4Field.Type.wrap(0x0f91e67891be0164227f53bbb878dcf24262bd48a3003e35adc2a55de5a47db6),
            Poseidon4Field.Type.wrap(0x45996205840c4b3d5c410afd195a0646c8300255f65f994e608dc7889d9f2e5b),
            Poseidon4Field.Type.wrap(0x3ead3e9e499d91be44dfb36a1ec2d0e606a736e0ab546d4454e12835352fc115),
            Poseidon4Field.Type.wrap(0x1598c26031f70feec9e034f64b1d9a36a695d767a26bfa59cee0cb445eb4b307),
            Poseidon4Field.Type.wrap(0x1cc0c0f8eaffe3789e3b439093440f1a60b921721763d41055c78922b871b03a),
            Poseidon4Field.Type.wrap(0x48703d4aa9bf7adc5e911c7817d88968569bc88162ad297ed48fb42893150047),
            Poseidon4Field.Type.wrap(0x5593e8d4c35eb09c60c8b0f998419159d552513affaa6ab9c34a07c3a577fc78),
            Poseidon4Field.Type.wrap(0x1d0edcbd6dcddf3ae0a64a0cd44eb759f2330f172cd4ed007a041ac18c5de850),
            Poseidon4Field.Type.wrap(0x328371fd8f5642affaa80772e382ba086b4aeae25cf32cb1fd6a03f4c17434e3),
            Poseidon4Field.Type.wrap(0x37941017b7862dedd6d93c13b7f08bb932defcd29c70d1b1d5724ca40c29cc72),
            Poseidon4Field.Type.wrap(0x10c59d50cb8d8d939b2b97163b5ce65d63d4b0a58522ff95addfc01620ef0100),
            Poseidon4Field.Type.wrap(0x0d5b533b43b0b27d9b64551c7ceaee9fb0b6b9061d13326147360615dda11212),
            Poseidon4Field.Type.wrap(0x636375e8e3a62551030f9dbe7811775d90b697a1619360756afec469adc3f468),
            Poseidon4Field.Type.wrap(0x16ff3d1de7193f4b98611664a8b64cbc4fe39ddbd74337d8e347e4bca730cd94),
            Poseidon4Field.Type.wrap(0x1cc95775b2716b3cdd35e56a7c7b2497564f9f44f202e18baf52d064877a4eab),
            Poseidon4Field.Type.wrap(0x36daf37534506831829b7229f6b34c5020846e98e02eef2db84136c910ba1594),
            Poseidon4Field.Type.wrap(0x61a68e2455dce0f6783ef9e5131db78a998c62b695a83078485b414f5f605e5a),
            Poseidon4Field.Type.wrap(0x12b11dd703fc60f2ede9f64b5050371c32fe393d86a3341996fc4210069d2a22),
            Poseidon4Field.Type.wrap(0x27bf254291de0508e8b83ca24a6f9412b5eb98ea795b87bb1040e411c2a823c9),
            Poseidon4Field.Type.wrap(0x35f4aa5fe745e6e65654e48e4b395290b2e872dde27245f08910ef4e0ff34b2a),
            Poseidon4Field.Type.wrap(0x24fdbbb549e57cbccc5914748a55d3f64778f957b6024162b89b3a3de13b1911),
            Poseidon4Field.Type.wrap(0x22485592115c7396684ea68c47390d13e784c29e5c2f1d15997bbad58557a29f),
            Poseidon4Field.Type.wrap(0x2056b61a624a856030a66e540f7a878f418adf12317d378869140919a33d02f6),
            Poseidon4Field.Type.wrap(0x38df7ffa7f9be7b2e80f05da1af774693bb3f59d13c3570b242096fccc6b1601),
            Poseidon4Field.Type.wrap(0x35b15b6c4c7bf09e1d9eebea32d2c9abe4fd1abd978480c637aa42b430e35637),
            Poseidon4Field.Type.wrap(0x255267e1ead997f166dcf53f0d0cd7e69a8199a11950ceb2515f8f8667d06763),
            Poseidon4Field.Type.wrap(0x3fd6bd225026a4673ee244b3ba4e49f9ff5dddea1238c4db69e1bf5d88a85020)
        ];

        // MDS matrix from the off-chain implementation
        constants.mds_matrix = [
            [
                Poseidon4Field.Type.wrap(0x5edc4de43ff07c60ace8f91ac726180f38604b5bb2f2ab2c27aa2a4d53cf7081),
                Poseidon4Field.Type.wrap(0x21c0f632624d48a11931e2bcb8695897e5cb1d7cec432d115df1b25ea0d9d4a3),
                Poseidon4Field.Type.wrap(0x4243ff5f4a234a2256286afa4ec59b4c9c32439c0869f1aa0b92a5ab82ee1b38),
                Poseidon4Field.Type.wrap(0x7344ba891ca71591e07e7e6aa563931b9d07b548c816668af7f6170e5c8cd073),
                Poseidon4Field.Type.wrap(0x20c42fc15a32ed98b81609d1e9de98f255e4b46414af1dad036bfe255d3d2f19)
            ],
            [
                Poseidon4Field.Type.wrap(0x68186626fb0239ce09c22fe4ec756ab3dede54596e3cc426ac7ec1f5c38881f2),
                Poseidon4Field.Type.wrap(0x1cdfe1f1de4a7290ab39316b544da5e6576d4d1c05eaf0719c3c60867fab0372),
                Poseidon4Field.Type.wrap(0x1992e57fe5537033e0b3711c4aba9a6630fdf87a5962a442e926718e92f7e573),
                Poseidon4Field.Type.wrap(0x5033856a6fe61acbb5a95e6f8e1d6e5aca6e1d2125d0c03d864e8fecdb3ccd4a),
                Poseidon4Field.Type.wrap(0x09e7c08b5c3289751cf3e30a7ab45c59aaca49585c3f08fb39a67bc9466cceb2)
            ],
            [
                Poseidon4Field.Type.wrap(0x73ac6ff5f192940a6a3198b94a158121172678891e35c8895c6a20f4164f7c93),
                Poseidon4Field.Type.wrap(0x03ac6b5eccedc5da43ff372db13fa55ac197bb9592e15d4feb74ee152e90e952),
                Poseidon4Field.Type.wrap(0x1574427d32abdcde8a24db9e42219c68f84d89f342f0eb455309c7937054f842),
                Poseidon4Field.Type.wrap(0x21fcae8d9f8f62a956217b8fd134560fc2654527ee9e5359beefb95b2c59288d),
                Poseidon4Field.Type.wrap(0x06ca0c88a61632956a1d3e91999c842f03b6e7f121df734ce75682fbfa1ef7f9)
            ],
            [
                Poseidon4Field.Type.wrap(0x4ce4f0699adf8172f73b8cd2407d7db698a2625bf837b95a35abbf4eddcbd7dd),
                Poseidon4Field.Type.wrap(0x1a0f8b3e444c78fcc67ce285e743094a787745b2761df2203979fc08d3ab3a99),
                Poseidon4Field.Type.wrap(0x40a3f19fa4064fd9c119dd0acaea02ea3ae33a5df8b181867ff6b705f159e4af),
                Poseidon4Field.Type.wrap(0x051d14de8bbf745f9f8a20682c4104c48a0198e8f604ae06b45de4051d90065c),
                Poseidon4Field.Type.wrap(0x294ce128d90968ca910a8cc18c9ab58d41a0a91df79bed878952aa88f7433a80)
            ],
            [
                Poseidon4Field.Type.wrap(0x637e4ac13df1eefbc7ee982d5a044b89a20d383b17fa5a23bfe25a7915d8885f),
                Poseidon4Field.Type.wrap(0x35151e81622f69dec5eedf76619630dc42997eeaf162fdda7644ce726da53c3b),
                Poseidon4Field.Type.wrap(0x707fbbeb0bf2b5aa6ed7573b46506eff64c69ce781aa7fa616e3d53390922a1e),
                Poseidon4Field.Type.wrap(0x5e876f8493c339c36750caa31382bea4a90d6928976a3f996a30a3f1af778f63),
                Poseidon4Field.Type.wrap(0x121909e9d5554a3b3d207272ad07359bb49136e23fe6f0d1c62c3bf940ca5bcd)
            ]
        ];
    }
}