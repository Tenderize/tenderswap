// SPDX-License-Identifier: MIT
//
//  _____              _           _
// |_   _|            | |         (_)
//   | | ___ _ __   __| | ___ _ __ _ _______
//   | |/ _ \ '_ \ / _` |/ _ \ '__| |_  / _ \
//   | |  __/ | | | (_| |  __/ |  | |/ /  __/
//   \_/\___|_| |_|\__,_|\___|_|  |_/___\___|
//
// Copyright (c) Tenderize Labs Ltd

import { UD60x18, ZERO, UNIT, unwrap, ud } from "@prb/math/UD60x18.sol";
import { ClonesWithImmutableArgs } from "clones/ClonesWithImmutableArgs.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { ERC721 } from "solmate/tokens/ERC721.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { Registry } from "@tenderize/stake/registry/Registry.sol";
import { Tenderizer } from "@tenderize/stake/tenderizer/Tenderizer.sol";
import { Unlocks } from "@tenderize/stake/unlocks/Unlocks.sol";
import { SafeCastLib } from "solmate/utils/SafeCastLib.sol";

import { Multicall } from "@tenderize/swap/util/Multicall.sol";
import { SelfPermit } from "@tenderize/swap/util/SelfPermit.sol";
import { LPToken } from "@tenderize/swap/LPToken.sol";
import { UnlockQueue } from "@tenderize/swap/UnlockQueue.sol";

pragma solidity >=0.8.19;

// TODO: UUPS upgradeable

UD60x18 constant BASE_FEE = UD60x18.wrap(0.0005e18);
UD60x18 constant RELAYER_CUT = UD60x18.wrap(0.1e18);
UD60x18 constant MIN_LP_CUT = UD60x18.wrap(0.1e18);
UD60x18 constant POW = UD60x18.wrap(3e18);

struct Config {
    ERC20 underlying;
    address registry;
    address unlocks;
}

contract TenderSwapStorage {
    uint256 private constant SSLOT = uint256(keccak256("xyz.tenderize.swap.storage.location")) - 1;

    struct Data {
        // total amount unlocking
        uint256 unlocking;
        // total amount of liabilities owed to LPs
        uint256 liabilities;
        // sum of token supplies that have outstanding unlocks
        uint256 S;
        // Unlock queue to hold unlocks
        UnlockQueue.Data unlockQ;
        // Recovery amount, if `recovery` > 0 enable recovery mode
        uint256 recovery;
        // amount unlocking per asset
        mapping(address asset => uint256 unlocking) unlockingForAsset;
        // last supply of a tenderizer when seen, tracked because they are rebasing tokens
        mapping(address asset => uint256 lastSupply) lastSupplyForAsset;
        // relayer fees
        mapping(address relayer => uint256 fee) relayerFees;
    }

    function _loadStorageSlot() internal pure returns (Data storage $) {
        uint256 slot = SSLOT;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := slot
        }
    }
}

contract TenderSwap is TenderSwapStorage, Multicall, SelfPermit {
    using SafeTransferLib for ERC20;
    using SafeCastLib for uint256;
    using UnlockQueue for UnlockQueue.Data;

    error UnlockNotMature(uint256 maturity, uint256 timestamp);
    error UnlockAlreadyMature(uint256 maturity, uint256 timestamp);
    error InvalidAsset(address asset);
    error SlippageThresholdExceeded(uint256 out, uint256 minOut);
    error InsufficientAssets(uint256 requested, uint256 available);
    error RecoveryMode();

    event Deposit(address indexed from, uint256 amount, uint256 lpSharesMinted);
    event Withdraw(address indexed to, uint256 amount, uint256 lpSharesBurnt);
    event Swap(address indexed caller, address indexed asset, uint256 amountIn, uint256 amountOut);
    event UnlockBought(address indexed caller, uint256 tokenId, uint256 amount, uint256 reward, uint256 lpFees);
    event UnlockRedeemed(address indexed relayer, uint256 tokenId, uint256 amount, uint256 reward, uint256 lpFees);
    event RelayerRewardsClaimed(address indexed relayer, uint256 rewards);

    LPToken public immutable lpToken;
    ERC20 private immutable underlying;
    address private immutable registry;
    address private immutable unlocks;

    constructor(Config memory config) {
        lpToken = new LPToken(config.underlying.name(), config.underlying.symbol());
        underlying = config.underlying;
        registry = config.registry;
        unlocks = config.unlocks;
    }

    modifier supplyUpdateHook(address asset) {
        _supplyUpdateHook(asset);
        _;
    }

    function liquidity() public view returns (uint256) {
        Data storage $ = _loadStorageSlot();
        return $.liabilities;
    }

    function availableLiquidity() public view returns (uint256) {
        Data storage $ = _loadStorageSlot();
        return $.liabilities - $.unlocking;
    }

    function utilisation() public view returns (UD60x18 r) {
        Data storage $ = _loadStorageSlot();
        if ($.liabilities == 0) return ZERO;
        r = _utilisation($.unlocking, $.liabilities);
    }

    function utilisationFee() public view returns (UD60x18 f) {
        f = _utilisationFee(utilisation());
    }

    function spread(address asset) public view returns (UD60x18 s) {
        return _spread(asset, 0);
    }

    function deposit(uint256 amount) external {
        Data storage $ = _loadStorageSlot();

        // Transfer tokens to the pool
        underlying.safeTransferFrom(msg.sender, address(this), amount);

        // Calculate LP tokens to mint
        uint256 lpShares = _calculateLpShares(amount);

        // Update liabilities
        $.liabilities += amount;

        // Mint LP tokens to the caller
        lpToken.mint(msg.sender, lpShares);

        emit Deposit(msg.sender, amount, lpShares);
    }

    function withdraw(uint256 amount) external {
        Data storage $ = _loadStorageSlot();

        uint256 available = availableLiquidity();

        if (amount > available) revert InsufficientAssets(amount, available);

        // Calculate LP tokens to burn
        uint256 lpShares = _calculateLpShares(amount);

        // Update liabilities
        $.liabilities -= amount;

        // Burn LP tokens from the caller
        lpToken.burn(msg.sender, lpShares);

        // Transfer tokens to caller
        underlying.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount, lpShares);
    }

    function claimRelayerRewards() public returns (uint256 relayerReward) {
        Data storage $ = _loadStorageSlot();

        relayerReward = $.relayerFees[msg.sender];

        delete $.relayerFees[msg.sender];

        underlying.safeTransfer(msg.sender, relayerReward);

        emit RelayerRewardsClaimed(msg.sender, relayerReward);
    }

    function quote(address asset, uint256 amount) public view returns (uint256 out, uint256 fee) {
        (bool success, bytes memory returnData) =
            address(this).staticcall(abi.encodeWithSelector(this.swap.selector, asset, amount));
        if (success) {
            (out, fee) = abi.decode(returnData, (uint256, uint256));
        }
    }

    function swap(
        address asset,
        uint256 amount,
        uint256 minOut
    )
        external
        supplyUpdateHook(asset)
        returns (uint256 out, uint256 fee)
    {
        if (!_isValidAsset(asset)) revert InvalidAsset(asset);

        Data storage $ = _loadStorageSlot();

        (out, fee) = _quote(asset, amount);

        // Revert if slippage threshold is exceeded, i.e. if `out` is less than `minOut`
        if (out < minOut) revert SlippageThresholdExceeded(out, minOut);

        // update pool state
        // - Update total amount unlocking
        $.unlocking += amount;
        // - update supplyForAsset
        $.lastSupplyForAsset[asset] -= amount;
        // - update S
        $.S -= amount;
        // - update unlockingForAsset
        $.unlockingForAsset[asset] += amount;

        // Transfer `amount` of `from` to this pool
        ERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Handle Unlocking of assets
        _unlock(asset, amount, fee);

        // Transfer `out` of `to` to msg.sender
        underlying.safeTransfer(msg.sender, out);

        emit Swap(msg.sender, asset, amount, out);
    }

    function buyUnlock() external {
        Data storage $ = _loadStorageSlot();

        // Can not purchase unlocks in recovery mode
        // The fees need to flow back to paying off debt and relayers are cheaper
        if ($.recovery > 0) revert RecoveryMode();

        // get newest item from unlock queue
        UnlockQueue.Item memory unlock = $.unlockQ.popBack();

        // revert if unlock at maturity
        if (unlock.maturity <= block.timestamp) revert UnlockNotMature(unlock.maturity, block.timestamp);

        // calculate reward after decay, take base fee cut for LPs
        uint256 reward = (unlock.fee - unwrap(ud(unlock.fee).mul(MIN_LP_CUT))) * unlock.maturity / block.timestamp;

        // Update pool state
        // - update unlocking
        $.unlocking -= unlock.amount;
        // - Update liabilities to distribute LP rewards
        $.liabilities += unlock.fee - reward;

        (address tenderizer,) = _decodeTokenId(unlock.id);
        uint256 ufa = $.unlockingForAsset[tenderizer] - unlock.amount;
        // - Update S if unlockingForAsset is now zero
        if (ufa == 0) {
            $.S -= $.lastSupplyForAsset[tenderizer];
            delete $.lastSupplyForAsset[tenderizer];
        }
        // - Update unlockingForAsset
        $.unlockingForAsset[tenderizer] = ufa;

        // transfer unlock amount minus reward from caller to pool
        underlying.safeTransferFrom(msg.sender, address(this), unlock.amount - reward);

        // transfer unlock to caller
        ERC721(unlocks).safeTransferFrom(address(this), msg.sender, unlock.id);

        emit UnlockBought(msg.sender, unlock.id, unlock.amount, reward, unlock.fee - reward);
    }

    function redeemUnlock() external {
        Data storage $ = _loadStorageSlot();

        // get oldest item from unlock queue
        UnlockQueue.Item memory unlock = $.unlockQ.popFront();

        // revert if unlock *not* at maturity
        if (unlock.maturity > block.timestamp) revert UnlockNotMature(unlock.maturity, block.timestamp);

        // withdraw the unlock (returns amount withdrawn)
        (address tenderizer, uint96 id) = _decodeTokenId(unlock.id);
        uint256 amountReceived = Tenderizer(tenderizer).withdraw(address(this), id);

        // TODO: Handle amount received > 0 ?

        //calculate the relayer reward
        uint256 relayerReward = unwrap(ud(unlock.fee).mul(RELAYER_CUT));
        // update relayer rewards
        $.relayerFees[msg.sender] += relayerReward;

        uint256 fee = unlock.fee - relayerReward;

        // Handle potential recovery mode
        {
            uint256 recovery = $.recovery;

            if (amountReceived < unlock.amount) {
                recovery += unlock.amount - amountReceived;
            }

            if (recovery > 0) {
                if (fee >= recovery) {
                    unchecked {
                        fee -= recovery;
                        recovery = 0;
                    }
                } else {
                    unchecked {
                        recovery -= fee;
                        fee = 0;
                    }
                }
            }
            $.recovery = recovery;
        }

        // update pool state
        // - Update unlocking
        $.unlocking -= amountReceived;
        uint256 ufa = $.unlockingForAsset[tenderizer] - amountReceived;
        // - Update S if unlockingForAsset is now zero
        if (ufa == 0) {
            $.S -= $.lastSupplyForAsset[tenderizer];
            delete $.lastSupplyForAsset[tenderizer];
        }
        // - Update unlockingForAsset
        $.unlockingForAsset[tenderizer] = ufa;

        // - Update liabilities to distribute LP rewards
        $.liabilities += fee;

        emit UnlockRedeemed(msg.sender, unlock.id, amountReceived, relayerReward, fee);
    }

    function _quote(address asset, uint256 amount) internal view returns (uint256 out, uint256 fee) {
        Data storage $ = _loadStorageSlot();

        // calculate utilisation rate
        UD60x18 r = _utilisation($.unlocking + amount, $.liabilities);

        // calculate spread multiplier
        UD60x18 w = _spread(asset, amount);

        // calculate fee by multiplying the base fee by the spread
        UD60x18 f = _utilisationFee(r).mul(w);

        f = f.gt(UNIT) ? UNIT : f; // max 100% fee

        // get the marginal fee
        fee = f.mul(ud(amount)).unwrap();

        // get the output amount
        out = amount - fee;
    }

    function _isValidAsset(address asset) internal view returns (bool) {
        return Registry(registry).isTenderizer(asset) && Tenderizer(asset).asset() == address(underlying);
    }

    function _utilisation(uint256 unlocking, uint256 liabilities) internal pure returns (UD60x18 r) {
        r = ud(unlocking).div(ud(liabilities));
    }

    function _utilisationFee(UD60x18 r) internal pure returns (UD60x18 f) {
        f = BASE_FEE.add(r.pow(POW));
        f > UNIT ? UNIT : f;
    }

    function _spread(address asset, uint256 x) internal view returns (UD60x18 w) {
        Data storage $ = _loadStorageSlot();

        ud($.unlockingForAsset[asset] + x).div(ud($.unlocking + x)).div(ud($.lastSupplyForAsset[asset] + x).div(ud($.S + x)));

        w = ud(($.unlockingForAsset[asset] + x) * $.lastSupplyForAsset[asset]).div(ud(($.unlocking + x) * $.S));
    }

    function _unlock(address asset, uint256 amount, uint256 fee) internal {
        Data storage $ = _loadStorageSlot();

        Tenderizer t = Tenderizer(asset);

        uint256 id = t.unlock(amount);

        uint256 key = _encodeTokenId(asset, SafeCastLib.safeCastTo96(id));

        uint256 maturity = t.unlockMaturity(id);

        $.unlockQ.push(
            key,
            UnlockQueue.Item({
                id: key,
                amount: SafeCastLib.safeCastTo128(amount + fee),
                fee: SafeCastLib.safeCastTo128(fee),
                maturity: maturity
            })
        );
    }

    function _supplyUpdateHook(address tenderizer) internal {
        Data storage $ = _loadStorageSlot();

        uint256 newSupply = Tenderizer(tenderizer).totalSupply();
        uint256 oldSupply = $.lastSupplyForAsset[tenderizer];

        if (oldSupply < newSupply) {
            $.S += newSupply - oldSupply;
        } else if (oldSupply > newSupply) {
            $.S -= oldSupply - newSupply;
        }

        $.lastSupplyForAsset[tenderizer] = newSupply;
    }

    function _calculateLpShares(uint256 amount) internal view returns (uint256) {
        Data storage $ = _loadStorageSlot();

        uint256 supply = lpToken.totalSupply();

        if (supply == 0) {
            return amount;
        }

        return amount * supply / $.liabilities;
    }
}

function _encodeTokenId(address tenderizer, uint96 id) pure returns (uint256) {
    return uint256(bytes32(abi.encodePacked(tenderizer, id)));
}

function _decodeTokenId(uint256 tokenId) pure returns (address tenderizer, uint96 id) {
    bytes32 a = bytes32(tokenId);
    return (address(bytes20(a)), uint96(bytes12(a << 160)));
}
