// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IiLayerVerifier} from "@ilayer/interfaces/IiLayerVerifier.sol";
import {iLayerMessage} from "@ilayer/libraries/iLayerCCMLibrary.sol";

/// Mock Verifier that returns true for all non-empty proofs.
contract MockiLayerVerifier is IiLayerVerifier {
    address public router;

    function verifyMessage(iLayerMessage calldata, /* message */ bytes calldata proof)
        external
        pure
        override
        returns (bool)
    {
        return proof.length > 0;
    }

    function verifyMessages(iLayerMessage[] calldata, /* messages */ bytes calldata proof)
        external
        pure
        override
        returns (bool)
    {
        return proof.length > 0;
    }

    function setRouter(address _router) external override {
        require(_router != address(0), "Router address cannot be zero");
        router = _router;
    }
}
