// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {MediaFactory} from "../src/MediaFactory.sol";
import {BucketHub} from "@bnb-chain/greenfield-contracts/contracts/middle-layer/resource-mirror/BucketHub.sol";

contract MediaFactoryScript is Script {
    function setUp() public {}

    function run() public {
        address crossChain = vm.envAddress("CROSSCHAIN_ADDRESS");
        address bucketHub = vm.envAddress("BUCKET_HUB_ADDRESS");
        address groupHub = vm.envAddress("GROUP_HUB_ADDRESS");
        address tokenHub = vm.envAddress("TOKEN_HUB_ADDRESS");

        uint256 callbackGasLimit = vm.envUint("CALLBACK_GAS_LIMIT");

        address spAddress = vm.envAddress("SP_OPERATOR_ADDRESS");
        vm.startBroadcast();
        MediaFactory factory = new MediaFactory();

        factory.initialize(crossChain, bucketHub, groupHub, callbackGasLimit, 0);

        factory.updateAdminParams(
            MediaFactory.AdminParams({
                tokenHub: tokenHub,
                spAddress: spAddress,
                readQuotaToCharge: 0,
                bucketValueAmount: 0.01 ether,
                subscribersValueAmount: 0.01 ether,
                authorsValueAmount: 0.02 ether,
                authorsAddValueAmount: 0.01 ether,
                protocolFee: 0.01 ether
            })
        );

        BucketHub buckets = BucketHub(bucketHub);
        buckets.grantRole(buckets.ROLE_CREATE(), address(factory), 2007186241);

        vm.stopBroadcast();
    }

    function createMR() public {
        address factoryAddress = vm.envAddress("FACTORY_ADDRESS");

        MediaFactory factory = MediaFactory(payable(factoryAddress));

        address[] memory authors = new address[](1);
        authors[0] = address(this);

        vm.startBroadcast();

        factory.createMediaResource{value: 0.08 ether}(
            vm.envString("MR_NAME"),
            uint64(vm.envUint("MR_EXPIRE_HEIGHT")),
            uint32(vm.envUint("MR_VIRTUAL_GROUP")),
            vm.envBytes("MR_SIGNATURE"),
            authors
        );

        vm.stopBroadcast();
    }
}
