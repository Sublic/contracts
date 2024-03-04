// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ISublicTokenFactory {
    function createSubscriptionToken(
        string memory _name,
        string memory _symbol
    ) external returns (address newToken, address plugin);
}