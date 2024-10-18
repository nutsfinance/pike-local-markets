//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {
    IERC165,
    ERC165Checker
} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return interfaceId == type(IERC165).interfaceId;
    }
}
