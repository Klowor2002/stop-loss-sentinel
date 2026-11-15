// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

interface IVaultView {
    function positionActive() external view returns (bool);
}

/// @title StopLossSentinel — the reactive contract (Reactive Lasna, chain 5318007).
/// @notice "Set it and forget it" portfolio protection: this contract subscribes to a price feed's
///         `PriceUpdated` events and, the moment the price crosses the owner's stop-loss or
///         take-profit threshold, requests a callback that makes the GuardedVault exit the position.
///         No keeper, no cron job, no server — the network itself watches the market.
/// @dev Origin and destination are both Lasna in this deployment, which lets `react()` read the
///      vault's state directly and skip the (billed) callback when no position is open.
contract StopLossSentinel is AbstractReactive {
    uint256 public constant LASNA_CHAIN_ID = 5318007;
    uint256 private constant PRICE_UPDATED_TOPIC = uint256(keccak256("PriceUpdated(uint256)"));
    uint64 private constant CALLBACK_GAS_LIMIT = 500_000;

    address public owner;
    address public immutable feed;
    address public vault;

    uint256 public stopLossPrice; // USD cents per token
    uint256 public takeProfitPrice; // USD cents per token

    uint256 public lastPrice;
    uint256 public observations;
    bool public latched; // true after a trigger, until the owner re-arms

    event Observed(uint256 price);
    event Triggered(uint256 kind, uint256 price); // kind: 1 = stop loss, 2 = take profit
    event Rearmed();
    event VaultSet(address vault);
    event ThresholdsSet(uint256 stopLossPrice, uint256 takeProfitPrice);

    constructor(address feed_, uint256 stopLossPrice_, uint256 takeProfitPrice_) payable {
        owner = msg.sender;
        feed = feed_;
        stopLossPrice = stopLossPrice_;
        takeProfitPrice = takeProfitPrice_;
        SYSTEM.subscribe(
            LASNA_CHAIN_ID, feed_, PRICE_UPDATED_TOPIC, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
    }

    function setVault(address vault_) external {
        require(msg.sender == owner, "not owner");
        vault = vault_;
        emit VaultSet(vault_);
    }

    function setThresholds(uint256 stopLossPrice_, uint256 takeProfitPrice_) external {
        require(msg.sender == owner, "not owner");
        require(stopLossPrice_ < takeProfitPrice_, "stop must be below target");
        stopLossPrice = stopLossPrice_;
        takeProfitPrice = takeProfitPrice_;
        emit ThresholdsSet(stopLossPrice_, takeProfitPrice_);
    }

    /// @notice Re-arm after a trigger (e.g. once a new position has been opened).
    function rearm() external {
        require(msg.sender == owner, "not owner");
        latched = false;
        emit Rearmed();
    }

    /// @notice Settles any outstanding reactive-fee debt from this contract's own balance.
    function coverDebt() external {
        _coverDebt();
    }

    function react(LogRecord calldata log_) external override onlySystem {
        if (log_.topic0 != PRICE_UPDATED_TOPIC || log_.contractAddress != feed) {
            return;
        }
        uint256 price = abi.decode(log_.data, (uint256));
        lastPrice = price;
        observations += 1;
        emit Observed(price);

        if (latched || vault == address(0)) {
            return;
        }
        // Same-chain deployment: check the vault before paying for a callback.
        try IVaultView(vault).positionActive() returns (bool active) {
            if (!active) {
                return;
            }
        } catch {
            return;
        }

        if (price <= stopLossPrice) {
            latched = true;
            emit Triggered(1, price);
            _requestExit("executeStopLoss(address,uint256)", price);
        } else if (price >= takeProfitPrice) {
            latched = true;
            emit Triggered(2, price);
            _requestExit("executeTakeProfit(address,uint256)", price);
        }
    }

    function _requestExit(string memory signature_, uint256 price_) internal {
        // The first payload argument is a placeholder: the callback proxy overwrites it with
        // this contract's address, which is how the vault authenticates the callback.
        bytes memory payload = abi.encodeWithSignature(signature_, address(0), price_);
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: LASNA_CHAIN_ID, recipient: vault, gasLimit: CALLBACK_GAS_LIMIT, payload: payload
            })
        );
    }
}
