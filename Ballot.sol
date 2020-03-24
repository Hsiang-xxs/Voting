pragma solidity >=0.4.22 <0.7.0;

/**
 * @title Vote with delegation.The idea is to create one contract per ballot, providing a short name for each option. 
 * Then the creator of the contract who serves as chairperson will give the right to vote to each address individually.
 * The persons behind the addresses can then choose to either vote themselves or to delegate their vote to a person they trust.
 * At the end of the voting time, winningProposal() will return the proposal with the largest number of votes.
 * 在现实生活中，投票是一个最能体现公平民主的机制，而且有广泛的应用场景。但是以往的投票过程，都或多或少存在着人为干预的风险，
 * 而区块链提供了公开透明、不可篡改的技术保障，使得利用区块链技术进行投票有着天然的可靠性。
 * 以太坊官方也给出了一个针对投票的智能合约示例 Ballot。 Ballot 合约是一个十分完整的投票智能合约，
 * 这个合约不仅支持基本的投票功能，投票人还可以将自己的投票权委托给其他人。
 * 虽然投票人身份和提案名称是由合约发布者制定的，不过这不影响投票结果的可信度。
 * 这个合约相对比较复杂，也展示出了一个去中心智能合约运作的很多特性。
 */
contract Ballot {
    // It will represent a single voter. 投票者 Voter 的数据结构
    struct Voter {
        uint weight; //weight is accumulated by delegation 该投票者的投票所占的权重
        bool voted; // if true, that person already voted 是否已经投过票
        address delegate; // person delegated to 该投票者投票权的委托对象
        uint vote; // index of the voted proposal 投票对应的提案编号
    }
    
    // This is a type for a single proposal. 提案 Proposal 的数据结构
    struct Proposal {
        bytes32 name; // short name (up to 32 bytes) 提案的名称
        uint voteCount; // number of accumulated votes 该提案目前的票数
    }
    
    // 投票的主持人
    address public chairperson;
    
    // Store a `Voter` struct for each possible address. 投票者地址与其对应的Voter结构体
    mapping(address => Voter) voters;
    
    // 提案的列表
    Proposal[] public proposals;
    
    /**
     * @dev Create a new ballot to choose one of `proposalNames`. 
     * 在初始化合约时 ， 给定一个包含多个提案名称的列表
     * 在调用 Ballot 合约的构造函数时，需要传入一个 bytes32 列表，表示投票的发起者在本场投票中提供的各个提案的名称，当然也可 以是提案的散列值。
     * 提案的具体内容没有必要存储在智能合约中，发起人通过链下的途径告知大家投票的议题和提案的内容即可 。 
     * 在智能合约中，可以只存储提案的散列值，总之有固定的机制能将提案的内容和链上所声明的提案名称一－对应即可。
     * 在合约部署的过程中， Ballot合约首先将合约的发布者地址记录在chairperson 里，
     * 作为唯一有权限添加投票人的“主持人”，同时他也默认成为参加投票 的一分子
     */
    constructor (bytes32[] memory proposalNames) public {
        chairperson = msg.sender;
        voters[chairperson].weight = 1;
        // For each of the provided proposal names, create a new proposal object and add it to the end of the array.
        // Ballot 合约将根据发布者提供的提案名称数组，使用 for 循环为每个提案名称创建一个 Proposal 类型的对象，
        // 并添加在 proposals 全局变量里 。 proposals是一个非定长的数组，因此使用 proposals.push(..）进行添加 
        for (uint i = 0; i < proposalNames.length; i++) {
            proposals.push(Proposal({
                name: proposalNames[i],
                voteCount: 0
            }));
        }
    }
    
    /// Give `voter` the right to vote on this ballot.chairperson 添加其他账户作为 Voter 
    /// May only be called by `chairperson`.
    /// @param voter 被赋予投票权的地址
    function giveRightToVote(address voter) public {
        // 调用方是否是 chairperson
        require(msg.sender == chairperson, "Only chairperson can give right to vote.");
        // voter 地址是否未投过票，或者巳授权别人
        require(!voters[voter].voted, "The voter already voted.");
        // voter 地址的权重是否为 0
        require(voters[voter].weight == 0);
        voters[voter].weight = 1;
    }
    
    // @dev 批量添加投票者
    function giveRightToVoteByBatch(address[] memory batch) public {
        require(msg.sender == chairperson, "Only chairperson can give right to vote.");
        
        for (uint i = 0; i < batch.length; i++ ) {
            address voter = batch[i];
            require(!voters[voter].voted, "The voter already voted.");
            require(voters[voter].weight == 0);
            voters[voter].weight = 1;
        }
    }
    
    /// Delegate your vote to the voter `to`.
    /// 委托投票权函数：投票者将自己的投票机会授权另外一个地址
    function delegate(address to) public {
        Voter storage sender = voters[msg.sender];
        require(!sender.voted, "You already voted.");
        require(to != msg.sender, "Self-delegation is disallowed.");
        
        while (voters[to].delegate != address(0)) {
            to = voters[to].delegate;
            require(to != msg.sender, "Found loop in delegation.");
        }
        
        sender.voted = true;
        sender.delegate = to;
        Voter storage delegate_ = voters[to];
        if (delegate_.voted) {
            // If the delegate already voted, directly add to the number of votes.
            proposals[delegate_.vote].voteCount += 1;
        } else {
            // If the delegate did not vote yet, add to her weight.
            delegate_.weight += sender.weight;
        }
    }
    
    /// Give your vote (including votes delegated to you) to proposal `proposals[proposal].name`.
    /// 投票函数：投票者根据提案列表编号进行投票
    function vote(uint proposal) public {
        Voter storage sender = voters[msg.sender];
        require(sender.weight != 0, "Has no right to vote.");
        require(!sender.voted, "Already voted.");
        sender.voted = true;
        sender.vote = proposal;
        
        // If `proposal` is out of the range of the array, this will throw automatically and revert all changes.
        proposals[proposal].voteCount += sender.weight;
    }
    
    /// @dev Computes the winning proposal taking all previous votes into account.
    /// 根据 proposals 里的票数统计计算出票数最多的提案编号
    function winningProposal() public view returns(uint[] memory winners) {
        winners = new uint[](proposals.length);
        uint winningVoteCount = 0;
        uint winningCount = 0;
        for (uint p = 0; p < proposals.length; p++) {
            if (proposals[p].voteCount > winningVoteCount) {
               winningVoteCount = proposals[p].voteCount;
               winners[0] = p;
               winningCount = 1;
            } else if (proposals[p].voteCount == winningVoteCount) {
               winners[winningCount] = p;
               winningCount++;
            }
        }
    }
    
    /// Calls winningProposal() function to get the index of the winner contained in the proposals array 
    /// and then returns the name of the winner. 返回得票最多的提案名称
    function winnerName() public view returns(bytes32[] memory winnerNames) {
        uint[] memory winners_ = winningProposal();
        winnerNames = new bytes32[](winners_.length);
        for (uint q = 0; q < winners_.length; q++) {
            winnerNames[q] = proposals[winners_[q]].name;
        }
    }
}
