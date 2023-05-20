// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

interface IGlitch{
    function proposeReward(uint reward, uint endblocktime) external returns (bool);

    function proposeArticle(string memory url) external returns (bool);

    function vote() external returns (bool);

    function claimReward(uint amount) external returns (bool);

}