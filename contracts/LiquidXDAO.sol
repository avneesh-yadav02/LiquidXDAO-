// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title LiquidX DAO
 * @dev A decentralized autonomous organization for liquidity management and governance
 */

// LiquidX Governance Token
contract LiquidXToken is ERC20, Ownable {
    constructor(uint256 initialSupply) ERC20("LiquidX Token", "LQX") Ownable(msg.sender) {
        _mint(msg.sender, initialSupply * 10 ** decimals());
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}

// Main DAO Contract
contract LiquidXDAO is ReentrancyGuard {
    LiquidXToken public governanceToken;
    
    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        uint256 amount;
        address payable recipient;
        uint256 voteCount;
        uint256 voteAgainst;
        uint256 deadline;
        bool executed;
        bool exists;
        mapping(address => bool) voters;
    }
    
    struct Member {
        address memberAddress;
        uint256 joinDate;
        uint256 reputation;
        bool isActive;
    }
    
    mapping(uint256 => Proposal) public proposals;
    mapping(address => Member) public members;
    mapping(address => uint256) public stakingBalance;
    
    address[] public memberList;
    uint256 public proposalCount;
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant QUORUM_PERCENTAGE = 51;
    uint256 public constant MIN_STAKE_AMOUNT = 100 * 10**18; // 100 LQX tokens
    uint256 public treasuryBalance;
    
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string description,
        uint256 amount,
        address recipient
    );
    
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 weight
    );
    
    event ProposalExecuted(uint256 indexed proposalId, bool success);
    event MemberJoined(address indexed member, uint256 timestamp);
    event TokensStaked(address indexed member, uint256 amount);
    event TokensUnstaked(address indexed member, uint256 amount);
    event FundsDeposited(address indexed depositor, uint256 amount);
    
    modifier onlyMember() {
        require(members[msg.sender].isActive, "Not an active member");
        _;
    }
    
    modifier onlyStaker() {
        require(stakingBalance[msg.sender] >= MIN_STAKE_AMOUNT, "Insufficient stake");
        _;
    }
    
    constructor(address _tokenAddress) {
        governanceToken = LiquidXToken(_tokenAddress);
    }
    
    /**
     * @dev Join the DAO as a member
     */
    function joinDAO() external {
        require(!members[msg.sender].isActive, "Already a member");
        require(
            governanceToken.balanceOf(msg.sender) >= MIN_STAKE_AMOUNT,
            "Insufficient token balance"
        );
        
        members[msg.sender] = Member({
            memberAddress: msg.sender,
            joinDate: block.timestamp,
            reputation: 0,
            isActive: true
        });
        
        memberList.push(msg.sender);
        emit MemberJoined(msg.sender, block.timestamp);
    }
    
    /**
     * @dev Stake tokens to gain voting power
     */
    function stakeTokens(uint256 amount) external onlyMember nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(
            governanceToken.transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );
        
        stakingBalance[msg.sender] += amount;
        emit TokensStaked(msg.sender, amount);
    }
    
    /**
     * @dev Unstake tokens (requires no active votes)
     */
    function unstakeTokens(uint256 amount) external onlyMember nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(stakingBalance[msg.sender] >= amount, "Insufficient staked balance");
        
        stakingBalance[msg.sender] -= amount;
        require(
            governanceToken.transfer(msg.sender, amount),
            "Token transfer failed"
        );
        
        emit TokensUnstaked(msg.sender, amount);
    }
    
    /**
     * @dev Create a new proposal
     */
    function createProposal(
        string memory description,
        uint256 amount,
        address payable recipient
    ) external onlyMember onlyStaker returns (uint256) {
        proposalCount++;
        
        Proposal storage newProposal = proposals[proposalCount];
        newProposal.id = proposalCount;
        newProposal.proposer = msg.sender;
        newProposal.description = description;
        newProposal.amount = amount;
        newProposal.recipient = recipient;
        newProposal.voteCount = 0;
        newProposal.voteAgainst = 0;
        newProposal.deadline = block.timestamp + VOTING_PERIOD;
        newProposal.executed = false;
        newProposal.exists = true;
        
        emit ProposalCreated(proposalCount, msg.sender, description, amount, recipient);
        return proposalCount;
    }
    
    /**
     * @dev Vote on a proposal
     */
    function vote(uint256 proposalId, bool support) external onlyMember onlyStaker {
        Proposal storage proposal = proposals[proposalId];
        
        require(proposal.exists, "Proposal does not exist");
        require(block.timestamp <= proposal.deadline, "Voting period ended");
        require(!proposal.voters[msg.sender], "Already voted");
        require(!proposal.executed, "Proposal already executed");
        
        uint256 votingPower = stakingBalance[msg.sender];
        proposal.voters[msg.sender] = true;
        
        if (support) {
            proposal.voteCount += votingPower;
        } else {
            proposal.voteAgainst += votingPower;
        }
        
        emit VoteCast(proposalId, msg.sender, support, votingPower);
    }
    
    /**
     * @dev Execute a proposal if it passes
     */
    function executeProposal(uint256 proposalId) external nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        
        require(proposal.exists, "Proposal does not exist");
        require(block.timestamp > proposal.deadline, "Voting period not ended");
        require(!proposal.executed, "Proposal already executed");
        
        uint256 totalVotes = proposal.voteCount + proposal.voteAgainst;
        require(totalVotes > 0, "No votes cast");
        
        uint256 supportPercentage = (proposal.voteCount * 100) / totalVotes;
        require(supportPercentage >= QUORUM_PERCENTAGE, "Quorum not reached");
        
        proposal.executed = true;
        
        if (proposal.amount > 0) {
            require(treasuryBalance >= proposal.amount, "Insufficient treasury funds");
            treasuryBalance -= proposal.amount;
            (bool success, ) = proposal.recipient.call{value: proposal.amount}("");
            require(success, "Transfer failed");
        }
        
        // Increase proposer reputation
        members[proposal.proposer].reputation += 1;
        
        emit ProposalExecuted(proposalId, true);
    }
    
    /**
     * @dev Deposit funds to DAO treasury
     */
    function depositToTreasury() external payable {
        require(msg.value > 0, "Must send ETH");
        treasuryBalance += msg.value;
        emit FundsDeposited(msg.sender, msg.value);
    }
    
    /**
     * @dev Get proposal details
     */
    function getProposal(uint256 proposalId) external view returns (
        uint256 id,
        address proposer,
        string memory description,
        uint256 amount,
        address recipient,
        uint256 voteCount,
        uint256 voteAgainst,
        uint256 deadline,
        bool executed
    ) {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.id,
            proposal.proposer,
            proposal.description,
            proposal.amount,
            proposal.recipient,
            proposal.voteCount,
            proposal.voteAgainst,
            proposal.deadline,
            proposal.executed
        );
    }
    
    /**
     * @dev Check if address has voted on proposal
     */
    function hasVoted(uint256 proposalId, address voter) external view returns (bool) {
        return proposals[proposalId].voters[voter];
    }
    
    /**
     * @dev Get member count
     */
    function getMemberCount() external view returns (uint256) {
        return memberList.length;
    }
    
    /**
     * @dev Get voting power of an address
     */
    function getVotingPower(address member) external view returns (uint256) {
        return stakingBalance[member];
    }
    
    /**
     * @dev Receive function to accept ETH
     */
    receive() external payable {
        treasuryBalance += msg.value;
        emit FundsDeposited(msg.sender, msg.value);
    }
}
