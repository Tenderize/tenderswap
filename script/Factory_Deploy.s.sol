// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Script, console2 } from "forge-std/Script.sol";
import { SwapFactory } from "@tenderize/swap/Factory.sol";
import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

address constant FACTORY = address(0);

contract Swap_Deploy is Script {
    // Contracts are deployed deterministically.
    // e.g. `foo = new Foo{salt: salt}(constructorArgs)`
    // The presence of the salt argument tells forge to use https://github.com/Arachnid/deterministic-deployment-proxy
    bytes32 private constant salt = 0x0;

    // Start broadcasting with private key from `.env` file
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        address fac = address(new SwapFactory());
        address proxy = address(new ERC1967Proxy(fac, abi.encodeWithSelector(SwapFactory.initialize.selector)));
        console2.log("SwapFactory deployed at: ", proxy);
        console2.log("Implementation deployed at: ", fac);
        vm.stopBroadcast();
    }
}
