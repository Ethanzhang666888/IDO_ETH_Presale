// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IPresale} from "./IPresale.sol";

contract IDO_ETH_Persale is IPresale, Ownable {
    /// Scaling factor to maintain precision.
    uint256 constant SCALE = 10 ** 18;
    // Foundation address, after successful fundraising, Ethereum will be transferred to the foundation address
    address public Foundation = 0x9753473c77316AdF25C839Ec44C2121F9266cAAE;

    /**
     * @notice Presale options
     * @param tokenprice price = Token:ETH (eg: 10000:1)
     * @param tokenDeposit Total tokens deposited for sale.
     * @param hardCap Maximum Wei to be raised.
     * @param softCap Minimum Wei to be raised to consider the presale successful.
     * @param max Maximum Wei contribution per address.
     * @param min Minimum Wei contribution per address.
     * @param start Start timestamp of the presale.
     * @param end End timestamp of the presale.
     */
    struct PresaleOptions {
        uint256 tokenprice; //10000:1 Token:ETH  price:0.0001ETH
        uint256 tokenDeposit; //20000
        uint256 hardCap; //2ETH
        uint256 softCap; //1.5ETH
        uint256 max; //0.1ETH
        uint256 min; //0.01ETH
        uint112 start; //1672531200
        uint112 end; //1672531200
    }

    /**
     * @notice Presale pool
     * @param token Address of the Presale token.
     * @param tokenBalance Presale Token balance in this contract
     * @param tokensClaimable Claimed share Presale tokens
     * @param ETHRaised All received ETH quantities
     * @param state Current state of the presale {1: Initialized, 2: Active, 3: Canceled or not finalized, 4: Finalized}.
     * @param options PresaleOptions struct containing configuration for the presale.
     */
    struct Pool {
        IERC20 token;
        uint256 tokenBalance;
        uint256 tokensClaimable;
        uint256 ETHRaised;
        uint8 state;
        PresaleOptions options;
    }

    //mapping of contributions of contributors
    mapping(address => uint256) public contributions;
    //Declare the pool
    Pool public pool;

    /**
     * @notice Initializes the presale contract.
     * @param _token Address of the presale token.
     * @param _options PresaleOptions struct containing configuration for the presale.
     */
    constructor(address _token, PresaleOptions memory _options) Ownable(msg.sender) {
        _prevalidatePool(_options);

        pool.token = IERC20(_token);
        pool.options = _options;
        pool.tokenBalance = 0;
        pool.tokensClaimable = 0;
        pool.ETHRaised = 0;
        pool.state = 1;
    }

    /**
     * @notice updates the state of the presale.
     * @notice state = 1 :  Initialized
     * @notice state = 2 :  Active
     * @notice state = 3 :  Canceled or not finalized
     * @notice state = 4 :  Finalized
     */
    function updatastate() external onlyOwner returns (uint8) {
        if (pool.state == 2 && block.timestamp >= pool.options.end) {
            if (pool.ETHRaised < pool.options.softCap) {
                pool.state = 3;
                emit Cancel(msg.sender, block.timestamp);
            } else {
                pool.state = 4;
                emit Finalized(msg.sender, pool.ETHRaised, block.timestamp);
            }
        }
        return (pool.state);
    }

    /**
     * @notice Validates the pool configuration before accepting funds.
     * @dev This function is called when the contract is initialized.
     * @param _options The presale options.
     * @return True if the pool configuration is valid.
     */
    function _prevalidatePool(PresaleOptions memory _options) internal view returns (bool) {
        if (_options.softCap == 0 || _options.softCap > _options.hardCap) revert InvalidCapValue();
        if (_options.min == 0 || _options.min > _options.max) revert InvalidLimitValue();
        if (_options.start > block.timestamp || _options.end < _options.start) revert InvalidTimestampValue();
        return true;
    }

    /**
     * @notice Calling this function deposits tokens into the contract. Contributions are unavailable until this.
     * @notice pool.state 1 :  Initialized
     * @dev function is called by the owner of the presale.
     * @return The amount of tokens deposited.
     */
    function deposit() external onlyOwner returns (uint256) {
        if (pool.state != 1) revert InvalidState(pool.state);
        pool.state = 2;
        IERC20(pool.token).transferFrom(msg.sender, address(this), pool.options.tokenDeposit);
        pool.tokenBalance += pool.options.tokenDeposit;
        emit Deposit(msg.sender, pool.options.tokenDeposit, block.timestamp);
        return pool.options.tokenDeposit;
    }

    /**
     * @notice receives ETH from contributors.
     * @notice pool.state 2 :  Active
     * @dev This function is called when a contributor sends ETH to the contract.
     */
    receive() external payable {
        _purchase(msg.sender, msg.value);
    }

    /**
     * @notice Validates the purchase conditions before accepting funds.
     * @notice pool.state 2 :  Active
     * @param _beneficiary The address attempting to make a purchase.
     * @param _amount The amount of Wei being contributed.
     * @return True if the purchase is valid.
     */
    function _prevalidatePurchase(address _beneficiary, uint256 _amount) internal view returns (bool) {
        if (pool.state != 2) revert InvalidState(pool.state);
        if (block.timestamp < pool.options.start || block.timestamp > pool.options.end) revert NotInPurchasePeriod();
        if (pool.ETHRaised + _amount > pool.options.hardCap) revert HardCapExceed();
        if (_amount < pool.options.min) revert PurchaseBelowMinimum();
        if (_amount + contributions[_beneficiary] > pool.options.max) revert PurchaseLimitExceed();
        return true;
    }

    /**
     * @notice Handles token purchase.
     * @notice pool.state 2 :  Active
     * @dev This function is called when a contributor sends ETH to the contract.
     * @param beneficiary The address making the purchase.
     * @param amount The amount of ETH contributed.
     */
    function _purchase(address beneficiary, uint256 amount) private {
        _prevalidatePurchase(beneficiary, amount);

        pool.ETHRaised += amount;
        contributions[beneficiary] += amount;

        pool.tokensClaimable += userTokens(beneficiary);
        pool.tokenBalance -= userTokens(beneficiary);

        emit Purchase(beneficiary, amount);
    }

    /**
     * @notice Call this function to cancel a presale. Calling this function withdraws deposited tokens and allows contributors
     * @notice pool.state 3 :  Canceled or not finalized
     * @dev This function is only callable by the owner of the presale.
     * @return True if the cancellation was successful.
     */
    function cancel() external onlyOwner returns (bool) {
        if (pool.state > 3) revert InvalidState(pool.state);
        pool.state = 3;
        if (pool.tokenBalance > 0) {
            uint256 amount = pool.options.tokenDeposit;
            pool.tokenBalance = 0;
            IERC20(pool.token).transfer(msg.sender, amount);
        }
        emit Cancel(msg.sender, block.timestamp);
        return true;
    }

    /**
     * @notice Withdraws ETH from the presale for the contributor.
     * @notice pool.state 3 :  Canceled or not finalized
     * @dev Only the contributor can call this function.
     */
    function _withdrawALLForPresale_user() external onlyRefundable {
        if (pool.state != 3) revert InvalidState(pool.state);
        uint256 _contributions = contributions[msg.sender];
        require(_contributions > 0, "No ETH to withdraw");
        contributions[msg.sender] = 0;
        pool.ETHRaised -= _contributions;
        bool success = payable(msg.sender).send(_contributions);
        require(success, "Withdrawal failed");
        emit Withdraw(msg.sender, _contributions, block.timestamp);
    }

    /**
     * @notice Withdraws tokens for the presale.
     * @notice pool.state 4 :  Finalized
     */
    function _withdrawForPresale(uint256 amount) external {
        if (pool.state != 4) revert InvalidState(pool.state);
        uint256 userTokenBalance = userTokens(msg.sender);
        if (amount > userTokenBalance) revert WithdrawExceed();
        // pool.options.tokenDeposit -= amount;
        pool.tokensClaimable -= amount;
        contributions[msg.sender] -= (amount / (pool.options.tokenprice));
        IERC20(pool.token).transfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount, block.timestamp);
    }

    /**
     * @notice Withdraws ETH from the presale for Foundation by owner.
     * @notice pool.state 4 :  Finalized
     * @dev Only the owner can call this function.
     */
    function _withdrawALLForPresale_owner() external onlyOwner {
        if (pool.state != 4) revert InvalidState(pool.state);
        uint256 _contributions = pool.ETHRaised;
        require(_contributions > 0, "No ETH to withdraw");
        pool.ETHRaised = 0;
        bool success = payable(Foundation).send(_contributions);
        require(success, "Withdrawal failed");
        emit Withdraw(Foundation, _contributions, block.timestamp);
    }

    /**
     * @notice Calculates the amount of tokens allocated for the presale.
     * @return The amount of tokens available for the presale.
     */
    function _tokensForPresale() internal view returns (uint256) {
        return pool.options.tokenDeposit - pool.tokensClaimable;
    }

    /**
     * @notice get user ETH contribution
     * @param _address The address of the contributor.
     * @return The amount of tokens claimable by the contributor.
     */
    function getBalance(address _address) public view returns (uint256) {
        return contributions[_address];
    }

    /**
     * @notice Calculates the amount of tokens claimable by a contributor.
     * @param contributor The address of the contributor.
     * @return The amount of tokens claimable by the contributor.
     */
    function userTokens(address contributor) public view returns (uint256) {
        return (contributions[contributor] * (pool.options.tokenprice));
    }

    /// @notice Canceled or NOT softcapped and expired
    modifier onlyRefundable() {
        if ((pool.state != 3) && (block.timestamp > pool.options.end) && (pool.ETHRaised < pool.options.softCap)) {
            revert NotRefundable();
        }
        _;
    }
}
