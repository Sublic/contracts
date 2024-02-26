// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {BucketApp} from "@bnb-chain/greenfield-contracts-sdk/BucketApp.sol";
import {GroupApp} from "@bnb-chain/greenfield-contracts-sdk/GroupApp.sol";
import {ITokenHub} from "@bnb-chain/greenfield-contracts/contracts/interface/ITokenHub.sol";
import {ICrossChain} from "@bnb-chain/greenfield-contracts/contracts//interface/ICrossChain.sol";

contract MediaFactory is OwnableUpgradeable, BucketApp, GroupApp {
    // ============ DATA TYPES ====================

    struct MediaElementResourceSet {
        bytes32 id;
        address owner;
        address[] initialAuthors;
        uint256 bucketId;
        uint256 subcribersGroupId;
        uint256 authorsGroupId;
        uint256 unspentEth;
        bool isBucketIdSet;
        bool isSubscribersGroupIdSet;
        bool isAuthorsGroupIdSetSet;
        bool isAuthorsAddedToGroup;
    }

    struct AdminParams {
        address tokenHub;
        address spAddress;
        uint64 readQuotaToCharge;
        uint256 bucketValueAmount;
        uint256 subscribersValueAmount;
        uint256 authorsValueAmount;
        uint256 authorsAddValueAmount;
        uint256 protocolFee;
    }

    enum GroupCreatedType {
        Unspecified,
        Authors,
        Subscribers
    }

    // ============ EVENTS ====================

    event MediaResourceCreationInitiated(bytes32 indexed id);
    event MediaResourceCreationCompleted(bytes32 indexed id);

    // ============ STATE ====================

    mapping(bytes32 => MediaElementResourceSet) public resources;
    AdminParams public params;
    uint256 public claimable;
    mapping(string => bool) public usedNames;

    // ============ initialize ====================

    function initialize(
        address _crossChain,
        address _bucketHub,
        address _groupHub,
        uint256 _callbackGasLimit,
        uint8 _failureHandleStrategy
    ) public initializer {
        __Ownable_init();
        __base_app_init_unchained(_crossChain, _callbackGasLimit, _failureHandleStrategy);
        __bucket_app_init_unchained(_bucketHub);
        __group_app_init_unchained(_groupHub);
    }

    // ============ RESTRICTED FUNCTIONS ====================

    function updateAdminParams(AdminParams calldata newParams) external onlyOwner {
        params = newParams;
    }

    function claimCollectedFee(address recepient, uint256 amount) external onlyOwner {
        require(amount >= claimable, "SublicMediaFactory: ERROR_INNSUFFICIENT_CLAIM_AMOUNT");
        (bool success,) = payable(recepient).call{value: amount}("");

        require(success, "SublicMediaFactory: ERROR_FEE_ETH_TRANSFER_FAIL");
    }

    // ============ OVERRIDES ====================

    function greenfieldCall(
        uint32 status,
        uint8 resourceType,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) external override(BucketApp, GroupApp) {
        require(msg.sender == bucketHub || msg.sender == groupHub, "SublicMediaFactory: ERROR_INVALID_RELAY_CALLER");

        if (resourceType == RESOURCE_BUCKET) {
            _bucketGreenfieldCall(status, operationType, resourceId, callbackData);
        } else if (resourceType == RESOURCE_GROUP) {
            _groupGreenfieldCall(status, operationType, resourceId, callbackData);
        } else {
            revert("SublicMediaFactory: ERROR_INVALID_RESOURCE");
        }
    }

    // ============ MODIFIERS ====================

    modifier onlySelfCall() {
        require(_msgSender() == address(this));
        _;
    }

    // ============ INTERNALS ====================

    function _tryNotifyResourceCompleted(bytes32 id) internal {
        MediaElementResourceSet storage resource = resources[id];
        bool isCompleted = resource.isBucketIdSet && resource.isAuthorsGroupIdSetSet && resource.isSubscribersGroupIdSet
            && resource.isAuthorsAddedToGroup;

        if (isCompleted) {
            (uint256 relayFee, uint256 minAckRelayFee) = ICrossChain(crossChain).getRelayFees();
            if (resource.unspentEth > (relayFee + minAckRelayFee)) {
                bool success = ITokenHub(params.tokenHub).transferOut{value: resource.unspentEth}(
                    resource.owner, resource.unspentEth - relayFee - minAckRelayFee
                );
                require(success, "SublicMediaFactory: ERROR_UNSPENT_ETH_TRANSFER_FAIL");
            } else {
                claimable += resource.unspentEth;
            }
            resources[id].unspentEth = 0;
            emit MediaResourceCreationCompleted(id);
        }
    }

    function _createBucketCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData)
        internal
        override(BucketApp)
    {
        (bytes32 resourceId) = abi.decode(_callbackData, (bytes32));
        if (_status == STATUS_SUCCESS) {
            resources[resourceId].bucketId = _tokenId;
            resources[resourceId].isBucketIdSet = true;

            _tryNotifyResourceCompleted(resourceId);
        }
    }

    function _createGroupCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData)
        internal
        override(GroupApp)
    {
        (bytes32 resourceId, GroupCreatedType groupType) = abi.decode(_callbackData, (bytes32, GroupCreatedType));
        require(groupType != GroupCreatedType.Unspecified, "SublicMediaFactory: ERROR_INVALID_GROUP_TYPE_CREATED");

        if (_status == STATUS_SUCCESS) {
            if (groupType == GroupCreatedType.Subscribers) {
                resources[resourceId].subcribersGroupId = _tokenId;
                resources[resourceId].isSubscribersGroupIdSet = true;
            } else {
                resources[resourceId].authorsGroupId = _tokenId;
                resources[resourceId].isAuthorsGroupIdSetSet = true;

                address[] storage authors = resources[resourceId].initialAuthors;
                MediaFactory(this).addAuthorsToGroup{value: params.authorsAddValueAmount}(
                    resources[resourceId].owner, _tokenId, authors, resourceId
                );

                resources[resourceId].unspentEth -= params.authorsAddValueAmount;
            }

            _tryNotifyResourceCompleted(resourceId);
        }
    }

    function _updateGroupCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData)
        internal
        override(GroupApp)
    {
        (bytes32 resourceId) = abi.decode(_callbackData, (bytes32));

        if (_status == STATUS_SUCCESS && resources[resourceId].authorsGroupId == _tokenId) {
            resources[resourceId].isAuthorsAddedToGroup = true;
            _tryNotifyResourceCompleted(resourceId);
        }
    }

    function initBucketResource(
        address sender,
        uint64 expireHeight,
        uint32 virtualGroupFamilyId,
        string calldata name,
        bytes calldata bucketSignature,
        bytes32 resourceId
    ) public payable onlySelfCall {
        _createBucket(
            sender,
            string.concat("sublic-", name),
            BucketVisibilityType.Private,
            sender,
            params.spAddress,
            expireHeight,
            virtualGroupFamilyId,
            bucketSignature,
            params.readQuotaToCharge,
            sender,
            FailureHandleStrategy.BlockOnFail,
            abi.encode(resourceId),
            callbackGasLimit
        );
    }

    function initSubscribersGroupResource(address sender, string calldata name, bytes32 resourceId)
        public
        payable
        onlySelfCall
    {
        _createGroup(
            sender,
            FailureHandleStrategy.BlockOnFail,
            abi.encode(resourceId, GroupCreatedType.Subscribers),
            address(this),
            string.concat("sublic-", name, "-subscribers"),
            callbackGasLimit
        );
    }

    function initAuthorsGroupResource(address sender, string calldata name, bytes32 resourceId)
        public
        payable
        onlySelfCall
    {
        _createGroup(
            sender,
            FailureHandleStrategy.BlockOnFail,
            abi.encode(resourceId, GroupCreatedType.Authors),
            address(this),
            string.concat("sublic-", name, "-authors"),
            callbackGasLimit
        );
    }

    function addAuthorsToGroup(address owner, uint256 groupId, address[] calldata authors, bytes32 resourceId)
        public
        payable
        onlySelfCall
    {
        uint64[] memory expirations = new uint64[](authors.length);

        for (uint256 i = 0; i < authors.length; i++) {
            expirations[i] = 0;
        }

        _updateGroup(
            owner,
            groupId,
            UpdateGroupOpType.AddMembers,
            authors,
            expirations,
            owner,
            FailureHandleStrategy.BlockOnFail,
            abi.encode(resourceId),
            callbackGasLimit
        );
    }

    // ============ PUBLIC METHODS ===============

    function createMediaResource(
        string calldata name,
        uint64 expireHeight,
        uint32 virtualGroupFamilyId,
        bytes calldata bucketSignature,
        address[] calldata authors
    ) external payable {
        require(!usedNames[name], "SublicMediaFactory: ERROR_NAME_ALREADY_USED");
        (uint256 relayFee, uint256 minAckRelayFee) = ICrossChain(crossChain).getRelayFees();
        require(
            msg.value
                >= params.bucketValueAmount + params.authorsValueAmount + params.subscribersValueAmount
                    + params.authorsAddValueAmount + params.protocolFee + 2 * relayFee + 2 * minAckRelayFee,
            "SublicMediaFactory: ERROR_INSUFFICIENT_PAYMENT_AMOUNT"
        );
        bytes32 resourceId = keccak256(abi.encodePacked(name, authors, _msgSender()));

        ITokenHub tokens = ITokenHub(params.tokenHub);

        bool success = tokens.transferOut{value: (params.protocolFee / 2) + relayFee + minAckRelayFee}(
            address(this), params.protocolFee / 2
        );
        require(success, "SublicMediaFactory: ERROR_FEE_ETH_TRANSFER_FAIL");

        success = tokens.transferOut{value: (params.protocolFee / 2) + relayFee + minAckRelayFee}(
            _msgSender(), params.protocolFee / 2
        );
        require(success, "SublicMediaFactory: ERROR_FEE_ETH_TRANSFER_FAIL");

        MediaFactory(this).initBucketResource{value: params.bucketValueAmount}(
            _msgSender(), expireHeight, virtualGroupFamilyId, name, bucketSignature, resourceId
        );
        MediaFactory(this).initSubscribersGroupResource{value: params.subscribersValueAmount}(
            _msgSender(), name, resourceId
        );
        MediaFactory(this).initAuthorsGroupResource{value: params.authorsValueAmount}(_msgSender(), name, resourceId);

        resources[resourceId] = MediaElementResourceSet({
            id: resourceId,
            owner: _msgSender(),
            unspentEth: msg.value - params.bucketValueAmount - params.authorsValueAmount - params.subscribersValueAmount
                - params.protocolFee - 2 * relayFee - 2 * minAckRelayFee,
            initialAuthors: authors,
            bucketId: 0,
            subcribersGroupId: 0,
            authorsGroupId: 0,
            isBucketIdSet: false,
            isSubscribersGroupIdSet: false,
            isAuthorsGroupIdSetSet: false,
            isAuthorsAddedToGroup: false
        });

        emit MediaResourceCreationInitiated(resourceId);
    }

    receive() external payable {
        claimable += msg.value;
    }

    fallback() external payable {
        claimable += msg.value;
    }
}