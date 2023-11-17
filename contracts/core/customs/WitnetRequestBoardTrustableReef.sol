// SPDX-License-Identifier: MIT

/* solhint-disable var-name-mixedcase */

pragma solidity >=0.7.0 <0.9.0;
pragma experimental ABIEncoderV2;

// Inherits from:
import "../defaults/WitnetRequestBoardTrustableDefault.sol";

/// @title Witnet Request Board OVM-compatible (Optimism) "trustable" implementation.
/// @notice Contract to bridge requests to Witnet Decentralized Oracle Network.
/// @dev This contract enables posting requests that Witnet bridges will insert into the Witnet network.
/// The result of the requests will be posted back to this contract by the bridge nodes too.
/// @author The Witnet Foundation
contract WitnetRequestBoardTrustableReef
    is
        WitnetRequestBoardTrustableDefault
{           
    constructor(
            WitnetRequestFactory _factory,
            bool _upgradable,
            bytes32 _versionTag,
            uint256 _reportResultGasBase,
            uint256 _sstoreFromZeroGas
        )
        WitnetRequestBoardTrustableDefault(
            _factory,
            _upgradable,
            _versionTag,
            _reportResultGasBase,
            _sstoreFromZeroGas
        )
    {}
    
    // ================================================================================================================
    // --- Overrides 'IWitnetRequestBoard' ----------------------------------------------------------------------------

    /// @notice Estimate the minimum reward required for posting a data request.
    /// @dev Underestimates if the size of returned data is greater than `_resultMaxSize`. 
    /// @param _gasPrice Expected gas price to pay upon posting the data request.
    /// @param _resultMaxSize Maximum expected size of returned data (in bytes).
    function estimateBaseFee(uint256 _gasPrice, uint256 _resultMaxSize)
        public view
        virtual override
        returns (uint256)
    {
        return WitnetRequestBoardTrustableDefault.estimateBaseFee(1, _resultMaxSize);
    }


    // ================================================================================================================
    // --- Overrides 'Payable' ----------------------------------------------------------------------------------------

    /// Gets current transaction price.
    function _getGasPrice()
        internal pure
        virtual override
        returns (uint256)
    {
        return 1;
    }
}
