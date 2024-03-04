// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ISublicMediaGroupManager {
    function addToGroup(address user, bytes32 mediaId) external;
}