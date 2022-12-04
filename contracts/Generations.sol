// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Generations is Ownable {
    //////////////////////////////////////////////////////////////
    ///                         STATE                          ///
    //////////////////////////////////////////////////////////////

    /// @dev The active society epoch.
    uint32 public generationInterval;

    /// @dev The state of the generation the society the operates within.
    /// @dev The bitpacked targets value represents:
    /// @dev 0-31: The generational capacity for new members.
    /// @dev 32-63: The generational decay rate for members.
    mapping(uint32 => uint64) public generation;

    /// @dev The state of the society running inside Posterity.
    /// @dev The nested uint maps to a bitpacked:
    ///      0-1: 0: Unseen, 1: Alive, 2: Dead
    ///      2-33: The timestamp of the last generation.
    mapping(uint32 => mapping(address => uint256)) public knowledge;

    // Implement the use of a Merkle root to control minting.
    bytes32 public merkleRoot;

    //////////////////////////////////////////////////////////////
    ///                        SETTERS                         ///
    //////////////////////////////////////////////////////////////

    /**
     * @dev Allows a society to roll into a new state.
     * @notice This is not really expected to be used by the owner, but rather by the society itself.
     * @param _generationInterval The new generation interval.
     * @param _generationCapacity The new generation capacity.
     * @param _generationDecayRate The new generation decay rate.
     */
    function setGeneration(
        uint32 _generationInterval,
        uint64 _generationCapacity,
        uint64 _generationDecayRate,
        bytes32 _merkleRoot
    ) public onlyOwner {
        /// @dev The generation interval must be taking society into the future.
        require(
            _generationInterval > generationInterval,
            "Posterity::setGeneration: cannot undo what has already been done."
        );

        /// @dev Set the details of the new generation.
        generation[_generationInterval] =
            _generationCapacity |
            (_generationDecayRate << 32);

        /// @dev Set the new generation interval.
        generationInterval = _generationInterval;

        /// @dev Set the new merkle root.
        merkleRoot = _merkleRoot;
    }

    /**
     * @dev Handles the logic for a member to join the society.
     * @param _interval The interval to join the society.
     * @param _molecule The member to join the society.
     * @param _state The state of the member.
     */
    function _setState(
        uint32 _interval,
        address _molecule,
        uint8 _state
    ) internal {
        /// @dev Set the first 2 bits to the state while keeping the following 32 bits intact.
        knowledge[_interval][_molecule] =
            (knowledge[_interval][_molecule] & 0xFFFFFFFC) |
            _state;
    }

    /**
     * @dev Manages the balanced date of a member to keep the society running.
     * @param _interval The interval to join the society.
     * @param _molecule The member to join the society.
     */
    function _setLastBalanced(uint32 _interval, address _molecule) internal {
        /// @dev Set the last 32 bits to the current block number while keeping the first 2 bits intact.
        knowledge[_interval][_molecule] =
            (knowledge[_interval][_molecule] & 0x3) |
            (block.timestamp << 2);
    }

    //////////////////////////////////////////////////////////////
    ///                        GETTERS                         ///
    //////////////////////////////////////////////////////////////

    function getGenerationCapacity(uint32 _interval)
        public
        view
        virtual
        returns (uint32)
    {
        return uint32(generation[_interval]);
    }

    function getGenerationDecayRate(uint32 _interval)
        public
        view
        virtual
        returns (uint32)
    {
        return uint32(generation[_interval] >> 32);
    }

    function getState(uint32 _interval, address _molecule)
        public
        view
        virtual
        returns (uint256)
    {
        /// @dev Get the first 2 bits from the bitpacked uint.
        return knowledge[_interval][_molecule] & 0x3;
    }

    function getLastBalanced(uint32 _interval, address _molecule)
        internal
        view
        returns (uint256)
    {
        /// @dev Get the last 32 bits from the bitpacked uint.
        return (knowledge[_interval][_molecule] & 0xfffffffffffffffc) >> 32;
    }

    function getKnowledgeDecay(address _molecule)
        public
        view
        virtual
        returns (uint256 decay)
    {
        /// @dev Get the decay rate of the current generation.
        decay =
            (block.timestamp - getLastBalanced(generationInterval, _molecule)) /
            getGenerationDecayRate(generationInterval);
    }

    function getKnowledgeErosion(uint256 _amount)
        public
        view
        virtual
        returns (uint256)
    {
        _amount;

        return 0;
    }
}
