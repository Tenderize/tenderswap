// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Script, console2 } from "forge-std/Script.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { TenderSwap, ConstructorConfig } from "@tenderize/swap/Swap.sol";

contract Add_Liquidity is Script {
    // Contracts are deployed deterministically.
    // e.g. `foo = new Foo{salt: salt}(constructorArgs)`
    // The presence of the salt argument tells forge to use https://github.com/Arachnid/deterministic-deployment-proxy
    bytes32 private constant salt = 0x0;

    // Start broadcasting with private key from `.env` file
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address underlying = vm.envAddress("UNDERLYING");

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        TenderSwap swap = TenderSwap(0x2C7b29B0d07276bA2DF4abE02E9A38b5693af9c6);
        ERC20(underlying).approve(address(swap), 500_000 ether);
        swap.deposit(500_000 ether, 0);
        console2.log("liabilities", swap.liabilities());
        console2.log("liquidity", swap.liquidity());
        // ERC20(0x2eaC4210B90D13666f7E88635096BdC17C51FB70).approve(address(swap), 10 ether);

        // (uint256 out, uint256 fee) = swap.quote(0x2eaC4210B90D13666f7E88635096BdC17C51FB70, 10 ether);
        // console2.log("quote", out);
        // ERC20(0x2eaC4210B90D13666f7E88635096BdC17C51FB70).approve(address(swap), 10 ether);
        // // (out, fee) = swap.swap(0x2eaC4210B90D13666f7E88635096BdC17C51FB70, 10 ether, 0);
        // console2.log("out", out);
        // console2.log("fee", fee);

        // // Other Tenderizer: 0xD58Fed21106A046093086903909478AD96D310a8
        // (out, fee) = swap.quote(0xD58Fed21106A046093086903909478AD96D310a8, 10 ether);
        // console2.log("quote", out);

        vm.stopBroadcast();
    }
}
