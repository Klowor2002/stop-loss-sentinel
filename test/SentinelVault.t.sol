// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { TestToken } from "../src/TestToken.sol";
import { PriceFeed } from "../src/PriceFeed.sol";
import { GuardedVault } from "../src/GuardedVault.sol";
import { StopLossSentinel } from "../src/StopLossSentinel.sol";

/// @notice Minimal stand-in for the Reactive system contract, etched at 0x8888…8888 in tests.
///         Records subscriptions and callback requests so tests can replay the callback the
///         same way the real proxy delivers it (first payload argument overwritten with the
///         reactive contract's address).
contract MockSystemContract {
    uint256 public subscriptionCount;
    uint256 public callbackCount;
    uint256 public lastCallbackChainId;
    address public lastCallbackRecipient;
    uint64 public lastCallbackGasLimit;
    bytes public lastCallbackPayload;

    function subscribe(uint256, address, uint256, uint256, uint256, uint256) external {
        subscriptionCount += 1;
    }

    function unsubscribe(uint256, address, uint256, uint256, uint256, uint256) external {
        subscriptionCount -= 1;
    }

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory config_) external {
        callbackCount += 1;
        lastCallbackChainId = config_.chainId;
        lastCallbackRecipient = config_.recipient;
        lastCallbackGasLimit = config_.gasLimit;
        lastCallbackPayload = config_.payload;
    }

    function requestCallback(ISystemContract.CallbackVersion, bytes memory) external {
        callbackCount += 1;
    }

    function debt(address) external pure returns (uint256) {
        return 0;
    }

    receive() external payable {}
}

/// @notice Local logic tests. The real end-to-end proof is the Lasna deployment; here the mock
///         system contract lets us drive `react()` and replay the requested callback locally.
contract SentinelVaultTest is Test {
    address payable internal constant SYSTEM = payable(0x8888888888888888888888888888888888888888);

    MockSystemContract internal mock;
    TestToken internal volt;
    TestToken internal susd;
    PriceFeed internal feed;
    GuardedVault internal vault;
    StopLossSentinel internal sentinel;

    function setUp() public {
        mock = new MockSystemContract();
        vm.etch(SYSTEM, address(mock).code);

        volt = new TestToken("Volatile Token", "VOLT");
        susd = new TestToken("USD Test", "sUSD");
        feed = new PriceFeed(300_00); // $300.00
        sentinel = new StopLossSentinel(address(feed), 250_00, 400_00);
        vault = new GuardedVault(IPayable(SYSTEM), address(sentinel), address(volt), address(susd));
        sentinel.setVault(address(vault));

        volt.mint(address(this), 100 ether);
        susd.mint(address(vault), 1_000_000 ether); // settlement inventory
        volt.approve(address(vault), type(uint256).max);
        vault.deposit(10 ether);
    }

    function _log(uint256 price) internal view returns (IReactive.LogRecord memory log_) {
        log_.chainId = 5318007;
        log_.contractAddress = address(feed);
        log_.topic0 = uint256(keccak256("PriceUpdated(uint256)"));
        log_.data = abi.encode(price);
        log_.opCode = 1;
    }

    /// @dev Replays the mock's recorded callback exactly like the real proxy: the caller is the
    ///      proxy and the payload's first argument is overwritten with the reactive contract.
    function _deliverLastCallback() internal {
        bytes memory payload = MockSystemContract(SYSTEM).lastCallbackPayload();
        bytes memory args = new bytes(payload.length - 4);
        for (uint256 i = 0; i < args.length; i++) {
            args[i] = payload[i + 4];
        }
        (, uint256 price) = abi.decode(args, (address, uint256));
        bytes4 selector;
        assembly {
            selector := mload(add(payload, 32))
        }
        bytes memory finalCall = abi.encodeWithSelector(selector, address(sentinel), price);
        address recipient = MockSystemContract(SYSTEM).lastCallbackRecipient();
        vm.prank(SYSTEM);
        (bool ok, bytes memory err) = recipient.call(finalCall);
        if (!ok) {
            assembly {
                revert(add(err, 32), mload(err))
            }
        }
    }

    function test_SubscribedOnDeploy() public view {
        assertEq(MockSystemContract(SYSTEM).subscriptionCount(), 1);
    }

    function test_PositionOpen() public view {
        assertTrue(vault.positionActive());
        assertEq(vault.position(), 10 ether);
    }

    function test_NoTriggerInsideBand() public {
        vm.prank(SYSTEM);
        sentinel.react(_log(300_00));
        assertEq(sentinel.observations(), 1);
        assertFalse(sentinel.latched());
        assertEq(MockSystemContract(SYSTEM).callbackCount(), 0);
        assertTrue(vault.positionActive());
    }

    function test_StopLossFullLoop() public {
        vm.prank(SYSTEM);
        sentinel.react(_log(240_00)); // below the $250 stop
        assertTrue(sentinel.latched());
        assertEq(MockSystemContract(SYSTEM).callbackCount(), 1);
        assertEq(MockSystemContract(SYSTEM).lastCallbackChainId(), 5318007);
        assertEq(MockSystemContract(SYSTEM).lastCallbackRecipient(), address(vault));

        _deliverLastCallback();
        assertFalse(vault.positionActive());
        assertEq(uint256(vault.lastExitReason()), 1); // StopLoss
        assertEq(vault.lastExitPrice(), 240_00);
        assertEq(susd.balanceOf(address(this)), 10 ether * 240); // 10 VOLT * $240.00
    }

    function test_CallbackRejectsWrongSender() public {
        vm.prank(SYSTEM);
        vm.expectRevert();
        vault.executeStopLoss(address(0xBEEF), 240_00);
    }

    function test_CallbackRejectsNonProxyCaller() public {
        vm.expectRevert();
        vault.executeStopLoss(address(sentinel), 240_00);
    }

    function test_TakeProfitFullLoop() public {
        vm.prank(SYSTEM);
        sentinel.react(_log(450_00)); // above the $400 target
        assertTrue(sentinel.latched());
        _deliverLastCallback();
        assertEq(uint256(vault.lastExitReason()), 2); // TakeProfit
        assertEq(susd.balanceOf(address(this)), 10 ether * 450);
    }

    function test_NoCallbackWithoutPosition() public {
        // Close the position manually via a delivered stop-loss, re-arm, then crash again:
        // with no open position the sentinel must not pay for another callback.
        vm.prank(SYSTEM);
        sentinel.react(_log(240_00));
        _deliverLastCallback();
        sentinel.rearm();
        vm.prank(SYSTEM);
        sentinel.react(_log(100_00));
        assertEq(MockSystemContract(SYSTEM).callbackCount(), 1); // unchanged
    }
}
