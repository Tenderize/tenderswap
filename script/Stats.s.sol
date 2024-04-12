// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Script, console2 } from "forge-std/Script.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { TenderSwap, ConstructorConfig } from "@tenderize/swap/Swap.sol";
import { UD60x18 } from "@prb/math/UD60x18.sol";
import { Tenderizer } from "@tenderize/stake/tenderizer/Tenderizer.sol";
import { StakingXYZ } from "lib/staking/test/helpers/StakingXYZ.sol";

contract Stats is Script {
    function run() public {
        address tenderswap = vm.envAddress("TENDERSWAP");
        TenderSwap swap = TenderSwap(tenderswap);
        console2.log(
            "staking xyz %s",
            StakingXYZ(0xd6d72408586887E37Cf299dbb50181892D3b184e).staked(0xE3350e66D3850B4f4C97b6737E9e8Ff78CFC1b00)
        );
        console2.log("tenderizer asset %s", Tenderizer(0xE3350e66D3850B4f4C97b6737E9e8Ff78CFC1b00).asset());
        console2.log("tenderizer validator %s", Tenderizer(0xE3350e66D3850B4f4C97b6737E9e8Ff78CFC1b00).validator());

        console2.log(
            "tenderizer bal %s",
            Tenderizer(0xE3350e66D3850B4f4C97b6737E9e8Ff78CFC1b00).balanceOf(0xF569CE1f749f073D6B85166141544288b3e24c2B)
        );

        console2.log("tenderizer supply %s", ERC20(address(0xE3350e66D3850B4f4C97b6737E9e8Ff78CFC1b00)).totalSupply());
        ERC20(address(0xE3350e66D3850B4f4C97b6737E9e8Ff78CFC1b00)).approve(tenderswap, 1 ether);
        swap.swap(address(0xE3350e66D3850B4f4C97b6737E9e8Ff78CFC1b00), 1 ether, 0);
        uint256 liabilities = swap.liabilities();
        uint256 liquidity = swap.liquidity();
        UD60x18 utilisation = swap.utilisation();

        console2.log("liabilities %s", liabilities);
        console2.log("liquidity %s", liquidity);
        console2.log("utilisation %s", utilisation.unwrap());
    }
}
