// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./interfaces/IBridgeERC721TokenWrapped.sol";

contract BitmapRentHelperContract is OwnableUpgradeable {
    string public constant version = "1.0.0";

    address public bitmapNFT;
    address public swapContract;

    modifier onlyValidAddress(address addr) {
        require(addr != address(0), "Illegal address");
        _;
    }

    function initialize(
        address _initialOwner,
        address _bitmapContract,
        address _swapContract
    ) external
    onlyValidAddress(_initialOwner) initializer {
        bitmapNFT = _bitmapContract;
        swapContract = _swapContract;
        __Ownable_init_unchained(_initialOwner);
    }

    /*
    * batch check if bitmaps is rent available (must be wasteLand or publicLand).
    */
    function bitmapsRentAvailable(uint256[] calldata _bitmaps) external view returns (bool) {
        require(_bitmaps.length > 0, "invalid _bitmaps length");

        for (uint16 i = 0; i < _bitmaps.length; i++) {
            if (!_bitmapRentAvailable(_bitmaps[i])) {
                return false;
            }
        }

        return true;
    }

    function _bitmapRentAvailable(uint256 _bitmap) internal view returns (bool){
        string memory inscriptionId = IBridgeERC721TokenWrapped(bitmapNFT).mpTokenId2InscriptionId(_bitmap);

        //check wasteLand
        if (bytes(inscriptionId).length == 0) {
            return true;
        }

        //check public land
        address owner = IERC721(bitmapNFT).ownerOf(_bitmap);
        if (owner == swapContract) {
            return true;
        }

        return false;
    }
}