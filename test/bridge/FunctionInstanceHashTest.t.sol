// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";

// Simple contract that replicates the _extractFunctionInstanceHashFromProof logic
contract HashTester {
    function extractFunctionInstanceHashFromProof(uint256[] calldata publicInputs) 
        external 
        pure 
        returns (bytes32) 
    {
        // Function instance data starts at index 66 (based on instance_description.json)
        // User data: 0-41, Block data: 42-65, Function data: 66+
        require(publicInputs.length > 66, "Public inputs too short for function instance data");
        
        // Extract function instance data starting from index 66
        uint256 functionDataLength = publicInputs.length - 66;
        uint256[] memory functionInstanceData = new uint256[](functionDataLength);
        
        for (uint256 i = 0; i < functionDataLength; i++) {
            functionInstanceData[i] = publicInputs[66 + i];
        }
        
        return keccak256(abi.encodePacked(functionInstanceData));
    }
}

contract FunctionInstanceHashTest is Test {
    HashTester public hashTester;
    
    // Expected hash computed by our JavaScript script using proper keccak256
    bytes32 constant EXPECTED_HASH = 0x01da72b21088e36f4c987d7796856fa1351ea79d94a9c6bfbcc4c36813f9e1af;
    
    function setUp() public {
        hashTester = new HashTester();
    }
    
    function test_extractFunctionInstanceHashFromProof() public {
        // Load the public inputs from the JSON file
        // This data is from test/verifier/proof1/a_pub_function.json
        uint256[] memory publicInputs = _loadPublicInputsFromJSON();
        
        // Call the function under test
        bytes32 computedHash = hashTester.extractFunctionInstanceHashFromProof(publicInputs);
        
        // Verify it matches our expected hash from the JavaScript script
        assertEq(computedHash, EXPECTED_HASH, "Function instance hash mismatch");
        
        console.log("Expected hash: %s", vm.toString(EXPECTED_HASH));
        console.log("Computed hash: %s", vm.toString(computedHash));
        console.log("Hash verification: PASSED");
    }
    
    function test_extractFunctionInstanceHashFromProof_TooShort() public {
        // Test with insufficient public inputs (should revert)
        uint256[] memory shortInputs = new uint256[](65); // Less than 66 required
        
        vm.expectRevert("Public inputs too short for function instance data");
        hashTester.extractFunctionInstanceHashFromProof(shortInputs);
    }
    
    function test_extractFunctionInstanceHashFromProof_EmptyFunctionData() public {
        // Test with exactly 66 elements (no function data)
        uint256[] memory exactInputs = new uint256[](66);
        
        vm.expectRevert("Public inputs too short for function instance data");
        hashTester.extractFunctionInstanceHashFromProof(exactInputs);
    }
    
    function test_extractFunctionInstanceHashFromProof_SingleFunctionElement() public {
        // Test with exactly 67 elements (one function data element)
        uint256[] memory inputs = new uint256[](67);
        for (uint256 i = 0; i < 66; i++) {
            inputs[i] = 0; // Fill user and block data with zeros
        }
        inputs[66] = 0x12345678; // Single function data element
        
        // Calculate expected hash for single element
        bytes32 expected = keccak256(abi.encodePacked(uint256(0x12345678)));
        
        bytes32 computed = hashTester.extractFunctionInstanceHashFromProof(inputs);
        assertEq(computed, expected, "Single element hash mismatch");
    }
    
    // Helper function to load public inputs from the JSON data
    // This manually creates the array from test/verifier/proof1/a_pub_function.json
    function _loadPublicInputsFromJSON() internal pure returns (uint256[] memory) {
        uint256[] memory inputs = new uint256[](448); // Total length from JSON
        
        // Manually populate the array with values from the JSON file
        // User data (0-41) and Block data (42-65)
        inputs[0] = 0x01;
        inputs[1] = 0xffffffffffffffffffffffffffffffff;
        inputs[2] = 0xffffffff;
        inputs[3] = 0xe72f6afd7d1f72623e6b071492d1122b;
        inputs[4] = 0x11dafe5d23e1218086a365b99fbf3d3b;
        inputs[5] = 0x3e26ba5cc220fed7cc3f870e59d292aa;
        inputs[6] = 0x1d523cf1ddab1a1793132e78c866c0c3;
        inputs[7] = 0x00;
        inputs[8] = 0x00;
        inputs[9] = 0x01;
        inputs[10] = 0x00;
        inputs[11] = 0x80;
        inputs[12] = 0x00;
        inputs[13] = 0x00;
        inputs[14] = 0x00;
        inputs[15] = 0x200000;
        inputs[16] = 0x04;
        inputs[17] = 0x00;
        inputs[18] = 0xa30fe402; // Function signature from instance.json
        inputs[19] = 0x00;
        inputs[20] = 0x010000;
        inputs[21] = 0xe0;
        inputs[22] = 0x00;
        inputs[23] = 0x08000000;
        inputs[24] = 0x20;
        inputs[25] = 0x00;
        inputs[26] = 0x10000000;
        inputs[27] = 0xe0;
        inputs[28] = 0x00;
        inputs[29] = 0x10000000;
        inputs[30] = 0x70a08231;
        inputs[31] = 0x00;
        inputs[32] = 0x020000;
        inputs[33] = 0x98650275;
        inputs[34] = 0x00;
        inputs[35] = 0x020000;
        inputs[36] = 0xaa271e1a;
        inputs[37] = 0x00;
        inputs[38] = 0x020000;
        inputs[39] = 0x98650275;
        inputs[40] = 0x00;
        inputs[41] = 0x100000;
        inputs[42] = 0xa457c2d7;
        inputs[43] = 0x00;
        inputs[44] = 0x100000;
        inputs[45] = 0xa9059cbb;
        inputs[46] = 0x00;
        inputs[47] = 0x100000;
        inputs[48] = 0x04;
        inputs[49] = 0x00;
        inputs[50] = 0x44;
        inputs[51] = 0x00;
        inputs[52] = 0x08;
        inputs[53] = 0x40;
        inputs[54] = 0x00;
        inputs[55] = 0x010000;
        inputs[56] = 0x200000;
        inputs[57] = 0x02;
        inputs[58] = 0xffffffffffffffffffffffffffffffff;
        inputs[59] = 0xffffffff;
        inputs[60] = 0x20;
        inputs[61] = 0x00;
        inputs[62] = 0x02;
        inputs[63] = 0x20;
        inputs[64] = 0x00;
        inputs[65] = 0x02;
        
        // Function data starts at index 66 (from the JSON file)
        // First 10 function data elements for reference:
        inputs[66] = 0x00;
        inputs[67] = 0x00;
        inputs[68] = 0xffffffffffffffffffffffffffffffff;
        inputs[69] = 0xffffffff;
        inputs[70] = 0xffffffffffffffffffffffffffffffff;
        inputs[71] = 0xffffffff;
        inputs[72] = 0x100000;
        inputs[73] = 0x200000;
        inputs[74] = 0x00;
        inputs[75] = 0x00;
        
        // Continue with the remaining function data (indexes 76-447)
        // Most are 0x00, with some specific values scattered throughout
        inputs[76] = 0xffffffffffffffffffffffffffffffff;
        inputs[77] = 0xffffffff;
        inputs[78] = 0xffffffffffffffffffffffffffffffff;
        inputs[79] = 0xffffffff;
        inputs[80] = 0x100000;
        inputs[81] = 0x200000;
        inputs[82] = 0x60;
        inputs[83] = 0x00;
        inputs[84] = 0x02;
        inputs[85] = 0x20;
        inputs[86] = 0x00;
        inputs[87] = 0x02;
        inputs[88] = 0x00;
        inputs[89] = 0x00;
        inputs[90] = 0xffffffffffffffffffffffffffffffff;
        inputs[91] = 0xffffffff;
        inputs[92] = 0xffffffffffffffffffffffffffffffff;
        inputs[93] = 0xffffffff;
        inputs[94] = 0x20;
        inputs[95] = 0x00;
        inputs[96] = 0x02;
        inputs[97] = 0x20;
        inputs[98] = 0x00;
        inputs[99] = 0x02;
        inputs[100] = 0x1da9;
        inputs[101] = 0x00;
        inputs[102] = 0xffffffff;
        inputs[103] = 0x00;
        inputs[104] = 0x020000;
        inputs[105] = 0x200000;
        inputs[106] = 0x08;
        inputs[107] = 0x00;
        inputs[108] = 0x00;
        inputs[109] = 0xffffffffffffffffffffffffffffffff;
        inputs[110] = 0xffffffff;
        inputs[111] = 0xffffffffffffffffffffffffffffffff;
        inputs[112] = 0xffffffff;
        inputs[113] = 0x20;
        inputs[114] = 0x00;
        inputs[115] = 0x02;
        inputs[116] = 0x20;
        inputs[117] = 0x00;
        inputs[118] = 0x02;
        inputs[119] = 0x00;
        inputs[120] = 0x00;
        inputs[121] = 0xffffffffffffffffffffffffffffffff;
        inputs[122] = 0xffffffff;
        inputs[123] = 0xffffffffffffffffffffffffffffffff;
        inputs[124] = 0xffffffff;
        inputs[125] = 0x20;
        inputs[126] = 0x00;
        inputs[127] = 0x02;
        inputs[128] = 0x20;
        inputs[129] = 0x00;
        inputs[130] = 0x02;
        inputs[131] = 0x1acc;
        inputs[132] = 0x00;
        inputs[133] = 0xffffffff;
        inputs[134] = 0x00;
        inputs[135] = 0x02;
        inputs[136] = 0x010000;
        inputs[137] = 0x200000;
        inputs[138] = 0x00;
        inputs[139] = 0x00;
        inputs[140] = 0xffffffffffffffffffffffffffffffff;
        inputs[141] = 0xffffffff;
        inputs[142] = 0xffffffffffffffffffffffffffffffff;
        inputs[143] = 0xffffffff;
        inputs[144] = 0x20;
        inputs[145] = 0x00;
        inputs[146] = 0x02;
        inputs[147] = 0x20;
        inputs[148] = 0x00;
        inputs[149] = 0x02;
        inputs[150] = 0xffffffffffffffffffffffffffffffff;
        inputs[151] = 0xffffffff;
        inputs[152] = 0xffffffffffffffffffffffffffffffff;
        inputs[153] = 0xffffffff;
        inputs[154] = 0x20;
        inputs[155] = 0x00;
        inputs[156] = 0x02;
        inputs[157] = 0x08;
        inputs[158] = 0x15;
        inputs[159] = 0x00;
        inputs[160] = 0x0100;
        inputs[161] = 0x00;
        inputs[162] = 0x01;
        inputs[163] = 0x00;
        inputs[164] = 0x10;
        inputs[165] = 0xff;
        inputs[166] = 0x00;
        inputs[167] = 0x200000;
        inputs[168] = 0x200000;
        inputs[169] = 0x01;
        inputs[170] = 0x00;
        inputs[171] = 0x200000;
        inputs[172] = 0x200000;
        inputs[173] = 0x200000;
        inputs[174] = 0x200000;
        inputs[175] = 0x20;
        inputs[176] = 0x00;
        inputs[177] = 0x02;
        inputs[178] = 0x08;
        
        // The remaining entries (179-447) are all 0x00
        for (uint256 i = 179; i < 448; i++) {
            inputs[i] = 0x00;
        }
        
        return inputs;
    }
    
    function test_extractFunctionSignature() public view {
        // Test function signature extraction from actual data
        uint256[] memory publicInputs = _loadPublicInputsFromJSON();
        
        // From instance.json, at index 18 we have "0xa30fe402"
        // This should be extracted as the function signature
        bytes32 expectedSig = 0xa30fe40200000000000000000000000000000000000000000000000000000000;
        
        // Note: We can't directly test the internal function from BridgeProofManager,
        // but we can verify the expected value matches what we see in the JSON
        uint256 actualValue = publicInputs[18];
        bytes4 selector = bytes4(uint32(actualValue));
        bytes32 extractedSig = bytes32(selector);
        
        assertEq(extractedSig, expectedSig, "Function signature extraction mismatch");
        console.log("Function signature at index 18: %s", vm.toString(extractedSig));
    }
}