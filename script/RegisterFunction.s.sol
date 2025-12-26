// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {BridgeAdminManager} from "../src/BridgeAdminManager.sol";

contract RegisterFunctionScript is Script {
    function run() external {
        vm.startBroadcast();

        address adminManagerAddress = 0x374c2a109C59c60E18af161F263689520eBd6932;
        BridgeAdminManager adminManager = BridgeAdminManager(adminManagerAddress);

        address targetContract = 0xa30fe40285B8f5c0457DbC3B7C8A280373c40044;
        bytes32 functionSignature = 0xa9059cbb00000000000000000000000000000000000000000000000000000000;
        bytes32 instanceHash = 0xd157cb883adb9cb0e27d9dc419e2a4be817d856281b994583b5bae64be94d35a;

        uint128[] memory preprocessPart1 = new uint128[](4);
        preprocessPart1[0] = 0x11b01d3b7756a1e2c84462f2a011f8cf;
        preprocessPart1[1] = 0x110f0dbdfee1e30c55061363fd147c5f;
        preprocessPart1[2] = 0x02e86220169ffc66feac2bca980de255;
        preprocessPart1[3] = 0x12d32a9d10236151ea94eddd2de15df4;

        uint256[] memory preprocessPart2 = new uint256[](4);
        preprocessPart2[0] = 0xe2285fde54386faf68544ac49ac3f620c84265d1e76dffbbb780329a35c798f2;
        preprocessPart2[1] = 0x85767f719652f5fcde0bc847a1af46c16c3ffab6bded47addd0f8215588f1684;
        preprocessPart2[2] = 0xd775a85c51e4d33eaccca66cd04346c2d291b2c777daa08b093d91a9475e1623;
        preprocessPart2[3] = 0x3e984d129c3dab74f9d13ab9ab66d5d826fca5e1f6270242aaa5dedeedf2fe58;

        adminManager.unregisterFunction(targetContract, functionSignature);
        
        adminManager.registerFunction(
            targetContract,
            functionSignature,
            preprocessPart1,
            preprocessPart2,
            instanceHash
        );

        vm.stopBroadcast();
    }
}