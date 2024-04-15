// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Script, console2 } from "forge-std/Script.sol";
import { SwapFactory } from "@tenderize/swap/Factory.sol";
import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

address constant FACTORY = address(0);

uint256 constant VERSION = 2;

contract Factory_Deploy is Script {
    // Contracts are deployed deterministically.
    // e.g. `foo = new Foo{salt: salt}(constructorArgs)`
    // The presence of the salt argument tells forge to use https://github.com/Arachnid/deterministic-deployment-proxy
    bytes32 constant SALT = bytes32(VERSION);

    // Start broadcasting with private key from `.env` file
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

    address fac = 0xBF0e7CE92bb073b2EC5940D7Fae52D3EA4Db70f6;

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        // address fac = address(new SwapFactory{ salt: SALT }());
        address proxy = address(new ERC1967Proxy{ salt: SALT }(fac, ""));
        SwapFactory(proxy).initialize();

        console2.log("SwapFactory deployed at: ", proxy);
        console2.log("Implementation deployed at: ", fac);
        vm.stopBroadcast();
    }
}
