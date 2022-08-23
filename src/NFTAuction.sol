// SPDX-License-Identifier: MIT

// @title NFT Auction
// @description NFT auction contract that can be paired with any contract that implements IMintable.sol
pragma solidity ^0.8.6;

import "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import "@jbx-protocol/contracts-v2/contracts/JBETHERC20ProjectPayer.sol";
import "./interfaces/IWETH9.sol";
import "./interfaces/INFT.sol";

// Custom Errors
error ALREADY_HIGHEST_BIDDER();
error AUCTION_NOT_OVER();
error AUCTION_OVER();
error AUCTION_ALREADY_FINALIZED();
error BID_TOO_LOW();
error MAX_SUPPLY_REACHED();
error TOKEN_TRANSFER_FAILURE();

contract NFTAuction is ReentrancyGuard, JBETHERC20ProjectPayer {
    IWETH9 public immutable weth; // WETH contract address
    INFT public immutable nft;
    uint256 public immutable auctionDuration; // Duration of auctions in seconds
    uint256 public immutable projectId; // Juicebox project id that will receive auction proceeds
    uint256 public auctionEndingAt; // Current auction ending time
    uint256 public highestBid; // Current highest bid
    address public highestBidder; // Current highest bidder

    event Bid(address indexed bidder, uint256 amount);
    event NewAuction(uint256 indexed auctionEndingAt, uint256 tokenId);

    /**
        Creates a new instance of NFTAuctionMachine
        @param _nft Address of the NFT contract
        @param _duration Duration of the auction.
        @param _projectId JB Project ID of a particular project to pay to.
        @param _weth WETH contract address
        @param _jbDirectory JB Directory contract address
     */
    constructor(
        INFT _nft,
        uint256 _duration,
        uint256 _projectId,
        IWETH9 _weth,
        IJBDirectory _jbDirectory
    )
        JBETHERC20ProjectPayer(
            _projectId,
            payable(msg.sender),
            false,
            "NFT auction proceeds",
            "",
            false,
            IJBDirectory(_jbDirectory),
            address(this)
        )
    {
        nft = _nft;
        auctionDuration = _duration;
        projectId = _projectId;
        weth = _weth;
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
    @dev Allows users to bid & send eth to the contract.
    */
    function bid() public payable nonReentrant {
        // the auctionEndingAt is only set during the first bid of every id to avoid total supply incremental dependency on the nft contract
        if (auctionEndingAt != 0 && block.timestamp >= auctionEndingAt) {
            revert AUCTION_OVER();
        }
        if (msg.value < (highestBid + 0.001 ether)) {
            revert BID_TOO_LOW();
        }
        if (msg.sender == highestBidder) {
            revert ALREADY_HIGHEST_BIDDER();
        }

        // if the bid is the first bid of the auction of a new id we set the auction end time and emit the event
        if (auctionEndingAt == 0) {
            if (nft.isMaxSupplyReached()) {
                revert MAX_SUPPLY_REACHED();
            }
            auctionEndingAt = block.timestamp + auctionDuration;
            emit NewAuction(auctionEndingAt, nft.nextTokenId());
        }

        uint256 lastAmount = highestBid;
        address lastBidder = highestBidder;

        highestBid = msg.value;
        highestBidder = msg.sender;

        _transferFunds(lastBidder, lastAmount);

        emit Bid(msg.sender, msg.value);
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

        uint256 lastAmount = highestBid;
        address lastBidder = highestBidder;

        highestBid = 0;
        highestBidder = address(0);

        if (nft.isMintingActive()) {
            _pay(
                projectId, //uint256 _projectId,
                JBTokens.ETH, // address _token
                lastAmount, //uint256 _amount,
                18, //uint256 _decimals,
                lastBidder, //address _beneficiary,
                0, //uint256 _minReturnedTokens,
                false, //bool _preferClaimedTokens,
                "nft mint", //string calldata _memo, // TODO: Add your own memo here. Links to image å are displayed on the Juicebox project page as images.
                "" //bytes calldata _metadata
            );
            nft.mint(lastBidder);
        } else {
            _transferFunds(lastBidder, lastAmount);
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(JBETHERC20ProjectPayer)
        returns (bool)
    {
        return JBETHERC20ProjectPayer.supportsInterface(interfaceId);
    }
}
