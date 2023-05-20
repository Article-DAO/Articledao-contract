// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Article_DAO.sol";

contract Article_DAO_Test is Test {
    Article_DAO public article_dao;

    function mint() public {
        article_dao = new Article_DAO();
    }
}
