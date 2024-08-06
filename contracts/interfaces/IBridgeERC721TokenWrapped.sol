// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.20;

interface IBridgeERC721TokenWrapped {
    function mpTokenId2InscriptionId(uint256 tokenId) external view returns(string memory);
}
