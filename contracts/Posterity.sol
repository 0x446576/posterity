// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {Generations} from "./Generations.sol";

/**
 * @notice Posterity is an abstract that provides a mechanism implements local societal obligation to keep the
 *         networking growing. Lost knowledge and the erosion of mind-share has led to a global society in which
 *         every individual lacks directly impact on the continuation of the network. Posterity is a mechanism that
 *         allows individuals to directly impact the continuation of the network by providing a mechanism to
 *         incentivize the continuation of the network.
 * @author @0x446575* | @nftchance+
 */
contract Posterity is ERC20, Generations {
    //////////////////////////////////////////////////////////////
    ///                      CONSTRUCTOR                       ///
    //////////////////////////////////////////////////////////////

    constructor(
        string memory _name,
        string memory _symbol,
        uint32 _generationCapacity,
        uint32 _generationDecayRate,
        bytes32 _merkleRoot
    ) ERC20(_name, _symbol) {
        setGeneration(
            1,
            _generationCapacity,
            _generationDecayRate,
            _merkleRoot
        );
    }

    //////////////////////////////////////////////////////////////
    ///                        SETTERS                         ///
    //////////////////////////////////////////////////////////////

    /**
     * @notice Claim tokens for a set of merkle proofs.
     * @param _molecule The molecule of the proof.
     * @param _merkleProof The merkle proof.
     */
    function claim(address _molecule, bytes32[] calldata _merkleProof)
        public
        virtual
    {
        /// @dev The molecule must be a valid address.
        require(
            getState(generationInterval, _molecule) == 0,
            "Posterity::claim: molecule is already alive."
        );

        /// @dev Require that the claim is valid.
        require(
            MerkleProof.verify(
                _merkleProof,
                merkleRoot,
                keccak256(abi.encodePacked(_molecule))
            ),
            "Posterity::claim: Invalid proof of permission to settle."
        );

        /// @dev Mint the capacity for new knowledge and mind-share.
        _mint(_molecule, getGenerationCapacity(generationInterval));
    }

    /**
     * @notice Burn tokens for a participant.
     * @dev Decay is not calculated prior to the burn, so the decay is not
     *      included in the burn.
     * @param _amount The amount of tokens to burn.
     */
    function burn(uint256 _amount) public virtual {
        _burn(_msgSender(), _amount);
    }

    //////////////////////////////////////////////////////////////
    ///                     INTERNAL SETTERS                   ///
    //////////////////////////////////////////////////////////////

    /**
     * @dev Manages the knowledge transfer between members of society.
     * @param _from The member to transfer knowledge from.
     * @param _to The member to transfer knowledge to.
     * @param _amount The amount of knowledge to transfer.
     */
    function _setKnowledge(
        address _from,
        address _to,
        uint256 _amount
    ) internal virtual {
        /// @dev Require that the knowledge transfer can only be performed once per interval.
        require(
            getState(generationInterval, _to) < 2,
            "Posterity::_knowledgeTransfer: Cannot house knowledge in a carcass."
        );

        /// @dev Move the value in a cheaper access pattern.
        uint256 balance = balanceOf(_from);

        /// @dev Require that only 1 or the full balance may be transferred.
        /// @notice Implementation of the 1% rule for knowledge transfer and growth.
        require(
            _amount == 1 || _amount == balance,
            "Posterity::_knowledgeTransfer: Only a shard or all of the knowledge may be transferred."
        );

        /// @dev In all situations, the sender needs to have their knowledge balanced.
        uint256 decay = getKnowledgeDecay(_from);

        /// @dev If the amount being transferred is the total balance, there is no cost to
        ///      expand the network (loss of knowledge) with complete passthrough of the transfer.
        /// @notice Accounts for the traditional forms of knowledge erosion that naturally occur.
        uint256 cost = _amount == balance ? 0 : getKnowledgeErosion(_amount);

        if (decay + cost > 0) {
            /// @dev Update the decay of the held knowledge before any transfer can take place.
            _setLastBalanced(generationInterval, _from);

            /// @dev Update the state after decay of the held knowledge before any
            ///      transfer can take place.
            unchecked {
                balance -= cost + decay;
            }

            /// @dev Update the decay of the recipient.
            emit Transfer(_from, address(0), decay + cost);
        }

        /// @dev Handle the seeding of a new molecule.
        if (_amount == 1) {
            /// @dev Mint the new knowledge and mind-share.
            _mint(_to, getGenerationCapacity(generationInterval));
        }

        /// @dev Determine if the transfer is a shard or a full piece of knowledge and enforce
        ///      the appropriate type of participant death.
        uint256 generationalDeath = _amount == balance ? 0 : 1;

        /// @dev Record the death of society members (and their knowledge and mind-share) if
        ///      the transfer concludes the emission of knowledge share.
        _setState(
            generationInterval,
            _from,
            balance == generationalDeath ? 2 : 1
        );
    }

    /**
     * @notice Makes sure that when the knowledge is does not have an omniscent party,
     *         the knowledge is balanced.
     * @param _from The member to transfer knowledge from.
     * @param _to The member to transfer knowledge to.
     * @param _amount The amount of knowledge to transfer.
     */
    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal virtual override {
        /// @dev Determine if the knowledge is not associated with the zero address.
        if (_from != address(0)) {
            /// @dev Handle the transfer of knowledge and mind-share.
            _setKnowledge(_from, _to, _amount);
        }

        /// @dev Handle the transfer of knowledge and mind-share.
        uint256 balance = balanceOf(_to);

        /// @dev Record the birth of society members if the transfer seeds a new generation.
        _setState(generationInterval, _to, balance == 0 ? 1 : 0);
    }
}
