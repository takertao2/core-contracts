// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
/*
 _    _ __     __ _____   _    _  _       ______   _____ __          __       _____
| |  | |\ \   / /|  __ \ | |  | || |     |  ____| / ____|\ \        / //\    |  __ \
| |__| | \ \_/ / | |__) || |  | || |     | |__   | (___   \ \  /\  / //  \   | |__) |
|  __  |  \   /  |  _  / | |  | || |     |  __|   \___ \   \ \/  \/ // /\ \  |  ___/
| |  | |   | |   | | \ \ | |__| || |____ | |____  ____) |   \  /\  // ____ \ | |
|_|  |_|   |_|   |_|  \_\ \____/ |______||______||_____/     \/  \//_/    \_\|_|

*/
// Interfaces
import "../../interfaces/IBEP20.sol";
import "../../interfaces/SafeBEP20.sol";
import "../../interfaces/IPancakeRouter.sol";
import "../../interfaces/IPancakeMasterChef.sol";

//Openzeppelin
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract BaseStrategy is Ownable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    bool public isCAKEStaking; // only for staking CAKE using pancakeswap's native CAKE staking contract.
    bool public isStaking; // HyruleSwap, Goose.. single pools staking
    bool public isAutoCompound; // Wether uses strategy or just stack to earn GoldenRupee

    address public masterChefAddress; // masterChef
    uint256 public pid; // pid of pool in masterChefAddress
    address public wantAddress;
    address public token0Address;
    address public token1Address;
    address public earnedAddress;
    address public routerAddress; // pancakeswap, apeswap etc.

    address public constant wbnbAddress = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public gRupeeMasterChef;
    address public govAddress; // timelock contract
    address public feeAddress;
    bool public onlyGov = true;

    uint256 public lastEarnBlock = 0;
    uint256 public wantLockedTotal = 0;
    uint256 public sharesTotal = 0;

    uint256 public controllerFee = 2000; // 20%
    uint256 public constant controllerFeeMax = 10000; // 100 = 1%
    uint256 public constant controllerFeeUL = 2000; // Maximum fees allowed eg. 20%

    uint256 public entranceFeeFactor = 9990; // < 0.1% entrance fee - goes to pool + prevents front-running
    uint256 public constant entranceFeeFactorMax = 10000;
    uint256 public constant entranceFeeFactorLL = 9950; // 0.5% is the max entrance fee settable.

    address[] public earnedToToken0Path;
    address[] public earnedToToken1Path;
    address[] public token0ToEarnedPath;
    address[] public token1ToEarnedPath;

    constructor(
        address _gRupeeMasterChef,
        address _feeAddress,
        bool _isCAKEStaking,
        bool _isStaking,
        bool _isAutoCompound,
        address _masterChefAddress,
        uint256 _pid,
        address _wantAddress,
        address _token0Address,
        address _token1Address,
        address _earnedAddress,
        address _routerAddress
    ) {
        govAddress = msg.sender;
        feeAddress = _feeAddress;
        gRupeeMasterChef = _gRupeeMasterChef;

        isCAKEStaking = _isCAKEStaking;
        isStaking = _isStaking;
        isAutoCompound = _isAutoCompound;
        wantAddress = _wantAddress;

        if (isAutoCompound) {
            if (!isCAKEStaking && !isStaking) {
                token0Address = _token0Address;
                token1Address = _token1Address;
            }

            masterChefAddress = _masterChefAddress;
            pid = _pid;
            earnedAddress = _earnedAddress;

            routerAddress = _routerAddress;

            earnedToToken0Path = [earnedAddress, wbnbAddress, token0Address];
            if (wbnbAddress == token0Address) {
                earnedToToken0Path = [earnedAddress, wbnbAddress];
            }

            earnedToToken1Path = [earnedAddress, wbnbAddress, token1Address];
            if (wbnbAddress == token1Address) {
                earnedToToken1Path = [earnedAddress, wbnbAddress];
            }

            token0ToEarnedPath = [token0Address, wbnbAddress, earnedAddress];
            if (wbnbAddress == token0Address) {
                token0ToEarnedPath = [wbnbAddress, earnedAddress];
            }

            token1ToEarnedPath = [token1Address, wbnbAddress, earnedAddress];
            if (wbnbAddress == token1Address) {
                token1ToEarnedPath = [wbnbAddress, earnedAddress];
            }
        }
        transferOwnership(gRupeeMasterChef);
    }

    function deposit(address _userAddress, uint256 _wantAmt) public onlyOwner whenNotPaused returns (uint256) {
        IBEP20(wantAddress).safeTransferFrom(address(msg.sender), address(this), _wantAmt);

        uint256 sharesAdded = _wantAmt;
        if (wantLockedTotal > 0) {
            sharesAdded = _wantAmt.mul(sharesTotal).mul(entranceFeeFactor).div(wantLockedTotal).div(entranceFeeFactorMax);
        }
        sharesTotal = sharesTotal.add(sharesAdded);

        if (isAutoCompound) {
            _farm();
        } else {
            wantLockedTotal = wantLockedTotal.add(_wantAmt);
        }

        return sharesAdded;
    }

    function farm() public nonReentrant {
        _farm();
    }

    function _farm() internal {
        uint256 wantAmt = IBEP20(wantAddress).balanceOf(address(this));
        wantLockedTotal = wantLockedTotal.add(wantAmt);
        IBEP20(wantAddress).safeIncreaseAllowance(masterChefAddress, wantAmt);

        if (isCAKEStaking) {
            IPancakeMasterChef(masterChefAddress).enterStaking(wantAmt); // Just for CAKE staking, we dont use deposit()
        } else {
            IPancakeMasterChef(masterChefAddress).deposit(pid, wantAmt);
        }
    }

    function withdraw(address _userAddress, uint256 _wantAmt) public onlyOwner nonReentrant returns (uint256) {
        require(_wantAmt > 0, "_wantAmt <= 0");

        if (isAutoCompound) {
            if (isCAKEStaking) {
                IPancakeMasterChef(masterChefAddress).leaveStaking(_wantAmt); // Just for CAKE staking, we dont use withdraw()
            } else {
                IPancakeMasterChef(masterChefAddress).withdraw(pid, _wantAmt);
            }
        }

        uint256 wantAmt = IBEP20(wantAddress).balanceOf(address(this));
        if (_wantAmt > wantAmt) {
            _wantAmt = wantAmt;
        }

        if (wantLockedTotal < _wantAmt) {
            _wantAmt = wantLockedTotal;
        }

        uint256 sharesRemoved = _wantAmt.mul(sharesTotal).div(wantLockedTotal);
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        sharesTotal = sharesTotal.sub(sharesRemoved);
        wantLockedTotal = wantLockedTotal.sub(_wantAmt);

        IBEP20(wantAddress).safeTransfer(gRupeeMasterChef, _wantAmt);

        return sharesRemoved;
    }

    function earn() public whenNotPaused {
        require(isAutoCompound, "!isAutoCompound");
        if (onlyGov) {
            require(msg.sender == govAddress, "Not authorised");
        }

        // Harvest farm tokens
        if (isCAKEStaking) {
            IPancakeMasterChef(masterChefAddress).leaveStaking(0); // Just for CAKE staking, we dont use withdraw()
        } else {
            IPancakeMasterChef(masterChefAddress).withdraw(pid, 0);
        }

        // Converts farm tokens into want tokens
        uint256 earnedAmt = IBEP20(earnedAddress).balanceOf(address(this));

        earnedAmt = distributeFees(earnedAmt);

        if (isCAKEStaking || isStaking) {
            lastEarnBlock = block.number;
            _farm();
            return;
        }
        IBEP20(earnedAddress).safeIncreaseAllowance(routerAddress, earnedAmt);

        if (earnedAddress != token0Address) {
            // Swap half earned to token0
            IPancakeRouter(routerAddress).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                earnedAmt.div(2),
                0,
                earnedToToken0Path,
                address(this),
                block.timestamp + 60
            );
        }

        if (earnedAddress != token1Address) {
            // Swap half earned to token1
            IPancakeRouter(routerAddress).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                earnedAmt.div(2),
                0,
                earnedToToken1Path,
                address(this),
                block.timestamp + 60
            );
        }

        // Get want tokens, ie. add liquidity
        uint256 token0Amt = IBEP20(token0Address).balanceOf(address(this));
        uint256 token1Amt = IBEP20(token1Address).balanceOf(address(this));
        if (token0Amt > 0 && token1Amt > 0) {
            IBEP20(token0Address).safeIncreaseAllowance(routerAddress, token0Amt);
            IBEP20(token1Address).safeIncreaseAllowance(routerAddress, token1Amt);
            IPancakeRouter(routerAddress).addLiquidity(
                token0Address,
                token1Address,
                token0Amt,
                token1Amt,
                0,
                0,
                address(this),
                block.timestamp + 60
            );
        }
        lastEarnBlock = block.number;
        _farm();
    }

    function distributeFees(uint256 _earnedAmt) internal returns (uint256) {
        if (_earnedAmt > 0) {
            // Performance fee
            if (controllerFee > 0) {
                uint256 fee = _earnedAmt.mul(controllerFee).div(controllerFeeMax);
                IBEP20(earnedAddress).safeTransfer(feeAddress, fee);
                _earnedAmt = _earnedAmt.sub(fee);
            }
        }

        return _earnedAmt;
    }

    function convertDustToEarned() public whenNotPaused {
        require(isAutoCompound, "!isAutoCompound");
        require(!isCAKEStaking && !isStaking, "Single pool strategy");

        // Converts dust tokens into earned tokens, which will be reinvested on the next earn().

        // Converts token0 dust (if any) to earned tokens
        uint256 token0Amt = IBEP20(token0Address).balanceOf(address(this));
        if (token0Address != earnedAddress && token0Amt > 0) {
            IBEP20(token0Address).safeIncreaseAllowance(routerAddress, token0Amt);

            // Swap all dust tokens to earned tokens
            IPancakeRouter(routerAddress).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                token0Amt,
                0,
                token0ToEarnedPath,
                address(this),
                block.timestamp + 60
            );
        }

        // Converts token1 dust (if any) to earned tokens
        uint256 token1Amt = IBEP20(token1Address).balanceOf(address(this));
        if (token1Address != earnedAddress && token1Amt > 0) {
            IBEP20(token1Address).safeIncreaseAllowance(routerAddress, token1Amt);

            // Swap all dust tokens to earned tokens
            IPancakeRouter(routerAddress).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                token1Amt,
                0,
                token1ToEarnedPath,
                address(this),
                block.timestamp + 60
            );
        }
    }

    function pause() public {
        require(msg.sender == govAddress, "Not authorised");
        _pause();
    }

    function unpause() external {
        require(msg.sender == govAddress, "Not authorised");
        _unpause();
    }

    function setEntranceFeeFactor(uint256 _entranceFeeFactor) external {
        require(msg.sender == govAddress, "Not authorised");
        require(_entranceFeeFactor > entranceFeeFactorLL, "!safe - too low");
        require(_entranceFeeFactor <= entranceFeeFactorMax, "!safe - too high");
        entranceFeeFactor = _entranceFeeFactor;
    }

    function setControllerFee(uint256 _controllerFee) external {
        require(msg.sender == govAddress, "Not authorised");
        require(_controllerFee <= controllerFeeUL, "too high");
        controllerFee = _controllerFee;
    }

    function setGov(address _govAddress) external {
        require(msg.sender == govAddress, "!gov");
        govAddress = _govAddress;
    }

    function setOnlyGov(bool _onlyGov) external {
        require(msg.sender == govAddress, "!gov");
        onlyGov = _onlyGov;
    }

    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    ) external {
        require(msg.sender == govAddress, "!gov");
        require(_token != earnedAddress, "!safe");
        require(_token != wantAddress, "!safe");
        IBEP20(_token).safeTransfer(_to, _amount);
    }
}
