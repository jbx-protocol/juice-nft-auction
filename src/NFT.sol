// SPDX-License-Identifier: MIT

// @title NFT
// @description NFT contract where tokenURI is <baseURI>/<tokenId>

pragma solidity ^0.8.6; // TODO Upgrade when JB upgrade is onchain

import "@rari-capital/solmate/src/tokens/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";

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

    /**
     * @notice Require that the minter be mutable.
     */
    modifier whenMinterIsMutable() {
        require(minterIsMutable, "Minter is immutable");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    uint256 public nextTokenId; // Next token id to be minted
    string public baseURI;
    bool public metadataFrozen;
    bool public minterIsMutable = true;
    address public minter;
    uint256 public maxSupply; // Maximum issuance of NFTs. 0 means unlimited.
    bool mintingActive = true;

    /**
     * @notice Creates a new instance of NFT
     * @param _name Name of the NFT
     * @param _symbol Symbol of the NFT
     * @param _uri Base URI of the NFT, concatenated with Token ID to create tokenURI
     * @param _minter Address of the minter
     @
     * @param _maxSupply Maximum supply of NFTs. 0 means unlimited
     * @param _oneBased If true, first tokenId is 1, otherwise 0
     */
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _uri,
        address _minter,
        bool _minterIsMutable,
        uint256 _maxSupply,
        bool _oneBased
    ) ERC721(_name, _symbol) {
        _setBaseURI(_uri);
        _setMinter(_minter);
        // TODO: Can't we just set the minter as the nft auction address with the set minter method instead of passing to the constructor, we'll also save gas with this
        minterIsMutable = _minterIsMutable;
        maxSupply = _maxSupply;
        // TODO: Why can't we just have a fixed pattern like having id's starting from 0 or 1 we can save gas by removing this check
        if (_oneBased) {
            nextTokenId = 1;
        }
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
    @dev Updates the minter
    @param newMinter New Minter address
    */
    function _setMinter(address newMinter)
        internal
        onlyOwner
        whenMinterIsMutable
    {
        minter = newMinter;
        emit MinterChanged(minter);
    }

    /**
    @dev Updates the minter if it is mutable
    @param newMinter New Minter address
    */
    function setMinter(address newMinter) external onlyOwner {
        _setMinter(newMinter);
    }

    /**
    @dev Make minter permanently immutable.
    */
    function setMinterImmutable() external onlyOwner whenMinterIsMutable {
        minterIsMutable = false;
    }

    function mint(address _recipient) external onlyMinter whenMintingIsActive {
        if (maxSupply > 0 && nextTokenId == maxSupply) {
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
