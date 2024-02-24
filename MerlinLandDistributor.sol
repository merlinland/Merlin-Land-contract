// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}


interface IMerlinLand {
    function setSkipMerlinLandDistributor(address MerlinLandDistributor, bool skip) external;
}

contract MerlinLandDistributor {
    IERC20 public token;
    IMerlinLand public merlinLand; 
    uint256 public constant MintLimitPerWallet = 10 * 10 ** 18;
    uint256 public constant InitialTotalSupply = 576 * 576 * 10 ** 18;
    address public owner;

    constructor(address _tokenAddress, address _merlinLandAddress) {
        token = IERC20(_tokenAddress);
        merlinLand = IMerlinLand(_merlinLandAddress); 
        owner = msg.sender; 
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    function mint() public {
        uint256 userLandBalance = token.balanceOf(msg.sender);
        require(userLandBalance < MintLimitPerWallet, "Cannot hold more than 10 Merlin Land");
        merlinLand.setSkipMerlinLandDistributor(msg.sender, true);
        bool sent = token.transfer(msg.sender, 1 * 10 ** 18);
        require(sent, "Land transfer failed");
        merlinLand.setSkipMerlinLandDistributor(msg.sender, false);
    }

    function totalSupply() public view returns (uint256) {
        uint256 remainingSupplyInContract = token.balanceOf(address(this));
        return InitialTotalSupply - remainingSupplyInContract;
    }
}
