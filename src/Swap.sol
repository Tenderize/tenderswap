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

import { SD59x18, ZERO as ZERO_SD59, UNIT, unwrap, sd } from "@prb/math/SD59x18.sol";
import { UD60x18, ZERO as ZERO_UD60, UNIT as UNIT_60x18, ud } from "@prb/math/UD60x18.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { ERC721 } from "solmate/tokens/ERC721.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";
import { Adapter } from "@tenderize/stake/adapters/Adapter.sol";
import { Registry } from "@tenderize/stake/registry/Registry.sol";
import { Tenderizer, TenderizerImmutableArgs } from "@tenderize/stake/tenderizer/Tenderizer.sol";
import { Unlocks } from "@tenderize/stake/unlocks/Unlocks.sol";
import { SafeCastLib } from "solmate/utils/SafeCastLib.sol";

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { Multicall } from "@tenderize/swap/util/Multicall.sol";
import { SelfPermit } from "@tenderize/swap/util/SelfPermit.sol";
import { ERC721Receiver } from "@tenderize/swap/util/ERC721Receiver.sol";
import { LPToken } from "@tenderize/swap/LPToken.sol";
import { UnlockQueue } from "@tenderize/swap/UnlockQueue.sol";

pragma solidity 0.8.20;

Registry constant REGISTRY = Registry(0xa7cA8732Be369CaEaE8C230537Fc8EF82a3387EE);
ERC721 constant UNLOCKS = ERC721(0xb98c7e67f63d198BD96574073AD5B3427a835796);
address constant TREASURY = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

error ErrorNotMature(uint256 maturity, uint256 timestamp);
error ErrorAlreadyMature(uint256 maturity, uint256 timestamp);
error ErrorInvalidAsset(address asset);
error ErrorSlippage(uint256 out, uint256 minOut);
error ErrorInsufficientAssets(uint256 requested, uint256 available);
error ErrorRecoveryMode();
error ErrorCalculateLPShares();

struct ConstructorConfig {
    ERC20 UNDERLYING;
    SD59x18 BASE_FEE;
    SD59x18 K;
}

struct SwapParams {
    SD59x18 u;
    SD59x18 U;
    SD59x18 s;
    SD59x18 S;
}

abstract contract SwapStorage {
    uint256 private constant SSLOT = uint256(keccak256("xyz.tenderize.swap.storage.location")) - 1;

    struct Data {
        LPToken lpToken;
        // total amount unlocking
        uint256 unlocking;
        // total amount of liabilities owed to LPs
        uint256 liabilities;
        // sum of token supplies that have outstanding unlocks
        SD59x18 S;
        // Recovery amount, if `recovery` > 0 enable recovery mode
        uint256 recovery;
        // treasury share of rewards pending withdrawal
        uint256 treasuryRewards;
        // Unlock queue to hold unlocks
        UnlockQueue.Data unlockQ;
        // amount unlocking per asset
        mapping(address asset => uint256 unlocking) unlockingForAsset;
        // last supply of a tenderizer when seen, tracked because they are rebasing tokens
        mapping(address asset => SD59x18 lastSupply) lastSupplyForAsset;
        // relayer fees
        mapping(address relayer => uint256 reward) relayerRewards;
    }

    function _loadStorageSlot() internal pure returns (Data storage $) {
        uint256 slot = SSLOT;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := slot
        }
    }
}

contract TenderSwap is Initializable, UUPSUpgradeable, OwnableUpgradeable, SwapStorage, Multicall, SelfPermit, ERC721Receiver {
    using SafeTransferLib for ERC20;
    using SafeCastLib for uint256;
    using UnlockQueue for UnlockQueue.Data;

    event Deposit(address indexed from, uint256 amount, uint256 lpSharesMinted);
    event Withdraw(address indexed to, uint256 amount, uint256 lpSharesBurnt);
    event Swap(address indexed caller, address indexed asset, uint256 amountIn, uint256 fee, uint256 unlockId);
    event UnlockBought(address indexed caller, uint256 tokenId, uint256 amount, uint256 reward, uint256 lpFees);
    event UnlockRedeemed(address indexed relayer, uint256 tokenId, uint256 amount, uint256 reward, uint256 lpFees);
    event RelayerRewardsClaimed(address indexed relayer, uint256 rewards);

    ERC20 public immutable UNDERLYING;
    SD59x18 public immutable BASE_FEE;
    SD59x18 public immutable K;

    // Minimum cut of the fee for LPs when an unlock is bought
    UD60x18 public constant MIN_LP_CUT = UD60x18.wrap(0.05e18);
    // Cut of the fee for the treasury when an unlock is bought or redeemed
    UD60x18 public constant TREASURY_CUT = UD60x18.wrap(0.01e18);
    // Cut of the fee for the relayer when an unlock is redeemed
    UD60x18 public constant RELAYER_CUT = UD60x18.wrap(0.01e18);

    function initialize() public initializer {
        Data storage $ = _loadStorageSlot();
        $.lpToken = new LPToken(UNDERLYING.name(), UNDERLYING.symbol());
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(ConstructorConfig memory config) {
        UNDERLYING = config.UNDERLYING;
        BASE_FEE = config.BASE_FEE;
        K = config.K;
        _disableInitializers();
    }

    function lpToken() public view returns (ERC20) {
        Data storage $ = _loadStorageSlot();
        return ERC20($.lpToken);
    }

    /**
     * @notice Amount of liabilities outstanding to liquidity providers.
     * Liabilities represent all the deposits from liquidity providers and their earned fees.
     */
    function liabilities() public view returns (uint256) {
        Data storage $ = _loadStorageSlot();
        return $.liabilities;
    }

    /**
     * @notice Amount of available liquidity (cash on hand).
     */
    function liquidity() public view returns (uint256) {
        Data storage $ = _loadStorageSlot();
        return $.liabilities - $.unlocking;
    }

    /**
     * @notice Current general utilisation ratio of the pool's liquidity
     * @dev `utilisation = unlocking / liabilities`
     */
    function utilisation() public view returns (UD60x18 r) {
        Data storage $ = _loadStorageSlot();
        if ($.liabilities == 0) return ZERO_UD60;
        r = _utilisation($.unlocking, $.liabilities);
    }

    /**
     * @notice Current oldest unlock in the queue
     * @dev returns a struct with zero values if queue is empty
     * @return unlock UnlockQueue.Item struct
     */
    function oldestUnlock() public view returns (UnlockQueue.Item memory) {
        Data storage $ = _loadStorageSlot();
        return $.unlockQ.head().data;
    }

    /**
     * @notice Current newest unlock in the queue
     * @dev returns a struct with zero values if queue is empty
     * @return unlock UnlockQueue.Item struct
     */
    function newestUnlock() public view returns (UnlockQueue.Item memory) {
        Data storage $ = _loadStorageSlot();
        return $.unlockQ.tail().data;
    }

    /**
     * @notice Deposit liquidity into the pool, receive liquidity pool shares in return.
     * The liquidity pool shares represent an amount of liabilities owed to the liquidity provider.
     * @param amount Amount of liquidity to deposit
     * @param minLpShares Minimum amount of liquidity pool shares to receive
     * @return lpShares Amount of liquidity pool shares minted
     */
    function deposit(uint256 amount, uint256 minLpShares) external returns (uint256 lpShares) {
        Data storage $ = _loadStorageSlot();

        // Transfer tokens to the pool
        UNDERLYING.safeTransferFrom(msg.sender, address(this), amount);

        // Calculate LP tokens to mint
        lpShares = _calculateLpShares(amount);
        if (lpShares < minLpShares) revert ErrorSlippage(lpShares, minLpShares);

        // Update liabilities
        $.liabilities += amount;

        // Mint LP tokens to the caller
        $.lpToken.mint(msg.sender, lpShares);

        emit Deposit(msg.sender, amount, lpShares);
    }

    /**
     * @notice Withdraw liquidity from the pool, burn liquidity pool shares.
     * If not enough liquidity is available, the transaction will revert.
     * In this case the liquidity provider has to wait until pending unlocks are processed,
     * and the liquidity becomes available again to withdraw.
     * @param amount Amount of liquidity to withdraw
     * @param maxLpSharesBurnt Maximum amount of liquidity pool shares to burn
     */
    function withdraw(uint256 amount, uint256 maxLpSharesBurnt) external {
        Data storage $ = _loadStorageSlot();

        uint256 available = liquidity();

        if (amount > available) revert ErrorInsufficientAssets(amount, available);

        // Calculate LP tokens to burn
        uint256 lpShares = _calculateLpShares(amount);
        if (lpShares > maxLpSharesBurnt) revert ErrorSlippage(lpShares, maxLpSharesBurnt);

        // Update liabilities
        $.liabilities -= amount;

        // Burn LP tokens from the caller
        $.lpToken.burn(msg.sender, lpShares);

        // Transfer tokens to caller
        UNDERLYING.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount, lpShares);
    }

    /**
     * @notice Claim outstanding rewards for a relayer.
     * @return relayerReward Amount of tokens claimed
     */
    function claimRelayerRewards() public returns (uint256 relayerReward) {
        Data storage $ = _loadStorageSlot();

        relayerReward = $.relayerRewards[msg.sender];

        delete $.relayerRewards[msg.sender];

        UNDERLYING.safeTransfer(msg.sender, relayerReward);

        emit RelayerRewardsClaimed(msg.sender, relayerReward);
    }

    function claimTreasuryRewards() public onlyOwner returns (uint256 treasuryReward) {
        Data storage $ = _loadStorageSlot();

        treasuryReward = $.treasuryRewards;

        $.treasuryRewards = 0;

        UNDERLYING.safeTransfer(TREASURY, treasuryReward);
    }

    /**
     * @notice Check outstanding rewards for a relayer.
     * @param relayer Address of the relayer
     * @return relayerReward Amount of tokens that can be claimed
     */
    function pendingRelayerRewards(address relayer) external view returns (uint256) {
        Data storage $ = _loadStorageSlot();
        return $.relayerRewards[relayer];
    }

    /**
     * @notice Quote the amount of tokens that would be received for a given amount of input tokens.
     * @dev This function wraps `swap` in `staticcall` and is therefore not very gas efficient to be used on-chain.
     * @param asset Address of the input token
     * @param amount Amount of input tokens
     * @return out Amount of output tokens
     * @return fee Amount of fees paid
     */
    function quote(address asset, uint256 amount) public view returns (uint256 out, uint256 fee) {
        Data storage $ = _loadStorageSlot();

        SD59x18 U = sd(int256($.unlocking));
        SD59x18 u = sd(int256($.unlockingForAsset[asset]));
        (SD59x18 s, SD59x18 S) = _checkSupply(asset);

        SwapParams memory p = SwapParams({ U: U, u: u, S: S, s: s });
        return _quote(amount, p);
    }

    /**
     * @notice Swap an amount of input tokens for an amount of output tokens.
     * @dev This function reverts if expected output amount is smaller than the required minimum output amount
     * specified by the caller. This allows slippage protection.
     * @param asset Address of the input token
     * @param amount Amount of input tokens
     * @param minOut Minimum amount of output tokens to receive
     * @return out Amount of output tokens
     * @return fee Amount of fees paid
     */
    function swap(address asset, uint256 amount, uint256 minOut) external returns (uint256 out, uint256 fee) {
        if (!_isValidAsset(asset)) revert ErrorInvalidAsset(asset);

        Data storage $ = _loadStorageSlot();

        SD59x18 U = sd(int256($.unlocking));
        SD59x18 u = sd(int256($.unlockingForAsset[asset]));
        SD59x18 x = sd(int256(amount));
        (SD59x18 s, SD59x18 S) = _checkSupply(asset);

        SwapParams memory p = SwapParams({ U: U, u: u, S: S, s: s });

        (out, fee) = _quote(amount, p);

        // Revert if slippage threshold is exceeded, i.e. if `out` is less than `minOut`
        if (out < minOut) revert ErrorSlippage(out, minOut);

        // update pool state
        // - Update total amount unlocking
        $.unlocking += amount;
        // - update supplyForAsset
        $.lastSupplyForAsset[asset] = s.sub(x);
        // - update S
        $.S = S.sub(x);
        // - update unlockingForAsset
        $.unlockingForAsset[asset] += amount;

        // Transfer `amount` of `from` to this pool
        ERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Handle Unlocking of assets
        uint256 id = _unlock(asset, amount, fee);

        // Transfer `out` of `to` to msg.sender
        UNDERLYING.safeTransfer(msg.sender, out);

        emit Swap(msg.sender, asset, amount, fee, id);
    }

    /**
     * @notice Purchase the earliest pending unlock NFT. The caller will receive the NFT,
     *  which represents an amount of tokens that unlock at maturity. The caller will also
     * receive a reward for purchasing the NFT, which decays as time to maturity decreases.
     * @dev Unlocks NFTs are held in a special dequeue, which is ordered by maturity.
     * The earliest pending unlock is always at the back of the queue. The queue must be traversed
     * from back to front to purchase unlocks.
     * @return tokenId The ID of the purchased unlock NFT
     */
    function buyUnlock() external returns (uint256 tokenId) {
        Data storage $ = _loadStorageSlot();

        // Can not purchase unlocks in recovery mode
        // The fees need to flow back to paying off debt and relayers are cheaper
        if ($.recovery > 0) revert ErrorRecoveryMode();

        // get newest item from unlock queue
        UnlockQueue.Item memory unlock = $.unlockQ.popTail().data;

        // revert if unlock at maturity
        tokenId = unlock.id;
        (address tenderizer,) = _decodeTokenId(tokenId);
        Adapter adapter = Tenderizer(tenderizer).adapter();
        uint256 time = adapter.currentTime();
        if (unlock.maturity <= time) revert ErrorAlreadyMature(unlock.maturity, block.timestamp);

        // Calculate the reward for purchasing the unlock
        // The base reward is the fee minus the MIN_LP_CUT going to liquidity providers and minus the TREASURY_CUT going to the
        // treasury
        // The base reward then further decays as time to maturity decreases
        uint256 reward;
        uint256 lpCut;
        uint256 treasuryCut;
        {
            UD60x18 fee60x18 = ud(unlock.fee);
            lpCut = fee60x18.mul(MIN_LP_CUT).unwrap();
            treasuryCut = fee60x18.mul(TREASURY_CUT).unwrap();
            uint256 baseReward = unlock.fee - lpCut - treasuryCut;
            UD60x18 progress = ud(unlock.maturity - time).div(ud(adapter.unlockTime()));
            reward = ud(baseReward).mul(UNIT_60x18.sub(progress)).unwrap();
            // Adjust lpCut by the remaining amount after subtracting the reward
            // This step seems to adjust lpCut to balance out the distribution
            // Assuming the final lpCut should encompass any unallocated fee portions
            lpCut += baseReward - reward;
        }

        // Update pool state
        // - update unlocking
        $.unlocking -= unlock.amount;
        // - Update liabilities to distribute LP rewards
        $.liabilities += lpCut;
        // - Update treasury rewards
        $.treasuryRewards += treasuryCut;

        uint256 ufa = $.unlockingForAsset[tenderizer] - unlock.amount;
        // - Update S if unlockingForAsset is now zero
        if (ufa == 0) {
            $.S = $.S.sub($.lastSupplyForAsset[tenderizer]);
            $.lastSupplyForAsset[tenderizer] = ZERO_SD59;
        }
        // - Update unlockingForAsset
        $.unlockingForAsset[tenderizer] = ufa;

        // transfer unlock amount minus reward from caller to pool
        // the reward is the discount paid. 'reward < unlock.fee' always.
        UNDERLYING.safeTransferFrom(msg.sender, address(this), unlock.amount - reward);

        // transfer unlock to caller
        UNLOCKS.safeTransferFrom(address(this), msg.sender, tokenId);

        emit UnlockBought(msg.sender, tokenId, unlock.amount, reward, lpCut);
    }

    /**
     * @notice Redeem an unlock NFT at maturity on behalf of the pool. The pool receives the tokens from the unlock.
     * The caller receives a small portion of the fee that was paid during the swap that created the unlock.
     * @dev The oldest unlocks are at the front of the queue. The queue must be traversed from front to back to redeem
     * unlocks that have reached maturity.
     */
    function redeemUnlock() external {
        Data storage $ = _loadStorageSlot();

        // get oldest item from unlock queue
        UnlockQueue.Item memory unlock = $.unlockQ.popHead().data;

        // withdraw the unlock (returns amount withdrawn)
        (address tenderizer, uint96 id) = _decodeTokenId(unlock.id);
        // this will revert if unlock is not at maturity
        uint256 amountReceived = Tenderizer(tenderizer).withdraw(address(this), id);

        uint256 fee = unlock.fee;

        {
            uint256 recovery = $.recovery;

            // Handle deficit
            if (amountReceived < unlock.amount) {
                recovery += unlock.amount - amountReceived;
            }

            // Handle surplus
            if (amountReceived > unlock.amount) {
                uint256 excess = amountReceived - unlock.amount;
                amountReceived = unlock.amount;
                if (excess > recovery) {
                    excess -= recovery;
                    recovery = 0;
                    $.liabilities += excess;
                } else {
                    recovery -= excess;
                    excess = 0;
                }
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
            $.S = $.S.sub($.lastSupplyForAsset[tenderizer]);
            $.lastSupplyForAsset[tenderizer] = ZERO_SD59;
        }
        // - Update unlockingForAsset
        $.unlockingForAsset[tenderizer] = ufa;

        //calculate the relayer reward
        uint256 relayerReward = ud(unlock.fee).mul(RELAYER_CUT).unwrap();
        // update relayer rewards
        $.relayerRewards[msg.sender] += relayerReward;

        // - Update liabilities to distribute LP rewards
        uint256 lpReward;
        if (fee > 0) {
            uint256 treasuryCut = ud(fee).mul(TREASURY_CUT).unwrap();
            $.treasuryRewards += treasuryCut;
            lpReward = fee - treasuryCut - relayerReward;
            $.liabilities += lpReward;
        }

        emit UnlockRedeemed(msg.sender, unlock.id, amountReceived, relayerReward, lpReward);
    }

    function _quote(uint256 amount, SwapParams memory p) internal view returns (uint256 out, uint256 fee) {
        Data storage $ = _loadStorageSlot();

        SD59x18 x = sd(int256(amount));
        SD59x18 L = sd(int256($.liabilities));
        SD59x18 nom;
        SD59x18 denom;

        {
            SD59x18 sumA = p.u.add(x);
            sumA = sumA.mul(K).sub(p.U).add(p.u);
            sumA = sumA.mul(p.U.add(x).div(L).pow(K));

            SD59x18 sumB = p.U.sub(p.u).sub(K.mul(p.u)).mul(p.U.div(L).pow(K));

            nom = sumA.add(sumB).mul(p.S.add(p.U));

            denom = K.mul(UNIT.add(K)).mul(p.s.add(p.u));
        }
        SD59x18 baseFee = BASE_FEE.mul(x);
        fee = uint256(baseFee.add(nom.div(denom)).unwrap());

        fee = fee >= amount ? amount : fee;
        unchecked {
            out = amount - fee;
        }
    }
    // (((u + x)*k - U + u)*((U + x)/L)**k + (-k*u + U - u)*(U/L)**k)*(S + U)/(k*(1 + k)*(s + u))

    /**
     * @notice checks if an asset is a valid tenderizer for `UNDERLYING`
     */
    function _isValidAsset(address asset) internal view returns (bool) {
        return REGISTRY.isTenderizer(asset) && Tenderizer(asset).asset() == address(UNDERLYING);
    }

    function _utilisation(uint256 U, uint256 L) internal pure returns (UD60x18 r) {
        r = ud(U).div(ud(L));
    }

    function _unlock(address asset, uint256 amount, uint256 fee) internal returns (uint256) {
        Data storage $ = _loadStorageSlot();

        Tenderizer t = Tenderizer(asset);

        uint256 id = t.unlock(amount);

        uint256 key = _encodeTokenId(asset, SafeCastLib.safeCastTo96(id));

        uint256 maturity = t.unlockMaturity(id);

        $.unlockQ.push(
            UnlockQueue.Item({
                id: key,
                amount: SafeCastLib.safeCastTo128(amount),
                fee: SafeCastLib.safeCastTo128(fee),
                maturity: maturity
            })
        );

        return key;
    }

    /**
     * @notice Since the LSTs to be exchanged are aTokens, and thus have a rebasing supply,
     * we need to update the supplies upon a swap to correctly determine the spread of the asset.
     */
    function _checkSupply(address tenderizer) internal view returns (SD59x18 s, SD59x18 S) {
        Data storage $ = _loadStorageSlot();

        S = $.S;

        s = sd(int256(Tenderizer(tenderizer).totalSupply()));
        SD59x18 oldSupply = $.lastSupplyForAsset[tenderizer];

        if (oldSupply.lt(s)) {
            S = S.add(s.sub(oldSupply));
        } else if (oldSupply.gt(s)) {
            S = S.sub(oldSupply.sub(s));
        }
    }

    /**
     * @notice Calculates the amount of LP tokens represented by a given amount of liabilities
     */
    function _calculateLpShares(uint256 amount) internal view returns (uint256 shares) {
        Data storage $ = _loadStorageSlot();

        uint256 supply = $.lpToken.totalSupply();
        uint256 L = $.liabilities;

        if (L == 0) {
            return amount * 1e18;
        }

        shares = amount * (supply / L); // calculate factor first since it's scaled up
        if (shares == 0) {
            revert ErrorCalculateLPShares();
        }
    }

    ///@dev required by the OZ UUPS module
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlyOwner { }
}

function _encodeTokenId(address tenderizer, uint96 id) pure returns (uint256) {
    return uint256(bytes32(abi.encodePacked(tenderizer, id)));
}

function _decodeTokenId(uint256 tokenId) pure returns (address tenderizer, uint96 id) {
    bytes32 a = bytes32(tokenId);
    return (address(bytes20(a)), uint96(bytes12(a << 160)));
}
