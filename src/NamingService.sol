// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";

contract NamingService is IWormholeReceiver {
    event TagRegistered(string tag, uint16 senderChain, address sender);
    event TagAlreadyExists(string tag, uint16 senderChain, address sender);

    uint256 constant GAS_LIMIT = 50_000;

    IWormholeRelayer public immutable wormholeRelayer;

    mapping(string => bool) public registeredTags;

    constructor(address _wormholeRelayer) {
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
    }

    function quoteTagRegistration(uint16 targetChain) public view returns (uint256 cost) {
        (cost,) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, 0, GAS_LIMIT);
    }

    function sendTagRegistration(uint16 targetChain, address targetAddress, string memory tag) public payable {
        uint256 cost = quoteTagRegistration(targetChain);
        require(msg.value == cost, "Incorrect amount sent");
        
        // Check if tag is already registered locally
        if (registeredTags[tag]) {
            emit TagAlreadyExists(tag, block.chainid, msg.sender);
            return;
        }

        wormholeRelayer.sendPayloadToEvm{value: cost}(
            targetChain,
            targetAddress,
            abi.encode(tag, msg.sender), // payload
            0, // no receiver value needed
            GAS_LIMIT
        );
    }

    mapping(bytes32 => bool) public seenDeliveryVaaHashes;

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory, // additionalVaas
        bytes32, // address that called 'sendPayloadToEvm' (NamingService contract address)
        uint16 sourceChain,
        bytes32 deliveryHash // this can be stored in a mapping deliveryHash => bool to prevent duplicate deliveries
    ) public payable override {
        require(msg.sender == address(wormholeRelayer), "Only relayer allowed");

        // Ensure no duplicate deliveries
        // need to also add tag values
        require(!seenDeliveryVaaHashes[deliveryHash], "Message already processed");
        seenDeliveryVaaHashes[deliveryHash] = true;

        // Parse the payload and do the corresponding actions!
        (string memory tag, address sender) = abi.decode(payload, (string, address));
        
        // Check if tag is already registered
        if (registeredTags[tag]) {
            emit TagAlreadyExists(tag, sourceChain, sender);
        } else {
            registeredTags[tag] = true;
            emit TagRegistered(tag, sourceChain, sender);
        }
    }
}
