// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Script, console2 } from "forge-std/Script.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { TenderSwap, ConstructorConfig } from "@tenderize/swap/Swap.sol";
import { SwapFactory } from "@tenderize/swap/Factory.sol";
import { UD60x18 } from "@prb/math/UD60x18.sol";
import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

address constant FACTORY = address(0);

contract Swap_Deploy is Script {
    // Contracts are deployed deterministically.
    // e.g. `foo = new Foo{salt: salt}(constructorArgs)`
    // The presence of the salt argument tells forge to use https://github.com/Arachnid/deterministic-deployment-proxy
    bytes32 private constant salt = 0x0;

    // Start broadcasting with private key from `.env` file
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address underlying = vm.envAddress("UNDERLYING");
    UD60x18 BASE_FEE = UD60x18.wrap(vm.envUint("BASE_FEE"));
    UD60x18 K = UD60x18.wrap(vm.envUint("K"));

    ConstructorConfig cfg = ConstructorConfig({ UNDERLYING: ERC20(underlying), BASE_FEE: BASE_FEE, K: K });

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        (address proxy, address implementation) = SwapFactory(FACTORY).deploy(cfg);
        console2.log("Deployment for ", underlying);
        console2.log("TenderSwap deployed at: ", proxy);
        console2.log("Implementation deployed at: ", implementation);
        vm.stopBroadcast();
    }
}
