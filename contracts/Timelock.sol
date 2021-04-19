// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma experimental ABIEncoderV2;
/*
 _    _ __     __ _____   _    _  _       ______   _____ __          __       _____
| |  | |\ \   / /|  __ \ | |  | || |     |  ____| / ____|\ \        / //\    |  __ \
| |__| | \ \_/ / | |__) || |  | || |     | |__   | (___   \ \  /\  / //  \   | |__) |
|  __  |  \   /  |  _  / | |  | || |     |  __|   \___ \   \ \/  \/ // /\ \  |  ___/
| |  | |   | |   | | \ \ | |__| || |____ | |____  ____) |   \  /\  // ____ \ | |
|_|  |_|   |_|   |_|  \_\ \____/ |______||______||_____/     \/  \//_/    \_\|_|

*/

//Openzeppelin
import "@openzeppelin/contracts/access/AccessControl.sol";

// Interfaces
import "../interfaces/IBEP20.sol";
import "../interfaces/SafeBEP20.sol";
import "../interfaces/IGRupeeFarm.sol";
import "../interfaces/IStrategy.sol";

contract Timelock is AccessControl {
    using SafeBEP20 for IBEP20;

    bytes32 public constant TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    uint256 internal constant _DONE_TIMESTAMP = uint256(1);

    mapping(bytes32 => uint256) private _timestamps;
    uint256 public minDelay = 86400; // 24h
    uint256 public minDelayReduced = 43200; // 12h

    address payable public devWalletAddress = 0xe08004Cb39EC176E2cCf841c4597bDb0f3a190Fb;
    /**
     * @dev Emitted when a call is scheduled as part of operation `id`.
     */
    event CallScheduled(
        bytes32 indexed id,
        uint256 indexed index,
        address target,
        uint256 value,
        bytes data,
        bytes32 predecessor,
        uint256 delay
    );

    /**
     * @dev Emitted when a call is scheduled as part of operation `id`.
     */
    event SetScheduled(
        bytes32 indexed id,
        uint256 indexed index,
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate,
        bytes32 predecessor,
        uint256 delay
    );

    /**
     * @dev Emitted when a call is performed as part of operation `id`.
     */
    event CallExecuted(bytes32 indexed id, uint256 indexed index, address target, uint256 value, bytes data);

    /**
     * @dev Emitted when operation `id` is cancelled.
     */
    event Cancelled(bytes32 indexed id);

    /**
     * @dev Emitted when the minimum delay for future operations is modified.
     */
    event MinDelayChange(uint256 oldDuration, uint256 newDuration);

    event MinDelayReducedChange(uint256 oldDuration, uint256 newDuration);

    event SetScheduled(bytes32 indexed id, uint256 indexed index, address target, uint256 value, bytes data, bytes32 predecessor, uint256 delay);

    /**
     * @dev Initializes the contract with a given `minDelay`.
     */
    constructor() public {
        _setRoleAdmin(TIMELOCK_ADMIN_ROLE, TIMELOCK_ADMIN_ROLE);
        _setRoleAdmin(PROPOSER_ROLE, TIMELOCK_ADMIN_ROLE);
        _setRoleAdmin(EXECUTOR_ROLE, TIMELOCK_ADMIN_ROLE);

        // deployer + self administration
        _setupRole(TIMELOCK_ADMIN_ROLE, _msgSender());
        _setupRole(TIMELOCK_ADMIN_ROLE, address(this));

        _setupRole(PROPOSER_ROLE, devWalletAddress);
        _setupRole(EXECUTOR_ROLE, devWalletAddress);

        emit MinDelayChange(0, minDelay);
    }

    /**
     * @dev Modifier to make a function callable only by a certain role. In
     * addition to checking the sender's role, `address(0)` 's role is also
     * considered. Granting a role to `address(0)` is equivalent to enabling
     * this role for everyone.
     */
    modifier onlyRole(bytes32 role) {
        require(hasRole(role, _msgSender()) || hasRole(role, address(0)), "TimelockController: sender requires permission");
        _;
    }

    /**
     * @dev Contract might receive/hold ETH as part of the maintenance process.
     */
    receive() external payable {}

    /**
     * @dev Returns whether an operation is pending or not.
     */
    function isOperationPending(bytes32 id) public view returns (bool pending) {
        return _timestamps[id] > _DONE_TIMESTAMP;
    }

    /**
     * @dev Returns whether an operation is ready or not.
     */
    function isOperationReady(bytes32 id) public view returns (bool ready) {
        // solhint-disable-next-line not-rely-on-time
        return _timestamps[id] > _DONE_TIMESTAMP && _timestamps[id] <= block.timestamp;
    }

    /**
     * @dev Returns whether an operation is done or not.
     */
    function isOperationDone(bytes32 id) public view returns (bool done) {
        return _timestamps[id] == _DONE_TIMESTAMP;
    }

    /**
     * @dev Returns the timestamp at with an operation becomes ready (0 for
     * unset operations, 1 for done operations).
     */
    function getTimestamp(bytes32 id) public view returns (uint256 timestamp) {
        return _timestamps[id];
    }

    /**
     * @dev Returns the minimum delay for an operation to become valid.
     *
     * This value can be changed by executing an operation that calls `updateDelay`.
     */
    function getMinDelay() public view returns (uint256 duration) {
        return minDelay;
    }

    /**
     * @dev Returns the identifier of an operation containing a single
     * transaction.
     */
    function hashOperation(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) public pure returns (bytes32 hash) {
        return keccak256(abi.encode(target, value, data, predecessor, salt));
    }

    /**
     * @dev Returns the identifier of an operation containing a batch of
     * transactions.
     */
    function hashOperationBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas,
        bytes32 predecessor,
        bytes32 salt
    ) public pure returns (bytes32 hash) {
        return keccak256(abi.encode(targets, values, datas, predecessor, salt));
    }

    /**
     * @dev Schedule an operation containing a single transaction.
     *
     * Emits a {CallScheduled} event.
     *
     * Requirements:
     *
     * - the caller must have the 'proposer' role.
     */
    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual onlyRole(PROPOSER_ROLE) {
        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        _schedule(id, delay);
        emit CallScheduled(id, 0, target, value, data, predecessor, delay);
    }

    /**
     * @dev Schedule an operation containing a batch of transactions.
     *
     * Emits one {CallScheduled} event per transaction in the batch.
     *
     * Requirements:
     *
     * - the caller must have the 'proposer' role.
     */
    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual onlyRole(PROPOSER_ROLE) {
        require(targets.length == values.length, "TimelockController: length mismatch");
        require(targets.length == datas.length, "TimelockController: length mismatch");

        bytes32 id = hashOperationBatch(targets, values, datas, predecessor, salt);
        _schedule(id, delay);
        for (uint256 i = 0; i < targets.length; ++i) {
            emit CallScheduled(id, i, targets[i], values[i], datas[i], predecessor, delay);
        }
    }

    /**
     * @dev Schedule an operation that is to becomes valid after a given delay.
     */
    function _schedule(bytes32 id, uint256 delay) private {
        require(_timestamps[id] == 0, "TimelockController: operation already scheduled");
        require(delay >= minDelay, "TimelockController: insufficient delay");
        // solhint-disable-next-line not-rely-on-time
        _timestamps[id] = SafeMath.add(block.timestamp, delay);
    }

    /**
     * @dev Cancel an operation.
     *
     * Requirements:
     *
     * - the caller must have the 'proposer' role.
     */
    function cancel(bytes32 id) public virtual onlyRole(PROPOSER_ROLE) {
        require(isOperationPending(id), "TimelockController: operation cannot be cancelled");
        delete _timestamps[id];

        emit Cancelled(id);
    }

    /**
     * @dev Execute an (ready) operation containing a single transaction.
     *
     * Emits a {CallExecuted} event.
     *
     * Requirements:
     *
     * - the caller must have the 'executor' role.
     */
    function execute(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) public payable virtual onlyRole(EXECUTOR_ROLE) {
        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        _beforeCall(predecessor);
        _call(id, 0, target, value, data);
        _afterCall(id);
    }

    /**
     * @dev Execute an (ready) operation containing a batch of transactions.
     *
     * Emits one {CallExecuted} event per transaction in the batch.
     *
     * Requirements:
     *
     * - the caller must have the 'executor' role.
     */
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas,
        bytes32 predecessor,
        bytes32 salt
    ) public payable virtual onlyRole(EXECUTOR_ROLE) {
        require(targets.length == values.length, "TimelockController: length mismatch");
        require(targets.length == datas.length, "TimelockController: length mismatch");

        bytes32 id = hashOperationBatch(targets, values, datas, predecessor, salt);
        _beforeCall(predecessor);
        for (uint256 i = 0; i < targets.length; ++i) {
            _call(id, i, targets[i], values[i], datas[i]);
        }
        _afterCall(id);
    }

    /**
     * @dev Checks before execution of an operation's calls.
     */
    function _beforeCall(bytes32 predecessor) private view {
        require(predecessor == bytes32(0) || isOperationDone(predecessor), "TimelockController: missing dependency");
    }

    /**
     * @dev Checks after execution of an operation's calls.
     */
    function _afterCall(bytes32 id) private {
        require(isOperationReady(id), "TimelockController: operation is not ready");
        _timestamps[id] = _DONE_TIMESTAMP;
    }

    /**
     * @dev Execute an operation's call.
     *
     * Emits a {CallExecuted} event.
     */
    function _call(
        bytes32 id,
        uint256 index,
        address target,
        uint256 value,
        bytes calldata data
    ) private {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = target.call{value: value}(data);
        require(success, "TimelockController: underlying transaction reverted");

        emit CallExecuted(id, index, target, value, data);
    }

    /**
     * @dev Changes the minimum timelock duration for future operations.
     *
     * Emits a {MinDelayChange} event.
     *
     * Requirements:
     *
     * - the caller must be the timelock itself. This can only be achieved by scheduling and later executing
     * an operation where the timelock is the target and the data is the ABI-encoded call to this function.
     */
    function updateMinDelay(uint256 newDelay) external virtual {
        require(msg.sender == address(this), "TimelockController: caller must be timelock");
        emit MinDelayChange(minDelay, newDelay);
        minDelay = newDelay;
    }

    function updateMinDelayReduced(uint256 newDelay) external virtual {
        require(msg.sender == address(this), "TimelockController: caller must be timelock");
        emit MinDelayReducedChange(minDelayReduced, newDelay);
        minDelayReduced = newDelay;
    }

    function setDevWalletAddress(address payable _devWalletAddress) public {
        require(msg.sender == address(this), "TimelockController: caller must be timelock");
        require(tx.origin == devWalletAddress, "tx.origin != devWalletAddress");
        devWalletAddress = _devWalletAddress;
    }

    /**
     * @dev Reduced timelock functions
     */
    function scheduleSet(
        address _gRupeeMasterchef,
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate,
        bytes32 predecessor,
        bytes32 salt
    ) public onlyRole(EXECUTOR_ROLE) {
        bytes32 id = keccak256(abi.encode(_gRupeeMasterchef, _pid, _allocPoint, _withUpdate, predecessor, salt));

        require(_timestamps[id] == 0, "TimelockController: operation already scheduled");

        _timestamps[id] = SafeMath.add(block.timestamp, minDelayReduced);
        emit SetScheduled(id, 0, _pid, _allocPoint, _withUpdate, predecessor, minDelayReduced);
    }

    function executeSet(
        address _gRupeeMasterchef,
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate,
        bytes32 predecessor,
        bytes32 salt
    ) public payable virtual onlyRole(EXECUTOR_ROLE) {
        bytes32 id = keccak256(abi.encode(_gRupeeMasterchef, _pid, _allocPoint, _withUpdate, predecessor, salt));

        _beforeCall(predecessor);
        IGRupeeFarm(_gRupeeMasterchef).set(_pid, _allocPoint, _withUpdate);
        _afterCall(id);
    }

    /**
     * @dev No timelock functions
     */
    function withdrawBNB() public payable {
        require(msg.sender == devWalletAddress, "!devWalletAddress");
        devWalletAddress.transfer(address(this).balance);
    }

    function withdrawBEP20(address _tokenAddress) public payable {
        require(msg.sender == devWalletAddress, "!devWalletAddress");
        uint256 tokenBal = IBEP20(_tokenAddress).balanceOf(address(this));
        IBEP20(_tokenAddress).safeIncreaseAllowance(devWalletAddress, tokenBal);
        IBEP20(_tokenAddress).transfer(devWalletAddress, tokenBal);
    }

    function add(
        address _gRupeeMasterchef,
        address _want,
        bool _withUpdate,
        address _strat
    ) public onlyRole(EXECUTOR_ROLE) {
        IGRupeeFarm(_gRupeeMasterchef).add(0, _want, _withUpdate, _strat); // allocPoint = 0. Schedule set (timelocked) to increase allocPoint.
    }

    function earn(address _stratAddress) public onlyRole(EXECUTOR_ROLE) {
        IStrategy(_stratAddress).earn();
    }
}
