// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Batch, Broker} from "@sablier/v2-periphery/src/types/DataTypes.sol";
import { IERC20 } from "@sablier/v2-core/src/types/Tokens.sol";

struct AddStreamsData {
    uint256 total;
    IERC20 token;
    Batch.CreateWithDurations[] linWithDur; 
    Batch.CreateWithRange[] linWithRange; 
    Batch.CreateWithDeltas[] dynWithDelta; 
    Batch.CreateWithMilestones[] dynWithMiles;
}

struct DeployedStreams {
    uint256 cycleNumber;
    uint256[] linearDurStreams;
    uint256[] linearRangeStreams;
    uint256[] dynDeltaStreams;
    uint256[] dynMileStreams;
}