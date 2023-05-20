// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./GlitchERC20.sol";
import "./libraries/TransferHelper.sol";

contract Article_DAO is GlitchERC20 {
    struct Member {
        address _address;
        uint votes;
        uint challenges;
    }

    // 투표결과
    enum VotingResult {
        FOR,
        AGAINST,
        END,
        NONE
    }

    // 여러 아티클 중에서 하나만 투표하기.
    struct Article {
        address writerAddress;
        uint articleid;
        string url;
        uint voteFor;
    }

    struct Writer {
        address _address;
        string twitterHandle;
    }

    struct Challenge {
        address challenger;
        bool resolved;
        uint stake;
        uint rewardPool;
        uint totalTokens;
    }
    struct Voter {
        uint tokenstake;
        uint votes;
        uint challenges;
        uint weights;
        bool voteFor; // true = 찬성, false = 반대
        bool voted;
    }

    struct WriterRegistry {
        address writer;
        uint stake;
        uint p_expiry; //참가인원 신청 만료시간
        uint voteFor;
        uint voteAgainst;
        uint voteForstake;
        uint voteAgainststake;
        uint totalstake;
        uint totalvotes;
        uint totalchallenges;
        VotingResult votingResult;
    }

    struct Proposal {
        address proposer;
        uint stake;
        uint p_expiry; //참가인원 신청 만료시간
        uint vstartTime; //투표 시작시간
        uint totalstake;
        uint totalvotes;
        uint totalchallenges;
        Article[] articles;
    }

    uint public constant DECIMALS = 10000; // 확률 소수 4째자리까지 표현

    // t = 찬성 , f = 반대  tt = 찬성 -> 찬성 횟수 , tf = 찬성 -> 반대 횟수 , ft = 반대 -> 찬성 횟수 , ff = 반대 -> 반대 횟수
    // pi_0 = 시스템이 찬성으로 판단할 확률 = 마코브체인 가정 한 경우의 찬성 확률
    uint private _tt = 1;
    uint private _tf = 1;
    uint private _ft = 1;
    uint private _ff = 1;
    uint public _pi_quorum = (DECIMALS * 5) / 10; // 0.5

    bool[] private _voteresult; // 투표 결과 저장

    uint[] public wRegisterids; // writerRegistry 조회용 id 저장
    mapping(uint => WriterRegistry) public writerRegistries;
    uint[] public proposalids; // proposal 조회용 id 저장
    mapping(uint => Proposal) public proposals;

    mapping(address => Member) public members; //dao member 정보 등록
    mapping(address => bool) public writers; // true = writer 등록완료

    // id => (투표자주소 => 투표자 정보 등록)
    mapping(uint => mapping(address => Voter)) private _wvoters;
    mapping(uint => mapping(address => Voter)) private _avoters;

    uint public VOTINGEXPIRY = 100; // 투표 기간
    uint public CHALLEGEEXPIRY = 100; // 챌린지 기간

    function propose(uint _expiry, uint _voteStartTime) external payable {
        require(_expiry < _voteStartTime, "Invalid time");
        uint stake = msg.value;
        uint proposalId = proposalids.length;
        proposalids.push(proposalId);
        Proposal storage proposal = proposals[proposalId];
        proposal.proposer = msg.sender;
        proposal.stake = stake;
        proposal.p_expiry = _expiry;
        proposal.vstartTime = _voteStartTime;
    }

    // 작가 화이트리스트 요청
    function writerRegister(uint _expiry) external payable {
        require(block.timestamp < _expiry, "Invalid time");
        require(writers[msg.sender] == false, "Already registered");
        uint stake = msg.value;
        uint wRegisterid = wRegisterids.length;
        wRegisterids.push(wRegisterid);
        writerRegistries[wRegisterid] = WriterRegistry({
            writer: msg.sender,
            stake: stake,
            p_expiry: _expiry,
            voteFor: 0,
            voteAgainst: 0,
            voteForstake: 0,
            voteAgainststake: 0,
            totalstake: 0,
            totalvotes: 1,
            totalchallenges: 1,
            votingResult: VotingResult.NONE
        });
    }

    // 작가 화이트리스트 투표
    function voteRegister(uint wRegisterID, bool voteFor) external {
        WriterRegistry memory writerRegistry = writerRegistries[wRegisterID]; // 가스 절약
        require(
            writerRegistry.p_expiry + VOTINGEXPIRY > block.timestamp,
            "Voting expired"
        );
        require(
            writerRegistry.p_expiry < block.timestamp,
            "Application not expired"
        );
        Voter memory voter = _wvoters[wRegisterID][msg.sender]; // 가스 절약
        require(voter.voted == false, "Already voted");
        uint weights = (DECIMALS * voter.tokenstake) /
            writerRegistry.totalstake +
            (DECIMALS * voter.votes) /
            writerRegistry.totalvotes +
            (DECIMALS * voter.challenges) /
            writerRegistry.totalchallenges;
        _wvoters[wRegisterID][msg.sender].weights = weights;
        if (voteFor) {
            writerRegistries[wRegisterID].voteFor += weights;
            writerRegistries[wRegisterID].voteForstake += voter.tokenstake;
        } else {
            writerRegistries[wRegisterID].voteAgainst += weights;
            writerRegistries[wRegisterID].voteAgainststake += voter.tokenstake;
            _wvoters[wRegisterID][msg.sender].voteFor = false;
        }
        _wvoters[wRegisterID][msg.sender].weights = weights;
        _wvoters[wRegisterID][msg.sender].voted = true;
        members[msg.sender].votes += 1;
    }

    // 아티클 순위 투표
    function voteRanking(uint proposalid, uint articleid) external {
        Proposal memory proposal = proposals[proposalid]; // gas 절약
        require(
            proposal.p_expiry + VOTINGEXPIRY > block.timestamp,
            "Voting expired"
        );
        require(proposal.p_expiry < block.timestamp, "Application not expired");
        Voter memory voter = _avoters[proposalid][msg.sender]; // gas 절약
        require(voter.voted == false, "Already voted");
        uint weights = (DECIMALS * voter.tokenstake) /
            proposal.totalstake +
            (DECIMALS * voter.votes) /
            proposal.totalvotes +
            (DECIMALS * voter.challenges) /
            proposal.totalchallenges;
        _avoters[proposalid][msg.sender].weights = weights;
        proposals[proposalid].articles[articleid].voteFor += weights;
    }

    // 작가가 Proposal에 아티클 등록
    function articleRegister(uint proposalid, string calldata url) external {
        require(writers[msg.sender], "Not a writer");
        require(
            proposals[proposalid].p_expiry < block.timestamp,
            "Application not expired"
        );
        uint articleid = proposals[proposalid].articles.length;
        proposals[proposalid].articles.push(
            Article({
                writerAddress: msg.sender,
                articleid: articleid,
                url: url,
                voteFor: 0
            })
        );
    }

    // writeRegister 투표 종료시키기 후 보상
    function claimRewardW(uint wregisterid) external {
        WriterRegistry memory writerRegistry = writerRegistries[wregisterid]; // gas 절약
        Voter memory voter = _wvoters[wregisterid][msg.sender]; // gas 절약
        require(voter.voted, "Not voted");
        if (writerRegistry.votingResult == VotingResult.NONE) {
            _endwregistervote(wregisterid);
        }
        WriterRegistry memory writerRegistry_u = writerRegistries[wregisterid]; // updated된 값
        if (
            writerRegistry_u.votingResult == VotingResult.FOR && voter.voteFor
        ) {
            uint reward = voter.tokenstake +
                ((writerRegistry_u.voteAgainststake * voter.weights) /
                    writerRegistry_u.voteFor);
            TransferHelper.safeTransfer(address(this), msg.sender, reward);
        } else if (
            writerRegistry_u.votingResult == VotingResult.AGAINST &&
            !voter.voteFor
        ) {
            uint reward = voter.tokenstake +
                ((writerRegistry_u.voteForstake * voter.weights) /
                    writerRegistry_u.voteAgainst);
            TransferHelper.safeTransfer(address(this), msg.sender, reward);
        }
    }

    // 작가 TCR투표 종료하고 결과 확인
    function _endwregistervote(uint wregisterid) internal {
        WriterRegistry memory writerRegistry = writerRegistries[wregisterid]; // gas 절약
        require(
            writerRegistry.p_expiry + VOTINGEXPIRY < block.timestamp,
            "Voting not expired"
        );
        if (
            (DECIMALS * writerRegistry.voteFor) /
                (writerRegistry.voteFor + writerRegistry.voteAgainst) >=
            _pi_quorum
        ) {
            writerRegistries[wregisterid].votingResult = VotingResult.FOR;
            _updateforprob();
            _voteresult.push(true);
            writers[writerRegistry.writer] = true;
        } else {
            writerRegistries[wregisterid].votingResult = VotingResult.AGAINST;
            _updateagainstprob();
            _voteresult.push(false);
        }
    }

    //
    function claimRewardA() external {
        
    }

    // article투표 종료하고 결과확인
    function _endarticlevote() internal {

    }

    //작가 리스트에 대한 challenge
    function challenge() external {

    }

    function wVoteParticipate(uint wregisterid, uint stake) external {
        require(
            writerRegistries[wregisterid].p_expiry > block.timestamp,
            "Application expired"
        );
        Member memory member = members[msg.sender]; // gas 절약
        TransferHelper.safeTransferFrom(
            address(this),
            msg.sender,
            address(this),
            stake
        );
        _wvoters[wregisterid][msg.sender] = Voter({
            tokenstake: stake,
            votes: member.votes,
            challenges: member.challenges,
            weights: 0,
            voteFor: true,
            voted: false
        });
        writerRegistries[wregisterid].totalstake += stake;
        writerRegistries[wregisterid].totalchallenges += member.challenges;
        writerRegistries[wregisterid].totalvotes += member.votes;
    }

    function aVoteParticipate(uint proposalid, uint stake) external {
        TransferHelper.safeTransferFrom(
            address(this),
            msg.sender,
            address(this),
            stake
        );
        require(
            proposals[proposalid].p_expiry > block.timestamp,
            "Application expired"
        );
        Member memory member = members[msg.sender]; // gas절약
        _avoters[proposalid][msg.sender] = Voter({
            tokenstake: stake,
            votes: member.votes,
            challenges: member.challenges,
            weights: 0,
            voteFor: true,
            voted: false
        });
        proposals[proposalid].totalstake += stake;
        proposals[proposalid].totalchallenges += member.challenges;
        proposals[proposalid].totalvotes += member.votes;
    }

    function _updateforprob() internal {
        bool[] memory voteresult = _voteresult;
        if (voteresult.length == 0) {
            return;
        }
        if (voteresult[voteresult.length - 1] == true) {
            _tt += 1;
        } else {
            _ft += 1;
        }
        uint a = (DECIMALS * _tt) / (_tt + _tf);
        uint b = (DECIMALS * _ft) / (_ft + _ff);
        _pi_quorum = (DECIMALS * b) / (b + DECIMALS - a);
    }

    function _updateagainstprob() internal {
        bool[] memory voteresult = _voteresult;
        if (voteresult.length == 0) {
            return;
        }
        if (voteresult[voteresult.length - 1] == true) {
            _tf += 1;
        } else {
            _ff += 1;
        }
        uint c = (DECIMALS * _tf) / (_tt + _tf);
        uint d = (DECIMALS * _ff) / (_ft + _ff);
        _pi_quorum = DECIMALS - ((DECIMALS * d) / (d + DECIMALS - c));
    }

    function getETH() external {
        uint eth = address(this).balance;
        uint swapratio = (DECIMALS * balanceOf(msg.sender)) / totalSupply();
        uint reward = (eth * swapratio) / DECIMALS;
        TransferHelper.safeTransferETH(msg.sender, reward);
    }

}
