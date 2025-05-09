// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MixerMerkleRoot
 * @dev A contract that allows users to deposit ETH and uses per-deposit Merkle proofs to verify withdrawals
 * Uses role-based access control for different permission levels
 */
contract MixerMerkleRoot is AccessControl, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    // Define role identifiers
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Maximum fee is 10% (1000 basis points)
    uint256 public constant MAX_FEE = 1000;

    address public feeRecipient;

    struct Deposit {
        bytes32 depositId; // merkle root
        address user;
        uint256 amount;
    }

    // Withdrawal tracking - depositId => user => releaseTime => withdrawn
    mapping(bytes32 => mapping(address => mapping(uint256 => bool)))
        private hasWithdrawn;

    mapping(bytes32 => Deposit) private deposits;
    EnumerableSet.Bytes32Set private depositIndex;
    uint256 public fee = 100; // 1% fee (in basis points, 10000 = 100%)
    bool public paused = false;

    // Events
    event DepositCreated(
        bytes32 indexed depositId,
        address indexed user,
        uint256 amount
    );
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(
        address indexed oldRecipient,
        address indexed newRecipient
    );
    event MerkleRootUpdated(
        bytes32 indexed depositId,
        bytes32 oldRoot,
        bytes32 newRoot
    );
    event EtherTransferred(
        bytes32 indexed depositId,
        address indexed user,
        uint256 amount,
        uint256 releaseTime
    );
    event EmergencyPause(bool isPaused);
    event WithdrawalExecuted(
        bytes32 indexed depositId,
        address indexed user,
        uint256 amount,
        uint256 releaseTime
    );
    event DepositDeleted(bytes32 indexed depositId);

    /**
     * @dev Modifier to check if the contract is not paused
     */
    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    /**
     * @dev Constructor that sets up initial roles
     * @param admin Address to be granted ADMIN_ROLE
     */
    constructor(address admin) {
        require(admin != address(0), "Admin cannot be zero address");

        // Set up the deployer as the owner and default admin
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, admin);

        feeRecipient = msg.sender; // Set the fee recipient to the contract deployer
    }

    /**
     * @dev Returns the current fee in basis points
     */
    function getFee() external view returns (uint256) {
        return fee;
    }

    /**
     * @dev Returns the total number of deposits
     */
    function totalDeposits() external view returns (uint256) {
        return depositIndex.length();
    }

    /**
     * @dev Returns the deposit ID at the specified index
     * @param index The index to query
     */
    function getDepositIdAt(uint256 index) external view returns (bytes32) {
        require(index < depositIndex.length(), "Index out of bounds");
        return depositIndex.at(index);
    }

    /**
     * @dev Gets deposit details by deposit ID
     * @param depositId The deposit ID to query
     */
    function getDeposit(
        bytes32 depositId
    ) external view returns (Deposit memory) {
        require(
            depositIndex.contains(depositId),
            "Query for nonexistent deposit"
        );
        return deposits[depositId];
    }

    /**
     * @dev Allows a user to deposit ETH with a Merkle root
     * @param depositId The Merkle root containing user/amount/releaseTime data
     */
    function deposit(
        bytes32 depositId
    ) external payable nonReentrant whenNotPaused {
        require(msg.value > 0, "Deposit amount must be greater than zero");
        require(depositId != bytes32(0), "Invalid Merkle root");

        // Check if depositId already exists
        require(!depositIndex.contains(depositId), "Deposit ID already exists");

        // Calculate fee
        uint256 feeAmount = (msg.value * fee) / 10000;
        uint256 netAmount = msg.value - feeAmount;

        // Store the net deposit amount after fee and the Merkle root
        deposits[depositId] = Deposit(depositId, msg.sender, netAmount);
        depositIndex.add(depositId);

        // Emit event before external calls (Checks-Effects-Interactions pattern)
        emit DepositCreated(depositId, msg.sender, netAmount);

        // Transfer the fee to the fee recipient
        (bool feeTransferSuccess, ) = address(feeRecipient).call{
            value: feeAmount
        }("");
        require(feeTransferSuccess, "Fee transfer failed");
    }

    /**
     * @dev Checks if a withdrawal has already been made
     * @param depositId The deposit to check
     * @param user The user address to check
     * @param releaseTime The release time that identifies this withdrawal opportunity
     */
    function hasUserWithdrawn(
        bytes32 depositId,
        address user,
        uint256 releaseTime
    ) external view returns (bool) {
        return hasWithdrawn[depositId][user][releaseTime];
    }

    /**
     * @dev Checks if a withdrawal can be made
     * @param depositId The deposit ID to check
     * @param recipient The recipient address
     * @param amount The amount to withdraw
     * @param releaseTime The release time for the withdrawal
     * @param merkleProof The Merkle proof to verify the withdrawal
     */
    function shouldTransferEther(
        bytes32 depositId,
        address recipient,
        uint256 amount,
        uint256 releaseTime,
        bytes32[] calldata merkleProof
    ) external view returns (bool) {
        require(depositIndex.contains(depositId), "Deposit ID does not exist");
        Deposit storage userDeposit = deposits[depositId];

        // Verify the merkle proof
        bytes32 leaf = keccak256(
            abi.encodePacked(recipient, amount, releaseTime)
        );
        require(
            MerkleProof.verify(merkleProof, userDeposit.depositId, leaf),
            "Invalid merkle proof"
        );

        // Check if already withdrawn
        require(
            !hasWithdrawn[depositId][recipient][releaseTime],
            "Already withdrawn"
        );
        // Check the release time has been reached
        require(
            releaseTime <= block.timestamp,
            "Release time not reached"
        );
        // Check sufficient funds in the deposit
        require(
            userDeposit.amount >= amount,
            "Insufficient deposit amount"
        );
        
        return true;
    }

    /**
     * @dev Allows an admin to transfer ETH from the contract
     * @param depositId The ID of the deposit to transfer from
     * @param recipient The address to send ETH to
     * @param amount The amount of ETH to send
     * @param releaseTime The release time for the withdrawal
     * @param merkleProof The Merkle proof to verify the withdrawal
     */
    function transferEther(
        bytes32 depositId,
        address payable recipient,
        uint256 amount,
        uint256 releaseTime,
        bytes32[] calldata merkleProof
    ) external onlyRole(ADMIN_ROLE) nonReentrant whenNotPaused {
        require(depositIndex.contains(depositId), "Deposit ID does not exist");
        Deposit storage userDeposit = deposits[depositId];

        bool shouldTransfer = this.shouldTransferEther(
            depositId,
            recipient,
            amount,
            releaseTime,
            merkleProof
        );
        require(shouldTransfer, "Invalid withdrawal conditions");

        // Mark as withdrawn before external call (Checks-Effects-Interactions pattern)
        hasWithdrawn[depositId][recipient][releaseTime] = true;

        // Update deposit amount
        uint256 newAmount = userDeposit.amount - amount;
        if (newAmount == 0) {
            delete deposits[depositId];
            depositIndex.remove(depositId);
            emit DepositDeleted(depositId);
        } else {
            userDeposit.amount = newAmount;
        }

        // Emit event after state changes but before external call
        emit EtherTransferred(depositId, recipient, amount, releaseTime);

        // Transfer funds
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Transfer failed");
    }

    /**
     * @dev Allows the owner to withdraw a deposit in emergency situations
     * @param depositId The ID of the deposit to withdraw
     */
    function emergencyWithdrawToUser(
        bytes32 depositId
    ) external onlyRole(OWNER_ROLE) nonReentrant {
        require(depositIndex.contains(depositId), "Deposit ID does not exist");

        Deposit memory userDeposit = deposits[depositId];
        require(userDeposit.user != address(0), "Deposit not found");

        uint256 amount = userDeposit.amount;
        address user = userDeposit.user;

        // Strictly follow Checks-Effects-Interactions pattern
        delete deposits[depositId];
        depositIndex.remove(depositId);

        emit WithdrawalExecuted(depositId, user, amount, 0);
        emit DepositDeleted(depositId);

        (bool success, ) = user.call{value: amount}("");
        require(success, "Transfer failed");
    }

    /**
     * @dev Allows the owner to withdraw a deposit in emergency situations
     * @param depositId The ID of the deposit to withdraw
     */
    function deleteDeposit(
        bytes32 depositId
    ) external onlyRole(OWNER_ROLE) nonReentrant {
        require(depositIndex.contains(depositId), "Deposit ID does not exist");

        // Strictly follow Checks-Effects-Interactions pattern
        delete deposits[depositId];
        depositIndex.remove(depositId);
        emit DepositDeleted(depositId);
    }

    /**
     * @dev Allows the owner to set the fee recipient
     * @param token The ERC20 token to recover
     * @param to The address to send the recovered tokens to
     */
    function recoverERC20(
        IERC20 token,
        address to
    ) external onlyRole(OWNER_ROLE) {
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No tokens");
        token.transfer(to, balance);
    }

    /**
     * @dev Allows the owner to set the fee recipient
     * @param to The address to send the recovered eth to
     * @param amount The amount of ETH to recover
     */
    function recoverEth(
        address to,
        uint256 amount
    ) external onlyRole(OWNER_ROLE) {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH");
        require(amount <= balance, "Amount exceeds balance");
        (bool success, ) = to.call{value: balance}("");
        require(success, "Transfer failed");
    }

    /**
     * @dev Allows the owner to set the fee percentage
     * @param newFee The new fee in basis points (100 = 1%)
     */
    function setFee(uint256 newFee) external onlyRole(OWNER_ROLE) {
        require(newFee > 0, "Fee must be greater than zero");
        require(newFee <= MAX_FEE, "Fee cannot exceed maximum (10%)");

        // Save the old fee before updating
        uint256 oldFee = fee;
        fee = newFee;

        // Use old and new fee in the event
        emit FeeUpdated(oldFee, newFee);
    }

    /**
     * @dev Allows the owner to set the fee recipient
     * @param newFeeRecipient The new fee recipient address
     */
    function setFeeRecipient(
        address newFeeRecipient
    ) external onlyRole(OWNER_ROLE) {
        require(newFeeRecipient != address(0), "Invalid fee recipient");

        // Save the old fee recipient before updating
        address oldFeeRecipient = feeRecipient;
        feeRecipient = newFeeRecipient;

        // Use old and new fee recipients in the event
        emit FeeRecipientUpdated(oldFeeRecipient, newFeeRecipient);
    }

    /**
     * @dev Toggles the paused state of the contract
     * @param _paused The new paused state
     */
    function setPaused(bool _paused) external onlyRole(OWNER_ROLE) {
        paused = _paused;
        emit EmergencyPause(_paused);
    }

    /**
     * @dev Allows the contract to receive ETH
     */
    receive() external payable {}

    /**
     * @dev Fallback function
     */
    fallback() external payable {}
}
