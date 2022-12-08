// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

/// @dev Core dependencies.
import {Generations} from "./Generations.sol";
import {Society} from "./Society.sol";

/// @dev Helper libraries.
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "hardhat/console.sol";

/**
 * @notice Posterity is a primitive that introduces localized ethical obligation to keep a society or
 *         networking growing. Lost knowledge and the erosion of mind-share has led to a global society
 *         in which every individual lacks direct impact on the continuation of the network.
 *         Posterity changes that.
 * @author @0x446576* | @nftchance+
 */
contract Posterity is Generations {
    //////////////////////////////////////////////////////////////
    ///                      CONSTRUCTOR                       ///
    //////////////////////////////////////////////////////////////

    constructor() Generations(Society(msg.sender).getSociety()) {}

    //////////////////////////////////////////////////////////////
    ///                        SETTERS                         ///
    //////////////////////////////////////////////////////////////

    /**
     * @dev Claim tokens for a set of merkle proofs.
     * @param _molecule The molecule of the proof.
     * @param _merkleProof The merkle proof.
     */
    function claim(address _molecule, bytes32[] calldata _merkleProof)
        external
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

        console.log("at the end of claim");
    }
}
