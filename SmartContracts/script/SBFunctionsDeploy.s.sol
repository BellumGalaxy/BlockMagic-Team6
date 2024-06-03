// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {SBFunctions} from "../src/SBFunctions.sol";

contract SBFunctionsDeploy is Script {
    
    function run(address _router, bytes32 _donId, uint64 _subId, address _owner, address _bet) public returns(SBFunctions functions){
        vm.broadcast();
        functions = new SBFunctions(_router, _donId, _subId, _owner, _bet);
    }
}
