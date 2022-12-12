// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

/// @dev Core dependencies.
import {Auth} from "solmate/src/auth/Auth.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Helper libraries.
import {PRBMathSD59x18} from "prb-math/contracts/PRBMathSD59x18.sol";
import {Snapshot} from "./Snapshot.sol";

import "hardhat/console.sol";

contract Generations is Auth, ERC20 {
    using PRBMathSD59x18 for int256;

    //////////////////////////////////////////////////////////////
    ///                         STATE                          ///
    //////////////////////////////////////////////////////////////

    ///@dev Parameter that controls initial price, stored as a 59x18 fixed precision number
    int256 internal immutable initialPrice;

    ///@dev Parameter that controls price decay, stored as a 59x18 fixed precision number
    int256 internal immutable decayConstant;

    ///@dev Emission rate, in tokens per second, stored as a 59x18 fixed precision number
    int256 internal immutable emissionRate;

    ///@dev Start time for last available auction, stored as a 59x18 fixed precision number
    int256 internal latestBirth;

    /// @dev The active society epoch.
    uint32 public generationInterval;

    /// @dev Implement the use of a Merkle root to control minting.
    bytes32 public generationMerkleRoot;

    /// @dev The state of the generation the society the operates within.
    /// @dev The bitpacked targets value represents:
    /// @dev 0-31: The generational capacity for new members.
    /// @dev 32-63: The generational decay rate for members.
    /// @dev 64-95: The base knowledge loss rate on transfer.
    mapping(uint32 => uint96) public generation;

    /// @dev The state of the society running inside Posterity.
    /// @dev The nested uint maps to a bitpacked:
    ///      0-1: 0: Unseen, 1: Alive, 2: Dead
    ///      2-33: The timestamp of the last generation.
    mapping(uint32 => mapping(address => uint48)) public knowledge;

    //////////////////////////////////////////////////////////////
    ///                         EVENTS                         ///
    //////////////////////////////////////////////////////////////

    event GenerationSet(
        uint32 indexed generationInterval,
        uint96 generationConfiguration,
        bytes32 generationMerkleRoot
    );

    //////////////////////////////////////////////////////////////
    ///                      CONSTRUCTOR                       ///
    //////////////////////////////////////////////////////////////

    constructor(Snapshot.Society memory society)
        ERC20(society.name, society.symbol)
        Auth(society.deployer, society.authority)
    {
        /// @dev Set the initial price.
        initialPrice = society.initialPrice;

        /// @dev Set the decay constant.
        decayConstant = society.decayConstant;

        /// @dev Set the emission rate.
        emissionRate = society.emissionRate;

        /// @dev Set the last birth.
        latestBirth = int256(block.timestamp).fromInt();

        /// @dev Set the generation interval.
        setGeneration(
            1,
            society.generationConfiguration,
            society.generationMerkleRoot
        );
    }

    //////////////////////////////////////////////////////////////
    ///                        SETTERS                         ///
    //////////////////////////////////////////////////////////////

    /**
     * @notice Allows a society to roll into a new state.
     * @dev This is not really expected to be used by the owner, but rather by the society itself.
     * @param _generationInterval The new generation interval.
     * @param _generationConfiguration The new generation configuration.
     * @param _generationMerkleRoot The new generation merkle root for settlers.
     */
    function setGeneration(
        uint32 _generationInterval,
        uint96 _generationConfiguration,
        bytes32 _generationMerkleRoot
    ) public requiresAuth {
        /// @dev The generation interval must be taking society into the future.
        require(
            _generationInterval > generationInterval,
            "Generations::setGeneration: cannot undo what has already been done."
        );

        /// @dev Set the new generation interval.
        generationInterval = _generationInterval;

        /// @dev Set the new merkle root for settler claims.
        generationMerkleRoot = _generationMerkleRoot;

        /// @dev Uses an already bitpacked value to set the generation configuration.
        /// 01010101010101010101010101010101
        /// |<---------- 32 bits --------->|
        /// 11111111111111111111111111111111
        /// |<---------- 32 bits --------->|
        /// 00000000000000000000000000000000
        /// |<---------- 32 bits --------->|
        /// 0101010101|1111111111|0000000000
        /// |<- 32 -->||<- 32 -->||<- 32 ->|
        /// |<---------- 96 bits --------->|
        generation[_generationInterval] = _generationConfiguration;

        /// @dev Emit the event.
        emit GenerationSet(
            _generationInterval,
            _generationConfiguration,
            _generationMerkleRoot
        );
    }

    //////////////////////////////////////////////////////////////
    ///                        GETTERS                         ///
    //////////////////////////////////////////////////////////////

    /**
     * @notice Returns the birth capacity each member of a society
     *      has in a generation.
     * @param _generationInterval The generation interval.
     * @return The birth capacity of the queried generation.
     */
    function getGenerationCapacity(uint32 _generationInterval)
        public
        view
        virtual
        returns (uint32)
    {
        /// @dev Return the first 32 bits of the generation.
        /// 01010101010101010101010101010101
        /// |<---------- 32 bits --------->|
        /// 11111111111111111111111111111111
        /// |<---------- 32 bits --------->|
        /// 00000000000000000000000000000000
        /// |<---------- 32 bits --------->|
        /// 0101010101|1111111111|0000000000
        /// |<- 32 -->||<- 32 -->||<- 32 ->|
        /// 00000000000000000000000000000000
        /// |<---------- 32 bits --------->|
        return uint32(generation[_generationInterval]);
    }

    /**
     * @notice Returns the decay rate each member of a society
     *      has in a generation.
     * @param _generationInterval The generation interval.
     * @return The decay rate of the queried generation.
     */
    function getGenerationDecayRate(uint32 _generationInterval)
        public
        view
        virtual
        returns (uint32)
    {
        /// @dev Shift the decay rate to the right by 32 bits and trim to 32 bits.
        /// 01010101010101010101010101010101
        /// |<---------- 32 bits --------->|
        /// 11111111111111111111111111111111
        /// |<---------- 32 bits --------->|
        /// 00000000000000000000000000000000
        /// |<---------- 32 bits --------->|
        /// 0101010101|1111111111|0000000000
        /// |<- 32 -->||<- 32 -->||<- 32 ->|
        /// >> 64 --> 11111111111111111111111111111111
        ///           |<---------- 32 bits --------->|
        return uint32(generation[_generationInterval] >> 32);
    }

    function getGenerationBaseKnowledgeLossRate(uint32 _generationInterval)
        public
        view
        virtual
        returns (uint32 rate)
    {
        /// @dev Shift the decay rate to the right by 64 bits and trim to 32 bits.
        /// 01010101010101010101010101010101
        /// |<---------- 32 bits --------->|
        /// 11111111111111111111111111111111
        /// |<---------- 32 bits --------->|
        /// 00000000000000000000000000000000
        /// |<---------- 32 bits --------->|
        /// 0101010101|1111111111|0000000000
        /// |<- 32 -->||<- 32 -->||<- 32 ->|
        /// >> 64 --> 01010101010101010101010101010101
        ///           |<---------- 32 bits --------->|
        return uint32(generation[_generationInterval] >> 64);
    }

    /**
     * @notice Returns the state of a molecule in a generation.
     * @param _generationInterval The generation interval.
     * @param _molecule The society member to query.
     * @return The state of the queried society molecule.
     */
    function getState(uint32 _generationInterval, address _molecule)
        public
        view
        virtual
        returns (uint8)
    {
        /// @dev Return the first 2 bits of the knowledge fit into 8.
        return getState(_generationInterval, _molecule, 0, 0);
    }

    /**
     * @notice (Overloaded) Returns the state of a molecule in a generation.
     * @param _generationInterval The generation interval.
     * @param _molecule The society member to query.
     * @param _balance The balance of the society member.
     * @param _requiredBalance The required balance of the society member.
     * @return The state of the queried society molecule.
     */
    function getState(
        uint32 _generationInterval,
        address _molecule,
        uint256 _balance,
        uint256 _requiredBalance
    ) public view virtual returns (uint8) {
        /// @dev Mask the number with 0b11 (0x3) to get the first 2 bits.
        /// 11111111111111111111111111111111
        /// |<---------- 32 bits --------->|
        /// 01
        /// |<---------- 2 bits ---------->|
        /// 11111111111111111111111111111111|01
        /// |<---------- 32 bits ---------->|-| <-- 2 bits
        /// & 0x3 --> 01
        ///           || <-- 2 bits
        if (_balance < _requiredBalance) return 2;

        /// @dev Have to use a mask on this one because the stored value
        ///      is smaller than a uint8 and there are other values
        ///      stored back to back.
        return uint8(knowledge[_generationInterval][_molecule] & 0x3);
    }

    /**
     * @notice Returns the timestamp the molecule of a generation was last seen.
     * @param _generationInterval The generation interval.
     * @param _molecule The society member to query.
     * @return The timestamp of the last generation the molecule was seen in.
     */
    function getLastBalanced(uint32 _generationInterval, address _molecule)
        public
        view
        virtual
        returns (uint32)
    {
        /// @dev Shift the number 2 bits to the right and trim to 32 bits.
        /// 11111111111111111111111111111111
        /// |<---------- 32 bits --------->|
        /// 01
        /// |<---------- 2 bits ---------->|
        /// 11111111111111111111111111111111|01
        /// >> 2 --> 11111111111111111111111111111111
        ///          |<---------- 32 bits --------->|
        return uint32(knowledge[_generationInterval][_molecule] >> 2);
    }

    /**
     * @notice Returns the amount of knowledge that has been lost by a
     *         molecule since the last balance.
     * @param _molecule The society member to query.
     * @return decay The amount of knowledge lost by the molecule.
     */
    function getKnowledgeDecay(address _molecule)
        public
        view
        virtual
        returns (uint256 decay)
    {
        /// @dev Determine the amount of time that has passed since the last balance
        ///      and decay the knowledge accordingly.
        decay =
            (block.timestamp - getLastBalanced(generationInterval, _molecule)) /
            getGenerationDecayRate(generationInterval);
    }

    /**
     * @notice Returns the amount of knowledge that erodes when transferring
     *         the provided amount of knowledge.
     * @dev Implements the knowledge eroding function:
     *      $P(q)=\frac{k}{\lambda} \cdot \frac{e^{\frac{\lambda q}{r}}-1}{e^{\lambda T}}$
     * @param _amount The amount of knowledge to transfer.
     * @return erosion The amount of knowledge that erodes.
     */
    function getKnowledgeErosion(uint256 _amount)
        public
        view
        virtual
        returns (uint256 erosion)
    {
        /// @dev Convert the amount of knowledge to a fixed point number.
        int256 amount = int256(_amount).fromInt();

        /// @dev Determine the amount of time that has passed since the last birth.
        int256 timeSinceLastAuctionStart = int256(block.timestamp).fromInt() -
            latestBirth;

        /// @dev Calculate the left side of the equation.
        int256 num1 = initialPrice.div(decayConstant);

        /// @dev Calculate the right side of the equation.
        int256 num2 = decayConstant.mul(amount).div(emissionRate).exp() -
            PRBMathSD59x18.fromInt(1);

        /// @dev Find the point in the curve.
        int256 den = decayConstant.mul(timeSinceLastAuctionStart).exp();

        /// @dev Calculate the erosion.
        int256 totalCost = num1.mul(num2).div(den);

        /// @dev Return the dynamic cost of erosion + the societies fixed cost.
        erosion =
            uint256(totalCost) +
            getGenerationBaseKnowledgeLossRate(generationInterval);
    }

    //////////////////////////////////////////////////////////////
    ///                    INTERNAL SETTERS                    ///
    //////////////////////////////////////////////////////////////

    /**
     * @dev Handles the logic for a member to join the society.
     * @param _generationInterval The interval to join the society.
     * @param _molecule The member to join the society.
     * @param _state The state of the member.
     */
    function _setState(
        uint32 _generationInterval,
        address _molecule,
        uint8 _state
    ) internal {
        /// @dev Bitpack the new state and the already stored value of timestamp.
        /// 01010101010101010101010101010101
        /// |<--------- 32 bits ---------->|
        /// 11
        /// || <-- 2 bits
        /// << 2 --> 01010101010101010101010101010101|00
        ///          |<---------- 32 bits ---------->|-| <-- 2 bits
        /// | --> 01010101010101010101010101010101|11
        ///       |<--------- 32 bits ----------->|-| <-- 2 bits
        /// 0101010101010101010101010101010111
        /// |<---------- 34 bits ----------->|
        knowledge[_generationInterval][_molecule] = uint48(
            _state | (getLastBalanced(_generationInterval, _molecule) << 2)
        );
    }

    /**
     * @dev Manages the balanced date of a member to keep the society running.
     * @param _generationInterval The interval to join the society.
     * @param _molecule The member to join the society.
     */
    function _setLastBalanced(uint32 _generationInterval, address _molecule)
        internal
    {
        /// @dev Keep the already stored state and update the timestamp.
        /// 01010101010101010101010101010101
        /// |<--------- 32 bits ---------->|
        /// 11
        /// || <-- 2 bits
        /// << 2 --> 01010101010101010101010101010101|00
        ///          |<---------- 32 bits ---------->|-| <-- 2 bits
        /// | --> 01010101010101010101010101010101|11
        ///       |<--------- 32 bits ----------->|-| <-- 2 bits
        /// 0101010101010101010101010101010111
        /// |<---------- 34 bits ----------->|
        knowledge[_generationInterval][_molecule] = uint48(
            getState(_generationInterval, _molecule) | (block.timestamp << 2)
        );
    }

    //////////////////////////////////////////////////////////////
    ///                     INTERNAL SETTERS                   ///
    //////////////////////////////////////////////////////////////

    /**
     * @dev Manages the knowledge transfer between members of society.
     * @param _from The member to transfer knowledge from.
     * @param _amount The amount of knowledge to transfer.
     */
    function _setKnowledge(address _from, uint256 _amount)
        internal
        virtual
        returns (uint256 cost)
    {
        /// @dev Move the value in a cheaper access pattern.
        uint256 balance = balanceOf(_from);

        /// @dev In all situations, the sender needs to have their knowledge balanced.
        uint256 decay = getKnowledgeDecay(_from);

        require(
            balance >= decay,
            "Generations::_setKnowledge: The sender has perished."
        );

        /// @dev Calculate the remaining knowledge after the transfer.
        uint256 remaining = balance - decay;

        /// @dev Require that only 1 or the full balance may be transferred.
        /// @notice Implementation of the 1% rule for knowledge transfer and growth.
        /// @notice The ideal implementation of philosphy was forgone in favor of a more
        ///         chain-focused solution that still allows for key rotation.
        require(
            _amount == 1 || _amount == remaining,
            "Generations::_setKnowledge: Only a shard or all of the knowledge may be transferred."
        );

        /// @dev If the amount being transferred is the total balance, there is no cost to
        ///      expand the network (loss of knowledge) with complete passthrough of the transfer.
        /// @notice Accounts for the traditional forms of knowledge erosion that naturally occur.
        cost = _amount == remaining ? 0 : getKnowledgeErosion(_amount);

        console.log("cost", cost);    

        if (cost != 0) {
            console.log("latestBirth", uint256(latestBirth));

            /// @dev Number of seconds of token emissions that are available to be purchased.
            int256 secondsOfEmissionsAvaiable = int256(block.timestamp)
                .fromInt() - latestBirth;

            /// @dev The number of seconds of emissions are being purchased.
            int256 secondsOfEmissionsToPurchase = int256(_amount).fromInt().div(
                emissionRate
            );

            console.log(
                "secondsOfEmissionsAvaiable",
                uint256(secondsOfEmissionsAvaiable)
            );
            console.log(
                "secondsOfEmissionsToPurchase",
                uint256(secondsOfEmissionsToPurchase)
            );

            /// @dev Ensure that the requested amount of seconds do not exceed the amount passed.
            require(
                secondsOfEmissionsAvaiable >= secondsOfEmissionsToPurchase,
                "Generations::_beforeTokenTransfer: Not enough knowledge capacity in ecosystem."
            );

            /// @dev Record the most recent time of birth.
            latestBirth += secondsOfEmissionsToPurchase;

            console.log("latestBirth", uint256(latestBirth));
        }

        /// @dev Handle the lost knowledge from the transfer if any.
        if (decay + cost > 0) {
            /// @dev Require the sender has enough knowledge to transfer.
            /// @notice This will force a large number of transactions to be in a "revert-state"
            ///         given a long enough horizon. This is an intentional design decision and is
            ///         the precise mechanism that prevents the network from being flooded with
            ///         knowledge (and thus, mind-share leeched from the network).
            /// @dev If this is a bug to you, you are not thinking about the problem correctly.
            require(
                remaining >= _amount + cost,
                "Generations::_setKnowledge: Too much knowledge to transfer."
            );

            /// @dev Update the decay of the held knowledge before any transfer can take place.
            _setLastBalanced(generationInterval, _from);

            /// @dev Update the state after decay of the held knowledge before any
            ///      transfer can take place.
            _burn(_from, decay + cost);
        }

        /// @dev Record the death of society members (and their knowledge and mind-share) if
        ///      the transfer concludes the emission of knowledge share.
        _setState(
            generationInterval,
            _from,
            _amount == balance - decay
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
        /// @dev If the transfer is a burn, don't run anything else.
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
                /// @dev Require that the knowledge transfer can only be performed once per interval.
                require(
                    getState(
                        generationInterval,
                        _to,
                        balance,
                        balance == 0 ? 0 : getKnowledgeDecay(_to)
                    ) < 2,
                    "Generations::_knowledgeTransfer: Cannot house knowledge in a carcass."
                );

                /// @dev Handle the transfer of knowledge and mind-share.
                _setKnowledge(_from, _amount);
            }

            /// @dev Handle the seeding of a new molecule.
            if (_amount == 1) {
                /// @dev Mint the new knowledge and mind-share.
                _mint(_to, getGenerationCapacity(generationInterval));
            }
        }
    }
}
