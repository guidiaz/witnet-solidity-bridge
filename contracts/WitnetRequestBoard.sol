// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "./interfaces/IWitnetRequestBoardEvents.sol";
import "./interfaces/IWitnetRequestBoardReporter.sol";
import "./interfaces/IWitnetRequestBoardRequestor.sol";
import "./interfaces/IWitnetRequestBoardView.sol";
import "./interfaces/IWitnetRequestParser.sol";

import "./interfaces/V2/IWitnetBytecodes.sol";
import "./interfaces/V2/IWitnetRequestFactory.sol";

/// @title Witnet Request Board functionality base contract.
/// @author The Witnet Foundation.
abstract contract WitnetRequestBoard is
    IWitnetRequestBoardEvents,
    IWitnetRequestBoardReporter,
    IWitnetRequestBoardRequestor,
    IWitnetRequestBoardView,
    IWitnetRequestParser
{
    IWitnetRequestFactory immutable public factory;
    IWitnetBytecodes immutable public registry;
    constructor (IWitnetRequestFactory _factory) {
        require(
            _factory.class() == type(IWitnetRequestFactory).interfaceId,
            "WitnetRequestBoard: uncompliant factory"
        );
        factory = _factory;
        registry = _factory.registry();
    }
}