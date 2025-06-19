// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { L2Pool } from "@aave/core-v3/contracts/protocol/pool/Pool.sol";
import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import { L2Encoder } from "@aave/core-v3/contracts/misc/L2Encoder.sol";

contract EHVault is BoringVault {
    IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;
    L2Pool public immutable lendingPool;
    L2Encoder public immutable encoder;
    IERC20 public immutable wrappedArbToken;
    ERC20Votes public immutable arbToken = ERC20Votes(0x912CE59144191C1204E64559FE8253a0e49E6548);
    
    address[] public delegates;
    mapping(address => uint256) public delegateArbBalance;
    mapping(address => uint256) public userDelegationBalance;

    event DelegationReceived(
        address indexed from,
        address indexed to,
        uint256 amount
    );
    event DelegationWithdrawn(
        address indexed from,
        address indexed to,
        uint256 amount
    );

    event AssetsRecalled(
        uint256 amount
    );

    event VotingWindowStarted(
        uint256 startTime,
        uint256 endTime
    );

    event VotingWindowEnded(
        uint256 endTime
    );

    event AssetsDeployed(
        address indexed asset,
        uint256 amount
    );

    constructor(
        address _owner,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _lendingPool,
        address _arbToken,
        address _wrappedArbToken,
        address _addressesProvider
    )
        BoringVault(_owner, _name, _symbol, _decimals)
    {
        ADDRESSES_PROVIDER = IPoolAddressesProvider(_addressesProvider);
        lendingPool = L2Pool(_lendingPool);
        arbToken = _arbToken;
        wrappedArbToken = IERC20(_wrappedArbToken);
        encoder = L2Encoder(lendingPool);
    }

    function addDelegate(address delegate) external requiresAuth {
        require(delegate != address(0), "Invalid delegate address");
        require(delegateArbBalance[delegate] > 0, "Delegate already exists");

        for (uint256 i = 0; i < delegates.length; i++) {
            require(delegates[i] != delegate, "Delegate already added");
        }

        delegates.push(delegate);
        delegateArbBalance[delegate] = 0;
    }

    function enter(uint256 amount, address delegate) external {
        require(arbToken.balanceOf() >= amount, "Insufficient ARB balance");
        require(delegate != address(0), "Invalid delegate address");
        require(wrappedArbToken.balanceOf(address(this)) >= amount, "Insufficient wrapped ARB balance");

        for (uint256 i = 0; i < delegates.length; i++) {
            if (delegates[i] == delegate) {
                break;
            }
            if (i == delegates.length - 1) {
                revert("Delegate not found");
            }
        }

        delegateArbBalance[delegate] += amount;
        userDelegationBalance[msg.sender] += amount;

        arbToken.transferFrom(msg.sender, address(this), amount);
        wrappedArbToken.transfer(msg.sender, amount);
        emit DelegationReceived(msg.sender, delegate, amount);

        bytes32 supplyData = encoder.encodeSupplyParams(address(arbToken), amount, 0);
        lendingPool.supply(supplyData);

        emit AssetsDeployed(address(arbToken), amount);
    }

    function exit(address delegate) external {
        require(userDelegationBalance[msg.sender] > 0, "No delegation balance");
        require(delegateArbBalance[delegate] > 0, "No delegation balance for delegate");
        require(wrappedArbToken.balanceOf(address(this)) >= userDelegationBalance[msg.sender], "Insufficient wrapped ARB balance");

        uint256 amount = userDelegationBalance[msg.sender];
        userDelegationBalance[msg.sender] = 0;
        delegateArbBalance[delegate] -= amount;

        bytes32 withdrawData = encoder.encodeWithdrawParams(address(arbToken), amount);
        lendingPool.withdraw(withdrawData);
        emit AssetsRecalled(amount);

        wrappedArbToken.transferFrom(msg.sender, address(this), amount);
        arbToken.transfer(msg.sender, amount);
        emit DelegationWithdrawn(msg.sender, delegate, amount);
    }

    function startVotingWindow() external requiresAuth {
        (uint256 totalCollateralBase, uint256 totalDebtBase, uint256 availableBorrowsBase, uint256 currrentLiquidationThreshold, uint256 ltv, uint256 healthFactor) 
            = lendingPool.getUserAccountData(address(this));
        require(totalCollateralBase > 0, "No collateral available");

        bytes32 withdrawData = encoder.encodeWithdrawParams(address(arbToken), totalCollateralBase);
        lendingPool.withdraw(withdrawData);
        emit AssetsRecalled(totalCollateralBase);

        for (uint256 i = 0; i < delegates.length; i++) {
            address delegate = delegates[i];
            uint256 delegateBalance = delegateArbBalance[delegate];
            if (delegateBalance > 0) {
                // Provide balance to the delegate to vote
                emit DelegationWithdrawn(msg.sender, delegate, delegateBalance);
            }
        }

        emit VotingWindowStarted(block.timestamp, block.timestamp + 1 days);
    }

    function endVotingWindow() external requiresAuth {
        // RECALL assets from franchiser delegations
        // TODO

        // Redeploy assets to the lending pool
        
        bytes32 supplyData = encoder.encodeSupplyParams(address(arbToken), wrappedArbToken.balanceOf(address(this)), 0);
        lendingPool.supply(supplyData);

        emit AssetsDeployed(address(arbToken), arbToken.balanceOf(address(this)));
        emit VotingWindowEnded(block.timestamp);
    }
}