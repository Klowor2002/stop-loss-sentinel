// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

interface IERC20Minimal {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @title GuardedVault — destination (callback) contract on Lasna.
/// @notice Holds a volatile-token position for its beneficiary. When the StopLossSentinel reactive
///         contract decides the market has crossed a threshold, it requests a callback and this
///         vault exits the position into the stable token — no human, keeper bot, or server involved.
/// @dev Callback authentication: the callback proxy (on Lasna, the Reactive system contract itself)
///      must be the caller (`onlyServiceProvider`, inherited) and the payload's first argument —
///      overwritten by the proxy with the reactive contract's address — must be the sentinel
///      (`onlyCallbackSender`, inherited).
contract GuardedVault is AbstractCallback {
    enum ExitReason {
        None,
        StopLoss,
        TakeProfit
    }

    IERC20Minimal public immutable volatileToken;
    IERC20Minimal public immutable stableToken;

    address public owner;
    address public beneficiary;

    uint256 public position; // volatile tokens currently held as the open position
    bool public positionActive;

    ExitReason public lastExitReason;
    uint256 public lastExitPrice;
    uint256 public lastExitStableOut;
    uint256 public exitCount;

    event Deposited(address indexed user, uint256 amount);
    event Exited(ExitReason reason, uint256 price, uint256 volatileIn, uint256 stableOut);

    /// @param callbackProxy_ On Lasna the callback proxy is the system contract 0x8888…8888.
    /// @param callbackSender_ The StopLossSentinel reactive contract — the only allowed sender.
    constructor(
        IPayable callbackProxy_,
        address callbackSender_,
        address volatileToken_,
        address stableToken_
    ) payable AbstractCallback(callbackProxy_, callbackSender_) {
        owner = msg.sender;
        volatileToken = IERC20Minimal(volatileToken_);
        stableToken = IERC20Minimal(stableToken_);
    }

    /// @notice Open (or top up) the guarded position. The depositor becomes the beneficiary.
    function deposit(uint256 amount) external {
        require(amount > 0, "zero");
        position += amount;
        positionActive = true;
        beneficiary = msg.sender;
        emit Deposited(msg.sender, amount);
        require(volatileToken.transferFrom(msg.sender, address(this), amount), "transfer failed");
    }

    /// @notice Callback entry point: exit the whole position at the stop-loss trigger price.
    /// @dev The first parameter is a placeholder — the callback proxy overwrites it with the
    ///      reactive contract's address before delivery.
    function executeStopLoss(address reactive_, uint256 price_) external onlyServiceProvider onlyCallbackSender(reactive_) {
        _exit(ExitReason.StopLoss, price_);
    }

    /// @notice Callback entry point: exit the whole position at the take-profit trigger price.
    function executeTakeProfit(address reactive_, uint256 price_) external onlyServiceProvider onlyCallbackSender(reactive_) {
        _exit(ExitReason.TakeProfit, price_);
    }

    function _exit(ExitReason reason, uint256 price_) internal {
        require(positionActive && position > 0, "no open position");
        uint256 volatileIn = position;
        // Price is USD cents per token; the stable token is a $1 token with 18 decimals.
        uint256 stableOut = (volatileIn * price_) / 100;
        position = 0;
        positionActive = false;
        lastExitReason = reason;
        lastExitPrice = price_;
        lastExitStableOut = stableOut;
        exitCount += 1;
        emit Exited(reason, price_, volatileIn, stableOut);
        // Settlement: the vault pays the beneficiary from its pre-funded stable inventory.
        // (On a real venue this is where the sell order would be placed; the reactive
        //  trigger — the part this project demonstrates — is identical either way.)
        require(stableToken.transfer(beneficiary, stableOut), "stable payout failed");
    }

    /// @notice Settles any outstanding callback-fee debt from this contract's own balance.
    function coverDebt() external {
        _coverDebt();
    }
}
