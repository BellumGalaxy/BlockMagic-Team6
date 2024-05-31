// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {SBFunctions} from "../src/SBFunctions.sol";
import {SBFunctionsDeploy} from "../script/SBFunctionsDeploy.s.sol";

contract SBFunctionsTest is Test {
    SBFunctions public functions;

    function setUp() public {
        // functions = new Counter();
    }
}
