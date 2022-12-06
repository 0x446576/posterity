// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Generations} from "./Generations.sol";
import {PRBMathSD59x18} from "prb-math/contracts/PRBMathSD59x18.sol";

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @notice Posterity is an abstract that provides a mechanism implements local societal obligation to keep the
 *         networking growing. Lost knowledge and the erosion of mind-share has led to a global society in which
 *         every individual lacks directly impact on the continuation of the network. Posterity is a mechanism that
 *         allows individuals to directly impact the continuation of the network by providing a mechanism to
 *         incentivize the continuation of the network.
 * @author @0x446576* | @nftchance+
 */
contract Posterity is ERC20, Generations {
    using PRBMathSD59x18 for int256;

    //////////////////////////////////////////////////////////////
    ///                      CONSTRUCTOR                       ///
    //////////////////////////////////////////////////////////////

    constructor(
        string memory _name,
        string memory _symbol,
        int256 _initialPrice,
        int256 _decayConstant,
        int256 _emissionRate,
        uint96 _generationConfiguration,
        bytes32 _merkleRoot
    )
        ERC20(_name, _symbol)
        Generations(
            _initialPrice,
            _decayConstant,
            _emissionRate,
            _generationConfiguration,
            _merkleRoot
        )
    {}

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
                generationMerkleRoot,
                keccak256(abi.encodePacked(_molecule))
            ),
            "Posterity::claim: Invalid proof of permission to settle."
        );

        /// @dev Mint the capacity for new knowledge and mind-share.
        _mint(_molecule, 1);
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
    ) internal virtual returns (uint256 cost) {
        /// @dev Move the value in a cheaper access pattern.
        uint256 balance = balanceOf(_to);

        /// @dev Require that the knowledge transfer can only be performed once per interval.
        require(
            getState(
                generationInterval,
                _to,
                balance,
                balance == 0 ? 0 : getKnowledgeDecay(_to)
            ) < 2,
            "Posterity::_knowledgeTransfer: Cannot house knowledge in a carcass."
        );

        /// @dev Move the value in a cheaper access pattern.
        balance = balanceOf(_from);

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
        cost = _amount == balance ? 0 : getKnowledgeErosion(_amount);

        if (decay + cost > 0) {
            require(
                balance >= _amount + decay + cost,
                "Posterity::_setKnowledge: too much knowledge to transfer."
            );

            /// @dev Update the decay of the held knowledge before any transfer can take place.
            _setLastBalanced(generationInterval, _from);

            /// @dev Update the state after decay of the held knowledge before any
            ///      transfer can take place.
            _burn(_from, decay + cost);

            /// @dev Update the decay of the recipient.
            emit Transfer(_from, address(0), decay + cost);
        }

        /// @dev Record the death of society members (and their knowledge and mind-share) if
        ///      the transfer concludes the emission of knowledge share.
        _setState(
            generationInterval,
            _from,
            _amount == balance
                ? 2
                : getState(
                    generationInterval,
                    _from,
                    balance,
                    _amount + decay + cost
                )
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
        if (_to != address(0)) {
            /// @dev Handle the transfer of knowledge and mind-share.
            uint256 balance = balanceOf(_to);

            /// @dev Record the birth of society members if the transfer seeds a new generation.
            _setState(
                generationInterval,
                _to,
                balance == 0
                    ? 1
                    : getState(
                        generationInterval,
                        _to,
                        balance,
                        getKnowledgeDecay(_to)
                    )
            );

            /// @dev If the transfer is not a mint, update the senders knowledge state.
            if (_from != address(0)) {
                /// @dev Handle the transfer of knowledge and mind-share.
                _setKnowledge(_from, _to, _amount);
            }

            /// @dev Handle the seeding of a new molecule.
            if (_amount == 1) {
                /// @dev number of seconds of token emissions that are available to be purchased.
                int256 secondsOfEmissionsAvaiable = int256(block.timestamp)
                    .fromInt() - lastBirth;

                /// @dev The number of seconds of emissions are being purchased.
                int256 secondsOfEmissionsToPurchase = int256(_amount)
                    .fromInt()
                    .div(emissionRate);

                /// @dev Ensure that the requested amount of seconds do not exceed the amount passed.
                require(
                    secondsOfEmissionsAvaiable >= secondsOfEmissionsToPurchase,
                    "Posterity::_beforeTokenTransfer: Not enough emissions available to purchase."
                );

                /// @dev Mint the new knowledge and mind-share.
                _mint(_to, getGenerationCapacity(generationInterval));

                /// @dev Record the most recent time of birth.
                lastBirth += secondsOfEmissionsToPurchase;
            }
        }
    }
}
