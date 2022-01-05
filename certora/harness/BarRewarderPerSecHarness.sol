pragma solidity 0.6.12;

import '../munged/rewarders/BarRewarderPerSec.sol';

contract BarRewarderPerSecHarness is BarRewarderPerSec {
    constructor(IERC20 _joe, uint256 _apr) public BarRewarderPerSec(_joe,_apr) {
    }
}
