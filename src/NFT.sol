// SPDX-License-Identifier: MIT

// @title NFT
// @description NFT contract where tokenURI is <baseURI>/<tokenId>

pragma solidity ^0.8.6; // TODO Upgrade when JB upgrade is onchain

import "@rari-capital/solmate/src/tokens/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import "@jbx-protocol/contracts-v2/contracts/interfaces/IJBTokenStore.sol";
import "@jbx-protocol/contracts-v2/contracts/abstract/JBOperatable.sol";
import "./structs/JBRedeemData.sol";
/*//////////////////////////////////////////////////////////////
                                ERRORS
//////////////////////////////////////////////////////////////*/
error METADATA_IS_IMMUTABLE();
error MAX_SUPPLY_REACHED();

contract NFT is ERC721, Ownable, ReentrancyGuard, JBOperatable {
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
    uint256 public constant REDEEM_PERMISSION_INDEX = 2;
    IJBTokenStore public immutable jbTokenStore;
    uint256 public immutable projectId; // Juicebox project id that will receive auction proceeds
    uint256 public immutable maxSupply; // Maximum issuance of NFTs. 0 means unlimited.
    uint256 public nextTokenId = 1; // Next token id to be minted id's are 1 based
    uint256 public totalSupply; // need this for the redemption accounting
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
     * @param _projectId project ID associated with the nft for redemption
     * @param _jbTokenStore jbtoken store instance
     * @param _operatorStore operator store instance for checking operator permission
     */
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _uri,
        address _minter,
        uint256 _maxSupply,
        uint256 _projectId,
        IJBTokenStore _jbTokenStore,
        IJBOperatorStore _operatorStore
    ) JBOperatable(_operatorStore) ERC721(_name, _symbol) {
        _setBaseURI(_uri);
        _setMinter(_minter);
        maxSupply = _maxSupply;
        projectId = _projectId;
        jbTokenStore = _jbTokenStore;
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

   /**
    @dev Mints the nft.
    @param _recipient address to mint to
    */
    function mint(address _recipient)
        external
        onlyMinter
        whenMintingIsActive
        nonReentrant
    {
        if (isMaxSupplyReached()) {
            revert MAX_SUPPLY_REACHED();
        }

        _mint(_recipient, nextTokenId);

        unchecked {
            ++nextTokenId;
            ++totalSupply;
        }
    }

   /**
    @dev Redeems the nft for the terminal tokens eth/erc20.
    @param _redeemData redeem data
    @dev The amount to redeem depends on total supply and it is only updated in this & mint method any nft's burnt outside of this contract are out of scope and have no affect on the redemption amount.
    */
    function redeemToken(JBRedeemData calldata _redeemData)
        external
        nonReentrant
        requirePermission(
            ownerOf(_redeemData.tokenId),
            projectId,
            REDEEM_PERMISSION_INDEX
        )
    {
        IJBToken token = jbTokenStore.tokenOf(projectId);
        uint256 amountToRedeem = token.balanceOf(address(this), projectId) /
            totalSupply;

        _redeemData.terminal.redeemTokensOf(
            address(this),
            projectId,
            amountToRedeem,
            _redeemData.token,
            _redeemData.minReturnedTokens,
            _redeemData.beneficiary,
            _redeemData.memo,
            _redeemData.metadata
        );

        unchecked {
            --totalSupply;
        }
        _burn(_redeemData.tokenId);
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
