// SPDX-License-Identifier: MIT

// @title NFT
// @description NFT contract where tokenURI is <baseURI>/<tokenId>

pragma solidity ^0.8.6; // TODO Upgrade when JB upgrade is onchain

// import "@rari-capital/solmate/src/tokens/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import "juice-nft-rewards/contracts/JBTiered721Delegate.sol";

/*//////////////////////////////////////////////////////////////
                                ERRORS
//////////////////////////////////////////////////////////////*/
error METADATA_IS_IMMUTABLE();
error MAX_SUPPLY_REACHED();

contract NFT is ERC721, Ownable, ReentrancyGuard {
    using Strings for uint256;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event URIChanged(string indexed newURI);
    event MinterChanged(address indexed newMinter);
    event MetadataFrozen();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Require that the sender is the minter.
     */
    modifier onlyMinter() {
        require(msg.sender == minter, "Only designated Minter can mint");
        _;
    }

    /**
     * @notice Require that the minting is allowed.
     */
    modifier whenMintingIsActive() {
        require(mintingActive, "Minting is not active");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    uint256 public immutable maxSupply; // Maximum issuance of NFTs. 0 means unlimited.
    uint256 public nextTokenId = 1; // Next token id to be minted id's are 1 based
    string public baseURI;
    bool public metadataFrozen;
    address public minter;
    bool mintingActive = true;

    /**
     * @notice Creates a new instance of NFT
     * @param _name Name of the NFT
     * @param _symbol Symbol of the NFT
     * @param _uri Base URI of the NFT, concatenated with Token ID to create tokenURI
     * @param _minter Address of the minter
     * @param _maxSupply Maximum supply of NFTs. 0 means unlimited
     */
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _uri,
        address _minter,
        uint256 _maxSupply
    ) ERC721(_name, _symbol) {
        _setBaseURI(_uri);
        _setMinter(_minter);
        maxSupply = _maxSupply;
    }

    /*//////////////////////////////////////////////////////////////
                                METADATA
    //////////////////////////////////////////////////////////////*/

    /**
    @dev Updates the baseURI.
    @param newBaseURI New Base URI Value
    */
    function _setBaseURI(string memory newBaseURI) internal onlyOwner {
        if (metadataFrozen) {
            revert METADATA_IS_IMMUTABLE();
        }
        baseURI = newBaseURI;
        emit URIChanged(baseURI);
    }

    /**
    @dev Freezes the metadata uri.
    */
    function freezeMetadataURI() external onlyOwner {
        metadataFrozen = true;
        emit MetadataFrozen();
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        return string(abi.encodePacked(baseURI, "/", tokenId));
    }

    /*//////////////////////////////////////////////////////////////
                                MINTING
    //////////////////////////////////////////////////////////////*/

    /**
    @dev Ends minting permanently.
    */
    function endMinting() external onlyOwner whenMintingIsActive {
        mintingActive = false;
    }

    /**
    @dev Allows composable minting contracts to check if minting is active.
    @return bool True if minting is active.
    */
    function isMintingActive() external view returns (bool) {
        return mintingActive;
    }

    /**
    @dev Checks if max. supply has been reached.
    @return bool Flag indicating if max. supply has been reached.
    */
    function isMaxSupplyReached() public view returns (bool) {
        if (maxSupply > 0 && nextTokenId == maxSupply) {
            return true;
        } else {
            return false;
        }
    }

    /**
    @dev Updates the minter
    @param newMinter New Minter address
    */
    function _setMinter(address newMinter) internal onlyOwner {
        minter = newMinter;
        emit MinterChanged(minter);
    }

    /**
    @dev Updates the minter
    @param newMinter New Minter address
    */
    function setMinter(address newMinter) external onlyOwner {
        _setMinter(newMinter);
    }

    function mint(address _recipient) external onlyMinter whenMintingIsActive {
        if (isMaxSupplyReached()) {
            revert MAX_SUPPLY_REACHED();
        }

        _mint(_recipient, nextTokenId);

        unchecked {
            ++nextTokenId;
        }
    }

    /*//////////////////////////////////////////////////////////////
                               INTERFACES
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721)
        returns (bool)
    {
        return
            // ERC721.supportsInterface(interfaceId);
            super.supportsInterface(interfaceId); // TODO Which is better?
    }
}
