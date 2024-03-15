// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "../WitnetRandomness.sol";
import "../apps/UsingWitnet.sol";
import "../interfaces/IWitnetRandomnessAdmin.sol";
import "../patterns/Ownable2Step.sol";

/// @title WitnetRandomnessV20: Unmalleable and provably-fair randomness generation based on the Witnet Oracle.
/// @author The Witnet Foundation.
contract WitnetRandomnessV20
    is
        Ownable2Step,
        UsingWitnet,
        WitnetRandomness,
        IWitnetRandomnessAdmin
{
    using Witnet for bytes;
    using Witnet for Witnet.Result;
    using WitnetV2 for WitnetV2.RadonSLA;

    struct Randomize {
        uint256 witnetQueryId;
        uint256 prevBlock;
        uint256 nextBlock;
    }

    struct Storage {
        uint256 lastRandomizeBlock;
        mapping (uint256 => Randomize) randomize_;
    }

    /// @notice Unique identifier of the RNG data request used on the Witnet Oracle blockchain for solving randomness.
    /// @dev Can be used to track all randomness requests solved on the Witnet Oracle blockchain.
    bytes32 immutable public override witnetRadHash;

    constructor(WitnetOracle _witnet)
        Ownable(address(msg.sender))
        UsingWitnet(_witnet)
    {
        require(
            address(_witnet) == address(0)
                || _witnet.specs() == type(IWitnetOracle).interfaceId,
            "WitnetRandomnessV2: uncompliant WitnetOracle"
        );
        WitnetRequestBytecodes _registry = witnet().registry();
        {
            // Build own Witnet Randomness Request:
            bytes32[] memory _retrievals = new bytes32[](1);
            _retrievals[0] = _registry.verifyRadonRetrieval(
                Witnet.RadonDataRequestMethods.RNG,
                "", // no request url
                "", // no request body
                new string[2][](0), // no request headers
                hex"80" // no request Radon script
            );
            Witnet.RadonFilter[] memory _filters;
            bytes32 _aggregator = _registry.verifyRadonReducer(Witnet.RadonReducer({
                opcode: Witnet.RadonReducerOpcodes.Mode,
                filters: _filters // no filters
            }));
            bytes32 _tally = _registry.verifyRadonReducer(Witnet.RadonReducer({
                opcode: Witnet.RadonReducerOpcodes.ConcatenateAndHash,
                filters: _filters // no filters
            }));
            witnetRadHash = _registry.verifyRadonRequest(
                _retrievals,
                _aggregator,
                _tally,
                32, // 256 bits of pure entropy ;-)
                new string[][](_retrievals.length)
            );
        }
    }

    receive() virtual external payable {
        revert(string(abi.encodePacked(
            class(),
            ": no transfers accepted"
        )));
    }

    fallback() virtual external payable { 
        revert(string(abi.encodePacked(
            class(),
            ": not implemented: 0x",
            Witnet.toHexString(uint8(bytes1(msg.sig))),
            Witnet.toHexString(uint8(bytes1(msg.sig << 8))),
            Witnet.toHexString(uint8(bytes1(msg.sig << 16))),
            Witnet.toHexString(uint8(bytes1(msg.sig << 24)))
        )));
    }

    function class() virtual override public pure returns (string memory) {
        return type(WitnetRandomnessV20).name;
    }

    function specs() virtual override external pure returns (bytes4) {
        return type(WitnetRandomness).interfaceId;
    }

    function witnet() override (IWitnetRandomness, UsingWitnet)
        public view returns (WitnetOracle)
    {
        return UsingWitnet.witnet();
    }

    
    /// ===============================================================================================================
    /// --- 'IWitnetRandomness' implementation ------------------------------------------------------------------------

    /// Returns amount of wei required to be paid as a fee when requesting randomization with a 
    /// transaction gas price as the one given.
    function estimateRandomizeFee(uint256 _evmGasPrice)
        public view
        virtual override
        returns (uint256)
    {
        return (
            (100 + __witnetBaseFeeOverheadPercentage)
                * __witnet.estimateBaseFee(
                    _evmGasPrice, 
                    witnetRadHash
                ) 
        ) / 100;
    }

    /// @notice Retrieves the randomness value generated by the Witnet Oracle blockchain in response to the 
    /// @notice first non-errored randomize request solved after the given block number.
    /// @dev Reverts if:
    /// @dev   i.   no `randomize()` was requested on neither the given block, nor afterwards.
    /// @dev   ii.  the first non-errored `randomize()` request found on or after the given block is not solved yet.
    /// @dev   iii. all `randomize()` requests that took place on or after the given block were solved with errors.
    /// @param _blockNumber Block number from which the search will start
    function fetchRandomnessAfter(uint256 _blockNumber)
        public view
        virtual override
        returns (bytes32)
    {
        Randomize storage __randomize = __storage().randomize_[_blockNumber];

        if (__randomize.witnetQueryId == 0) {
            _blockNumber = getRandomizeNextBlock(_blockNumber);
        }

        uint256 _witnetQueryId = __randomize.witnetQueryId;
        require(
            _witnetQueryId != 0, 
            "WitnetRandomness: not randomized"
        );
        
        WitnetV2.ResponseStatus _status = __witnet.getQueryResponseStatus(_witnetQueryId);
        if (_status == WitnetV2.ResponseStatus.Ready) {
            return (__witnet.getQueryResponse(_witnetQueryId)
                .resultCborBytes
                .toWitnetResult()
                .asBytes32()
            );
        } else if (_status == WitnetV2.ResponseStatus.Error) {
            uint256 _nextRandomizeBlock = __randomize.nextBlock;
            require(
                _nextRandomizeBlock != 0, 
                "WitnetRandomness: faulty randomize"
            );
            return fetchRandomnessAfter(_nextRandomizeBlock);
        
        } else {
            revert("WitnetRandomness: pending randomize");
        }
    }

    /// @notice Retrieves the unique hash and timestamp of the witnessing commit/reveal act that took
    /// @notice place in the Witnet Oracle blockchain in response to the first non-errored randomize request
    /// @notice solved after the given block number.
    /// @dev Reverts if:
    /// @dev   i.   no `randomize()` was requested on neither the given block, nor afterwards.
    /// @dev   ii.  the first non-errored `randomize()` request found on or after the given block is not solved yet.
    /// @dev   iii. all `randomize()` requests that took place on or after the given block were solved with errors.
    /// @param _blockNumber Block number from which the search will start.
    /// @return _witnetResultTimestamp Timestamp at which the randomness value was generated by the Witnet blockchain.
    /// @return _witnetResultTallyHash Hash of the witnessing commit/reveal act that took place on the Witnet blockchain.
    /// @return _witnetResultFinalityBlock EVM block number from which the provided randomness can be considered to be final.
    function fetchRandomnessAfterProof(uint256 _blockNumber) 
        virtual override
        public view 
        returns (
            uint64  _witnetResultTimestamp,
            bytes32 _witnetResultTallyHash,
            uint256 _witnetResultFinalityBlock
        )
    {
        Randomize storage __randomize = __storage().randomize_[_blockNumber];

        if (__randomize.witnetQueryId == 0) {
            _blockNumber = getRandomizeNextBlock(_blockNumber);
        }

        uint256 _witnetQueryId = __randomize.witnetQueryId;
        require(
            _witnetQueryId != 0, 
            "WitnetRandomness: not randomized"
        );
        
        WitnetV2.ResponseStatus _status = __witnet.getQueryResponseStatus(_witnetQueryId);
        if (_status == WitnetV2.ResponseStatus.Ready) {
            WitnetV2.Response memory _witnetQueryResponse = __witnet.getQueryResponse(_witnetQueryId);
            _witnetResultTimestamp = _witnetQueryResponse.resultTimestamp;
            _witnetResultTallyHash = _witnetQueryResponse.resultTallyHash;
            _witnetResultFinalityBlock = _witnetQueryResponse.finality;

        } else if (_status == WitnetV2.ResponseStatus.Error) {
            uint256 _nextRandomizeBlock = __randomize.nextBlock;
            require(
                _nextRandomizeBlock != 0, 
                "WitnetRandomness: faulty randomize"
            );
            return fetchRandomnessAfterProof(_nextRandomizeBlock);
        
        } else {
            revert("WitnetRandomness: pending randomize");
        }
    }

    /// @notice Returns last block number on which a randomize was requested.
    function getLastRandomizeBlock()
        virtual override
        external view
        returns (uint256)
    {
        return __storage().lastRandomizeBlock;
    }

    /// @notice Retrieves metadata related to the randomize request that got posted to the 
    /// @notice Witnet Oracle contract on the given block number.
    /// @dev Returns zero values if no randomize request was actually posted on the given block.
    /// @return _witnetQueryId Identifier of the underlying Witnet query created on the given block number. 
    /// @return _prevRandomizeBlock Block number in which a randomize request got posted just before this one. 0 if none.
    /// @return _nextRandomizeBlock Block number in which a randomize request got posted just after this one, 0 if none.
    function getRandomizeData(uint256 _blockNumber)
        external view
        virtual override
        returns (
            uint256 _witnetQueryId,
            uint256 _prevRandomizeBlock,
            uint256 _nextRandomizeBlock
        )
    {
        Randomize storage __randomize = __storage().randomize_[_blockNumber];
        _witnetQueryId = __randomize.witnetQueryId;
        _prevRandomizeBlock = __randomize.prevBlock;
        _nextRandomizeBlock = __randomize.nextBlock;
    }

    /// @notice Returns the number of the next block in which a randomize request was posted after the given one. 
    /// @param _blockNumber Block number from which the search will start.
    /// @return Number of the first block found after the given one, or `0` otherwise.
    function getRandomizeNextBlock(uint256 _blockNumber)
        public view
        virtual override
        returns (uint256)
    {
        return ((__storage().randomize_[_blockNumber].witnetQueryId != 0)
            ? __storage().randomize_[_blockNumber].nextBlock
            // start search from the latest block
            : _searchNextBlock(_blockNumber, __storage().lastRandomizeBlock)
        );
    }

    /// @notice Returns the number of the previous block in which a randomize request was posted before the given one.
    /// @param _blockNumber Block number from which the search will start. Cannot be zero.
    /// @return First block found before the given one, or `0` otherwise.
    function getRandomizePrevBlock(uint256 _blockNumber)
        public view
        virtual override
        returns (uint256)
    {
        assert(_blockNumber > 0);
        uint256 _latest = __storage().lastRandomizeBlock;
        return ((_blockNumber > _latest)
            ? _latest
            // start search from the latest block
            : _searchPrevBlock(_blockNumber, __storage().randomize_[_latest].prevBlock)
        );
    }

    /// @notice Returns status of the first non-errored randomize request posted on or after the given block number.
    /// @dev Possible values:
    /// @dev - 0 -> Void: no randomize request was actually posted on or after the given block number.
    /// @dev - 1 -> Awaiting: a randomize request was found but it's not yet solved by the Witnet blockchain.
    /// @dev - 2 -> Ready: a successfull randomize value was reported and ready to be read.
    /// @dev - 3 -> Error: all randomize requests after the given block were solved with errors.
    /// @dev - 4 -> Finalizing: a randomize resolution has been reported from the Witnet blockchain, but it's not yet final.  
    function getRandomizeStatus(uint256 _blockNumber)
        virtual override
        public view 
        returns (WitnetV2.ResponseStatus)
    {
        if (__storage().randomize_[_blockNumber].witnetQueryId == 0) {
            _blockNumber = getRandomizeNextBlock(_blockNumber);
        }
        uint256 _witnetQueryId = __storage().randomize_[_blockNumber].witnetQueryId;
        if (_witnetQueryId == 0) {
            return WitnetV2.ResponseStatus.Void;
        
        } else {
            WitnetV2.ResponseStatus _status = __witnet.getQueryResponseStatus(_witnetQueryId);
            if (_status == WitnetV2.ResponseStatus.Error) {
                uint256 _nextRandomizeBlock = __storage().randomize_[_blockNumber].nextBlock;
                if (_nextRandomizeBlock != 0) {
                    return getRandomizeStatus(_nextRandomizeBlock);
                } else {
                    return WitnetV2.ResponseStatus.Error;
                }
            } else {
                return _status;
            }
        }
    }

    /// @notice Returns `true` only if a successfull resolution from the Witnet blockchain is found for the first 
    /// @notice non-errored randomize request posted on or after the given block number.
    function isRandomized(uint256 _blockNumber)
        public view
        virtual override
        returns (bool)
    {
        return (
            getRandomizeStatus(_blockNumber) == WitnetV2.ResponseStatus.Ready
        );
    }

    /// @notice Generates a pseudo-random number uniformly distributed within the range [0 .. _range), by using 
    /// @notice the given `nonce` and the randomness returned by `getRandomnessAfter(blockNumber)`. 
    /// @dev Fails under same conditions as `getRandomnessAfter(uint256)` does.
    /// @param _range Range within which the uniformly-distributed random number will be generated.
    /// @param _nonce Nonce value enabling multiple random numbers from the same randomness value.
    /// @param _blockNumber Block number from which the search for the first randomize request solved aftewards will start.
    function random(uint32 _range, uint256 _nonce, uint256 _blockNumber)
        external view 
        virtual override
        returns (uint32)
    {
        return WitnetV2.randomUint32(
            _range,
            _nonce,
            keccak256(
                abi.encode(
                    msg.sender,
                    _blockNumber,
                    fetchRandomnessAfter(_blockNumber)
                )
            )
        );
    }

    /// @notice Requests the Witnet oracle to generate an EVM-agnostic and trustless source of randomness. 
    /// @dev Only one randomness request per block will be actually posted to the Witnet Oracle. 
    /// @return _witnetEvmReward Funds actually paid as randomize fee.
    function randomize()
        external payable
        virtual override
        returns (uint256 _witnetEvmReward)
    {
        if (__storage().lastRandomizeBlock < block.number) {
            _witnetEvmReward = msg.value;
            // Post the Witnet Randomness request:
            uint _witnetQueryId = __witnet.postRequest{
                value: _witnetEvmReward
            }(
                witnetRadHash,
                __witnetDefaultSLA  
            );
            // Keep Randomize data in storage:
            Randomize storage __randomize = __storage().randomize_[block.number];
            __randomize.witnetQueryId = _witnetQueryId;
            // Update block links:
            uint256 _prevBlock = __storage().lastRandomizeBlock;
            __randomize.prevBlock = _prevBlock;
            __storage().randomize_[_prevBlock].nextBlock = block.number;
            __storage().lastRandomizeBlock = block.number;
            // Throw event:
            emit Randomizing(
                block.number,
                tx.gasprice,
                _witnetQueryId,
                _witnetEvmReward
            );
        }
        // Transfer back unused funds:
        if (_witnetEvmReward < msg.value) {
            payable(msg.sender).transfer(msg.value - _witnetEvmReward);
        }
    }

    /// @notice Returns the SLA parameters required for the Witnet Oracle blockchain to fulfill 
    /// @notice when solving randomness requests:
    /// @notice - number of witnessing nodes contributing to randomness generation
    /// @notice - reward in $nanoWIT received by every contributing node in the Witnet blockchain
    function witnetQuerySLA() 
        virtual override
        external view
        returns (WitnetV2.RadonSLA memory)
    {
        return __witnetDefaultSLA;
    }


    /// ===============================================================================================================
    /// --- 'IWitnetRandomnessAdmin' implementation -------------------------------------------------------------------

    function acceptOwnership()
        virtual override (IWitnetRandomnessAdmin, Ownable2Step)
        public
    {
        Ownable2Step.acceptOwnership();
    }

    function baseFeeOverheadPercentage()
        virtual override
        external view 
        returns (uint16)
    {
        return __witnetBaseFeeOverheadPercentage;
    }

    function owner()
        virtual override (IWitnetRandomnessAdmin, Ownable)
        public view 
        returns (address)
    {
        return Ownable.owner();
    }

    function pendingOwner() 
        virtual override (IWitnetRandomnessAdmin, Ownable2Step)
        public view
        returns (address)
    {
        return Ownable2Step.pendingOwner();
    }
    
    function transferOwnership(address _newOwner)
        virtual override (IWitnetRandomnessAdmin, Ownable2Step)
        public 
        onlyOwner
    {
        Ownable.transferOwnership(_newOwner);
    }

    function settleBaseFeeOverheadPercentage(uint16 _baseFeeOverheadPercentage)
        virtual override
        external
        onlyOwner
    {
        __witnetBaseFeeOverheadPercentage = _baseFeeOverheadPercentage;
    }

    function settleWitnetQuerySLA(WitnetV2.RadonSLA calldata _witnetQuerySLA)
        virtual override
        external
        onlyOwner
    {
        require(
            _witnetQuerySLA.isValid(),
            "WitnetRandomness: invalid SLA"
        );
        __witnetDefaultSLA = _witnetQuerySLA;
    }


    // ================================================================================================================
    // --- Internal methods -------------------------------------------------------------------------------------------

    /// @dev Recursively searches for the number of the first block after the given one in which a Witnet 
    /// @dev randomness request was posted. Returns 0 if none found.
    function _searchNextBlock(uint256 _target, uint256 _latest) internal view returns (uint256) {
        return ((_target >= _latest) 
            ? __storage().randomize_[_latest].nextBlock
            : _searchNextBlock(_target, __storage().randomize_[_latest].prevBlock)
        );
    }

    /// @dev Recursively searches for the number of the first block before the given one in which a Witnet 
    /// @dev randomness request was posted. Returns 0 if none found.
    function _searchPrevBlock(uint256 _target, uint256 _latest) internal view returns (uint256) {
        return ((_target > _latest)
            ? _latest
            : _searchPrevBlock(_target, __storage().randomize_[_latest].prevBlock)
        );
    }

    function __storage() internal pure returns (Storage storage _ptr) {
        bytes32 _slothash = keccak256(bytes("io.witnet.apps.randomness.v20"));
        assembly {
            _ptr.slot := _slothash
        }
    }
}
