// SPDX-License-Identifier: MIT
// solhint-disable var-name-mixedcase
// solhint-disable payable-fallback

pragma solidity >=0.8.0 <0.9.0;

import "../patterns/Ownable2Step.sol";
import "../patterns/ReentrancyGuard.sol";
import "../patterns/Upgradeable.sol";

import "./WitnetProxy.sol";

/// @title Witnet Request Board base contract, with an Upgradeable (and Destructible) touch.
/// @author Guillermo Díaz <guillermo@otherplane.com>
abstract contract WitnetUpgradableBase
    is
        Ownable2Step,
        Upgradeable, 
        ReentrancyGuard
{
    bytes32 internal immutable _WITNET_UPGRADABLE_VERSION;

    address public immutable deployer = msg.sender;

    constructor(
            bool _upgradable,
            bytes32 _versionTag,
            string memory _proxiableUUID
        )
        Upgradeable(_upgradable)
    {
        _WITNET_UPGRADABLE_VERSION = _versionTag;
        proxiableUUID = keccak256(bytes(_proxiableUUID));
    }
    
    /// @dev Reverts if proxy delegatecalls to unexistent method.
    /* solhint-disable no-complex-fallback */
    fallback() virtual external { 
        _revert(string(abi.encodePacked(
            "not implemented: 0x",
            _toHexString(uint8(bytes1(msg.sig))),
            _toHexString(uint8(bytes1(msg.sig << 8))),
            _toHexString(uint8(bytes1(msg.sig << 16))),
            _toHexString(uint8(bytes1(msg.sig << 24)))
        )));
    }

    function class() virtual public view returns (string memory) {
        return type(WitnetUpgradableBase).name;
    }
   
    // ================================================================================================================
    // --- Overrides 'Proxiable' --------------------------------------------------------------------------------------

    /// @dev Gets immutable "heritage blood line" (ie. genotype) as a Proxiable, and eventually Upgradeable, contract.
    ///      If implemented as an Upgradeable touch, upgrading this contract to another one with a different 
    ///      `proxiableUUID()` value should fail.
    bytes32 public immutable override proxiableUUID;


    // ================================================================================================================
    // --- Overrides 'Upgradeable' --------------------------------------------------------------------------------------

    /// Tells whether provided address could eventually upgrade the contract.
    function isUpgradableFrom(address _from) external view virtual override returns (bool) {
        return (
            // false if the WRB is intrinsically not upgradable, or `_from` is no owner
            isUpgradable()
                && owner() == _from
        );
    }

    /// Retrieves human-readable version tag of current implementation.
    function version() public view virtual override returns (string memory) {
        return _toString(_WITNET_UPGRADABLE_VERSION);
    }


    // ================================================================================================================
    // --- Internal methods -------------------------------------------------------------------------------------------

    function _require(
            bool _condition, 
            string memory _message
        )
        virtual internal view
    {
        if (!_condition) {
            _revert(_message);
        }
    }

    function _revert(string memory _message)
        virtual internal view
    {
        revert(
            string(abi.encodePacked(
                class(),
                ": ",
                _message
            ))
        );
    }

    function _toHexString(uint8 _u)
        internal pure
        returns (string memory)
    {
        bytes memory b2 = new bytes(2);
        uint8 d0 = uint8(_u / 16) + 48;
        uint8 d1 = uint8(_u % 16) + 48;
        if (d0 > 57)
            d0 += 7;
        if (d1 > 57)
            d1 += 7;
        b2[0] = bytes1(d0);
        b2[1] = bytes1(d1);
        return string(b2);
    }

    /// Converts bytes32 into string.
    function _toString(bytes32 _bytes32)
        internal pure
        returns (string memory)
    {
        bytes memory _bytes = new bytes(_toStringLength(_bytes32));
        for (uint _i = 0; _i < _bytes.length;) {
            _bytes[_i] = _bytes32[_i];
            unchecked {
                _i ++;
            }
        }
        return string(_bytes);
    }

    // Calculate length of string-equivalent to given bytes32.
    function _toStringLength(bytes32 _bytes32)
        internal pure
        returns (uint _length)
    {
        for (; _length < 32; ) {
            if (_bytes32[_length] == 0) {
                break;
            }
            unchecked {
                _length ++;
            }
        }
    }

}