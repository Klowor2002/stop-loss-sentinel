// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title PriceFeed — the origin contract. Emits `PriceUpdated` whenever the price moves.
/// @notice Prices are USD cents per token (e.g. 300_00 = $300.00). In production this role would be
///         played by an exchange or oracle contract; here the feed is owner-driven so the demo can
///         move the market on demand. The reactive contract downstream does not care who writes
///         the price — it only reacts to the event.
contract PriceFeed {
    address public owner;
    uint256 public price;
    uint256 public updatedAt;

    event PriceUpdated(uint256 price);

    constructor(uint256 initialPrice) {
        owner = msg.sender;
        price = initialPrice;
        updatedAt = block.timestamp;
        emit PriceUpdated(initialPrice);
    }

    function setPrice(uint256 newPrice) external {
        require(msg.sender == owner, "not owner");
        price = newPrice;
        updatedAt = block.timestamp;
        emit PriceUpdated(newPrice);
    }
}
