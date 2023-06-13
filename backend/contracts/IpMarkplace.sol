// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract PatentNFT is ERC721, ERC721URIStorage {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    mapping(uint256 => uint256) public tokenIdToPatentId;
    mapping(uint256 => uint256) public patentIdToTokenId;

    constructor() ERC721("Patent NFT", "PNFT") {}

    /// can the mint function be called by anyone ??
    // where is the token uri ??
    function mint(address _to, uint256 _patentId , string calldata tokenURIString) external {
        require(patentIdToTokenId[_patentId] == 0, "Patent already minted as NFT");

        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();

        tokenIdToPatentId[tokenId] = _patentId;
        patentIdToTokenId[_patentId] = tokenId;
        _safeMint(_to, tokenId);
        _setTokenURI(tokenId , tokenURIString);
        
    }

    function _burn(uint256 tokenId) internal virtual override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }


}

contract PatentRegistryMarketplace is PatentNFT {
    using Counters for Counters.Counter;
    
    struct Patent {
        uint256 patentId;
        string title;
        string description;
        address inventor;
        uint256 filingDate;
        string[] documents;
        bool verified;
    }

    struct LicenseAgreement {
        uint256 agreementId;
        uint256 patentId;
        address patentOwner;
        uint256 price;
        uint256 royaltyPercentage;
        bool isApproved;
        bool isEscrowed;
        uint256 expirationDate;
    }

    struct Dispute {
        uint256 disputeId;
        uint256 patentId;
        address initiator;
        address respondent;
        string description;
        DisputeStatus status;
        mapping(address => bool) upVotes;
        mapping(address => bool ) downVotes;
        uint upVoteCount;
        uint downVoteCount;
        uint startTime;
    }

    enum DisputeStatus { Pending, Resolved }

    mapping(uint256 => Patent) private _patents;
    mapping(uint256 => string) private _tokenURIs;
    mapping(uint256 => uint256) private _patentIdToTokenId;
    mapping(uint256 => LicenseAgreement) public licenseAgreements;
    mapping(uint256 => Dispute) public disputes;
    
    uint256 private _patentIdCounter;
    uint256 public totalLicenseAgreements;
    uint256 public totalDisputes;

    event LicenseAgreementCreated(uint256 indexed agreementId, uint256 indexed patentId, address patentOwner);
    event LicenseAgreementApproved(uint256 indexed agreementId);
    event LicenseAgreementRejected(uint256 indexed agreementId);
    event RoyaltyPaid(uint256 indexed agreementId, address indexed licensee, uint256 amount);
    event DisputeInitiated(uint256 indexed disputeId, address indexed initiator, address indexed respondent);
    event DisputeResolved(uint256 indexed disputeId);

    constructor() payable {}

    // Patent Registry Functions

    function registerPatent(string memory _title, string memory _description, string[] memory _documents) public {
        uint256 patentId = _patentIdCounter;
        _patentIdCounter++;
        
        _patents[patentId] = Patent(
            patentId,
            _title,
            _description,
            msg.sender,
            block.timestamp,
            _documents,
            false
        );

        _safeMint(msg.sender, patentId);
    }

    function verifyPatent(uint256 _patentId) public payable {
        require(_exists(_patentId), "Patent does not exist");
        require(ownerOf(_patentId) == msg.sender, "You are not the patent owner");
        require(msg.value >= 1 ether , "The staked amount should be greater than 1 ether");
        
        _patents[_patentId].verified = true;
    }

    function getPatent(uint256 _patentId) public view returns (Patent memory) {
        require(_exists(_patentId), "Patent does not exist");
        return _patents[_patentId];
    }
    
    function _baseURI() internal pure override returns (string memory) {
        return "ipfs://";
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURI();

        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }
        return super.tokenURI(tokenId);
    }

    // Patent Marketplace

    function createLicenseAgreement(uint256 _patentId, uint256 _price, uint256 _royaltyPercentage, uint256 _expirationDate) public {
        totalLicenseAgreements++;
        licenseAgreements[totalLicenseAgreements] = LicenseAgreement(
            totalLicenseAgreements,
            _patentId,
            msg.sender,
            _price,
            _royaltyPercentage,
            false,
            false,
            _expirationDate
        );
        emit LicenseAgreementCreated(totalLicenseAgreements, _patentId, msg.sender);
    }

    function approveLicenseAgreement(uint256 _agreementId) public {
        LicenseAgreement storage agreement = licenseAgreements[_agreementId];
        require(agreement.patentOwner == msg.sender, "You are not the licensee");
        require(!agreement.isApproved, "License agreement is already approved");

        agreement.isApproved = true;
        emit LicenseAgreementApproved(_agreementId);
    }

    function rejectLicenseAgreement(uint256 _agreementId) public {
        LicenseAgreement storage agreement = licenseAgreements[_agreementId];
        require(agreement.patentOwner == msg.sender, "You are not the licensee");
        require(!agreement.isApproved, "License agreement is already approved");

        delete licenseAgreements[_agreementId];
        emit LicenseAgreementRejected(_agreementId);
    }

    function payRoyalty(uint256 _agreementId, uint256 _amount) public {
        LicenseAgreement storage agreement = licenseAgreements[_agreementId];
        require(agreement.isApproved, "License agreement is not approved");
        require(agreement.isEscrowed, "Funds are not in escrow");
        require(agreement.expirationDate >= block.timestamp, "License agreement has expired");

        // Transfer royalty to patent owner
        uint256 royaltyAmount = (_amount * agreement.royaltyPercentage) / 100;
        agreement.isEscrowed = false;
        payable(agreement.patentOwner).transfer(royaltyAmount);

        emit RoyaltyPaid(_agreementId, msg.sender, royaltyAmount);
    }

    // Patent Dispute Resolution
    
    function initiateDispute(uint256 _patentId, address _respondent, string calldata _description) public {
        totalDisputes++;
        Dispute storage dispute  = disputes[totalDisputes];
        dispute.patentId = _patentId;
        dispute.initiator = msg.sender;
        dispute.respondent = _respondent;
        dispute.description = _description;
        dispute.startTime = block.timestamp;

        emit DisputeInitiated(totalDisputes, msg.sender, _respondent);
    }

    function upVoteDispute(uint _disputeID ) public{
        Dispute storage dispute = disputes[_disputeID];
        require(!dispute.upVotes[msg.sender] , "Already upvoted on the Dispute");
        if(dispute.downVotes[msg.sender]){
            dispute.downVoteCount--;
        }
        dispute.downVotes[msg.sender]= false;
        dispute.upVotes[msg.sender] = true;
        dispute.upVoteCount++;
    }

    function downVoteDispute(uint _disputeID ) public{
        Dispute storage dispute = disputes[_disputeID];
        require(!dispute.downVotes[msg.sender] , "Already downVoted on the Dispute");
        if(dispute.downVotes[msg.sender]){
            dispute.upVoteCount--;
        }
        dispute.downVotes[msg.sender]= true;
        dispute.upVotes[msg.sender] = false;
        dispute.downVoteCount++;
    }
    function resolveDispute(uint256 _disputeId) public {
        Dispute storage dispute = disputes[_disputeId];
        require(dispute.status == DisputeStatus.Pending, "Dispute is not pending");
        // require(msg.sender == dispute.initiator || msg.sender == dispute.respondent, "Unauthorized resolution");
        require(dispute.startTime  + 10 days > block.timestamp , "Not enough time to resolve the dispute");
        if(dispute.upVoteCount > dispute.downVoteCount){
            // add the thing that you want to do when the dispute initator has won 
            
        }

        else{
            // add the condition where the respondant has won 
        }
        dispute.status = DisputeStatus.Resolved;
        emit DisputeResolved(_disputeId);
    }

    // Patent Expiration
    // ...

    // Patent Rating and Review
    // ...
}
