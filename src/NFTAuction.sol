// SPDX-License-Identifier: MIT

// @title NFT Auction
// @description NFT auction contract that can be paired with any contract that implements IMintable.sol
pragma solidity ^0.8.6;

import "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import "juice-nft-rewards/contracts/abstract/JB721Delegate.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IWETH9.sol";

// Custom Errors
error AUCTION_NOT_OVER();
error AUCTION_OVER();
error AUCTION_ALREADY_FINALIZED();
error BID_TOO_LOW();
error MAX_SUPPLY_REACHED();
error METADATA_IS_IMMUTABLE();
error TOKEN_TRANSFER_FAILURE();

contract NFTAuction is ReentrancyGuard, Ownable, JB721Delegate {
    IWETH9 public immutable weth; // WETH contract address
    uint256 public immutable auctionDuration; // Duration of auctions in seconds
    uint256 public immutable maxSupply; // Maximum issuance of NFTs. 0 means unlimited.
    uint256 public auctionEndingAt; // Current auction ending time
    uint256 public highestBid; // Current highest bid
    address public highestBidder; // Current highest bidder

    uint256 public nextTokenId = 1; // Next token id to be minted id's are 1 based
    string public baseURI; // Base URI
    bool public metadataFrozen; //Flag that indicates whther metdata can be updated or not

    event Bid(address indexed bidder, uint256 amount);
    event NewAuction(uint256 indexed auctionEndingAt, uint256 tokenId);
    // event AuctionCancelled();
    event MetadataFrozen();
    event URIChanged(string indexed newURI);

    /**
        Creates a new instance of NFTAuctionMachine
        @param _duration Duration of the auction.
        @param _weth WETH contract address
     */
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _uri,
        uint256 _projectId,
        IJBDirectory _directory,
        uint256 _duration,
        IWETH9 _weth,
        uint256 _maxSupply
    ) JB721Delegate(_projectId, _directory, _name, _symbol) {
        baseURI = _uri;
        auctionDuration = _duration;
        weth = _weth;
        maxSupply = _maxSupply;
    }

    /**
    @notice
    Set a base token URI.
    @dev
    Only the contract's owner can set the base URI.
    @param _newBaseURI The new base URI.
  */
    function setBaseUri(string memory _newBaseURI) external override onlyOwner {
        if (metadataFrozen) {
            revert METADATA_IS_IMMUTABLE();
        }
        baseURI = _newBaseURI;

        emit SetBaseUri(_newBaseURI, msg.sender);
    }

    /**
    @notice
    Set a token URI resolver.
    @dev
    Only the contract's owner can set the token URI resolver.
    We don't need this in terms of the auction nft for now, added to avoid the compilation error
    @param _tokenUriResolver The new base URI.
  */
    function setTokenUriResolver(IJBTokenUriResolver _tokenUriResolver)
        external
        view
        override
        onlyOwner
    {
        // to avoid compilation warning
        _tokenUriResolver;
    }

    /**
    @notice
    Set a contract metadata URI to contain opensea-style metadata.
    @dev
    Only the contract's owner can set the contract URI.
    We don't need this in terms of the auction nft for now, added to avoid the compilation error
    @param _contractUri The new contract URI.
  */
    function setContractUri(string calldata _contractUri)
        external
        view
        override
        onlyOwner
    {
        // to avoid compilation warning
        _contractUri;
    }

    /**
    @dev Transfers eth/weth.
    */
    function _transferFunds(address _bidder, uint256 _amount) internal {
        if (_amount > 0) {
            (bool sent, ) = _bidder.call{value: _amount, gas: 20000}("");
            if (!sent) {
                weth.deposit{value: _amount}();
                bool success = weth.transfer(_bidder, _amount);
                if (!success) {
                    revert TOKEN_TRANSFER_FAILURE();
                }
            }
        }
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
    @dev Returns time remaining in the auction.
    */
    function timeLeft() public view returns (uint256) {
        if (block.timestamp > auctionEndingAt) {
            return 0;
        } else {
            return auctionEndingAt - block.timestamp;
        }
    }

    /**
    @dev Freezes the metadata uri.
    */
    function freezeMetadataURI() external onlyOwner {
        metadataFrozen = true;
        emit MetadataFrozen();
    }

    function mint(address _recipient) internal {
        if (isMaxSupplyReached()) {
            revert MAX_SUPPLY_REACHED();
        }

        _mint(_recipient, nextTokenId);

        unchecked {
            ++nextTokenId;
        }
    }

    /** 
    @notice
    Process a received payment.
    @param _data The Juicebox standard project payment data.
  */
    function _processPayment(JBDidPayData calldata _data) internal override {
        _data; // Prevents unused var compiler and natspec complaints.
        bid(); //TODO: implement the logic when a project receieves a payhment
    }

    /**
    @dev Allows users to bid & send eth to the contract.
    */
    function bid() internal nonReentrant {
        // the auctionEndingAt is only set during the first bid of every id to avoid total supply incremental dependency on the nft contract
        if (auctionEndingAt != 0 && block.timestamp >= auctionEndingAt) {
            revert AUCTION_OVER();
        }
        if (msg.value < (highestBid + 0.001 ether)) {
            revert BID_TOO_LOW();
        }

        uint256 lastAmount = highestBid;
        address lastBidder = highestBidder;

        highestBid = msg.value;
        highestBidder = msg.sender;

        // if (auctionEndingAt != 0) _transferFunds(lastBidder, lastAmount);
        // TODO: Need to implement redemption logic for prev. bidders

        // if the bid is the first bid of the auction of a new id we set the auction end time and emit the event
        if (auctionEndingAt == 0) {
            if (isMaxSupplyReached()) {
                revert MAX_SUPPLY_REACHED();
            }
            auctionEndingAt = block.timestamp + auctionDuration;
            emit NewAuction(auctionEndingAt, nextTokenId);
        }

        emit Bid(msg.sender, msg.value);
    }

    /**
    @notice
    Part of IJBRedeemDelegate, this function gets called when the token holder redeems. It will burn the specified NFTs to reclaim from the treasury to the _data.beneficiary.
    @dev
    This function will revert if the contract calling is not one of the project's terminals.
    @param _data The Juicebox standard project redemption data.
  */
    function didRedeem(JBDidRedeemData calldata _data)
        external
        virtual
        override
    {
        _data; // to avoid compilation warn ing
        //TODO: Implement redemption logic
    }

    /**
    @dev Allows anyone to mint the nft to the highest bidder/burn if there were no bids & restart the auction with a new end time.
    */
    function finalize() public nonReentrant {
        if (block.timestamp <= auctionEndingAt) {
            revert AUCTION_NOT_OVER();
        }

        if (auctionEndingAt == 0) {
            revert AUCTION_ALREADY_FINALIZED();
        }
        // after the auction of each id is finalized ensuring we have atleast 1 bid we reset the auctionEndingAt so as to accept bids for the new id and hence start a new auction
        auctionEndingAt = 0;

        address lastBidder = highestBidder;

        highestBid = 0;
        highestBidder = address(0);

        mint(lastBidder);

        // if (isMintingActive()) {
        //     nft.mint(lastBidder);
        // } else {
        //     emit AuctionCancelled();
        //     _transferFunds(lastBidder, lastAmount);
        // }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(JB721Delegate)
        returns (bool)
    {
        return JB721Delegate.supportsInterface(interfaceId);
    }
}
