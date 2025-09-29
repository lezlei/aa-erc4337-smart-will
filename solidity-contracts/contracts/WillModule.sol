// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import "./interfaces/ISafe.sol";
import "./interfaces/ISafeProxyFactory.sol";

contract WillModule {
    // Variables
    mapping(address => Will) willData;

    struct Will {
        uint256 lastPing; // The timestamp of the last "I'm alive" signal
        uint256 timeout; // Length of time after lastPing for beneficiaries to be able to claim
        mapping(bytes32 => uint256) inheritances; // Mapping of beneficiary ID to their inheritance amount
        bytes32[] beneficiaryList; // List of beneficiaries
    }

    // Errors
    error WillNotFound(address owner);
    error BeneficiaryExists(bytes32 beneficiary);
    error BeneficiaryNotFound(bytes32 beneficiary);
    error TimeoutNotExpired(uint256 unlockTime);
    error NothingToClaim();
    error NoValueSent();
    error UnviableAmount();
    error TimeoutMustBeMoreThan0();
    error WillAlreadyExists();

    // --- Events ---
    event WillCreated(address indexed owner, uint256 timeout);
    event Ping(address indexed owner);
    event BeneficiaryAdded(address indexed owner, bytes32 indexed beneficiary, uint256 amount);
    event BeneficiaryUpdated(address indexed owner, bytes32 indexed beneficiary, uint256 newAmount);
    event BeneficiaryRemoved(address indexed owner, bytes32 indexed beneficiary);
    event InheritanceClaimed(address indexed owner, bytes32 indexed beneficiary, address newSafe, uint256 amount);

    /**
     * @notice Creates a will for the calling Safe account.
     * @dev Can only be called once per Safe. The caller must be the Safe itself,
     * which is the msg.sender in a module context.
     * @param _timeoutInDays The number of days of inactivity before the will can be executed.
     */
    function createWill(uint256 _timeoutInDays) external {
        address safe = msg.sender;

        if (willData[msg.sender].lastPing > 0) {
            revert WillAlreadyExists();
        }
        if (_timeoutInDays <= 0) {
            revert TimeoutMustBeMoreThan0();
        }

        willData[safe].lastPing = block.timestamp;
        willData[safe].timeout = _timeoutInDays * 1 days;

        emit WillCreated(safe, _timeoutInDays * 1 days);
    }

    /**
     * @notice Resets the inactivity timer for the calling Safe's will.
     * @dev The caller (msg.sender) must be a Safe account with an existing will.
     */
    function ping() external {
        address safe = msg.sender;

        if (willData[safe].timeout == 0) {
            revert WillNotFound(safe);
        }

        willData[safe].lastPing = block.timestamp;
        emit Ping(safe);
    }

    /**
     * @notice Adds a beneficiary to the calling Safe's will.
     * @dev The caller (msg.sender) must be a Safe account with an existing will.
     * @param _beneficiary The keccak256 hash of the beneficiary's off-chain identifier to add.
     * @param _amount The inheritance amount in wei.
     */
    function addBeneficiary(bytes32 _beneficiary, uint256 _amount) external {
        address safe = msg.sender;
        Will storage userWill = willData[safe];

        if (userWill.timeout == 0) {
            revert WillNotFound(safe);
        }
        if (_amount == 0) {
            revert UnviableAmount();
        }
        if (userWill.inheritances[_beneficiary] > 0) {
            revert BeneficiaryExists(_beneficiary);
        }
        
        userWill.inheritances[_beneficiary] = _amount;
        userWill.beneficiaryList.push(_beneficiary);
        userWill.lastPing = block.timestamp; 
        emit BeneficiaryAdded(safe, _beneficiary, _amount);
    }

    /**
     * @notice Removes a beneficiary from the calling Safe's will.
     * @dev Uses the 'swap and pop' method for efficient array removal.
     * @param _beneficiary The keccak256 hash of the beneficiary's off-chain identifier to remove.
     */
    function removeBeneficiary(bytes32 _beneficiary) external {
        address safe = msg.sender;
        Will storage userWill = willData[safe];

        // --- Checks ---
        if (userWill.timeout == 0) {
            revert WillNotFound(safe);
        }
        if (userWill.inheritances[_beneficiary] == 0) {
            revert BeneficiaryNotFound(_beneficiary);
        }

        delete userWill.inheritances[_beneficiary];
        
        // "Swap and Pop" to remove from the array
        for (uint256 i = 0; i < userWill.beneficiaryList.length; i++) {
            if (userWill.beneficiaryList[i] == _beneficiary) {
                // Swap the element to remove with the last element
                userWill.beneficiaryList[i] = userWill.beneficiaryList[userWill.beneficiaryList.length - 1];
                // Remove the last element
                userWill.beneficiaryList.pop();
                break;
            }
        }
        
        userWill.lastPing = block.timestamp;
        emit BeneficiaryRemoved(safe, _beneficiary);
    }

    /**
     * @notice Updates the inheritance amount for an existing beneficiary using their private identifier.
     * @param _beneficiary The keccak256 hash of the beneficiary's unique off-chain identifier.
     * @param _newAmount The new inheritance amount in wei.
     */
    function updateBeneficiary(bytes32 _beneficiary, uint256 _newAmount) external {
        address safe = msg.sender;
        Will storage userWill = willData[safe];

        if (userWill.timeout == 0) {
            revert WillNotFound(safe);
        }
        if (userWill.inheritances[_beneficiary] == 0) {
            revert BeneficiaryNotFound(_beneficiary);
        }
        if (_newAmount == 0) {
            revert UnviableAmount();
        }

        userWill.inheritances[_beneficiary] = _newAmount;
        userWill.lastPing = block.timestamp;
        emit BeneficiaryUpdated(safe, _beneficiary, _newAmount);
    }

    /**
     * @notice Allows a beneficiary to claim their inheritance. This action creates a new Safe
     * for the beneficiary and transfers their inheritance from the owner's Safe.
     * @param _ownerSafeAddress The address of the will owner's Safe account.
     * @param _beneficiarySecret A unique off-chain secret (e.g., "charmander@gmail.com").
     * @param _newSafeOwner The address that will own the newly created Safe for the beneficiary.
     */
    function claimInheritance(address _ownerSafeAddress, string calldata _beneficiarySecret, address _newSafeOwner) external {
        Will storage ownerWill = willData[_ownerSafeAddress];
        // --- 1. The Checks ---
        if (ownerWill.timeout == 0) {
            revert WillNotFound(_ownerSafeAddress);
        }
        if (block.timestamp < ownerWill.lastPing + ownerWill.timeout) {
            revert TimeoutNotExpired(ownerWill.lastPing + ownerWill.timeout);
        }

        // Hash the secret to get the beneficiary ID
        bytes32 beneficiaryId = keccak256(abi.encodePacked(_beneficiarySecret));
        
        uint256 inheritanceAmount = ownerWill.inheritances[beneficiaryId];
        if (inheritanceAmount == 0) {
            revert NothingToClaim();
        }

        // --- 2. New Safe Creation for Beneficiary ---
        address safeSingleton = 0x29fcB43b46531BcA003ddC8FCB67FFE91900C762; // Arb Sepolia
        address safeFactory = 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67;   // Arb Sepolia

        address[] memory owners = new address[](1);
        owners[0] = _newSafeOwner;

        // Initializes the new Safe, setting `_newSafeOwner` as the owner.
        bytes memory setupData = abi.encodeWithSignature(
            // The function signature as a string literal
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",

            // Argument 1: The owners array
            _newSafeOwner,

            // Argument 2: Threshold of 1 since there's a single owner
            1,

            // Arguments 3-8: The optional parameters, set to zero/empty
            address(0),
            "",
            address(0),
            address(0),
            0,
            address(0)
            );

        // Calls the factory to create the new Safe for the beneficiary and returns 
        // the address of the newly created Safe. 
        address newBeneficiarySafe = ISafeProxyFactory(safeFactory).createProxy(safeSingleton, setupData);

        // --- 3. The Payout ---
        // Commands the owner's Safe to send the inheritance to the new Safe.
        bool success = ISafe(payable(_ownerSafeAddress)).execTransactionFromModule(
            newBeneficiarySafe, 
            inheritanceAmount, 
            "", 
            Enum.Operation.Call);
        require(success, "WillModule: Payout from owner's Safe failed");
        
        // --- 4. Admin ---
        delete ownerWill.inheritances[beneficiaryId];
        for (uint256 i = 0; i < ownerWill.beneficiaryList.length; i++) {
            if (ownerWill.beneficiaryList[i] == beneficiaryId) {
                ownerWill.beneficiaryList[i] = ownerWill.beneficiaryList[ownerWill.beneficiaryList.length - 1];
                ownerWill.beneficiaryList.pop();
                break;
            }
        }
        emit InheritanceClaimed(_ownerSafeAddress, beneficiaryId, newBeneficiarySafe, inheritanceAmount);
    }
}