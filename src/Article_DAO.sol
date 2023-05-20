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
        Writer writer;
        uint articleid;
        string url;
        uint votedweights;
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

    struct WriterRegistration {
        Writer writer;
        uint applytime;
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
        uint applytime;
        uint proposerstake;
        uint totalstake;
        uint totalvotes;
        uint totalchallenges;
        uint totalweights;
        VotingResult votingResult;
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
    mapping(uint => WriterRegistration) public writerRegistrations;
    uint[] public proposalids; // proposal 조회용 id 저장
    mapping(uint => Proposal) public proposals;
    mapping(uint => Article[]) public articles; // proposalid => article 저장

    mapping(address => Member) public members; //dao member 정보 등록
    mapping(address => Writer) public writermapping; //writer 정보 매핑
    mapping(address => bool) public writers; // true = writer 등록완료
    mapping(address => mapping(uint => uint)) public votedarticles; // proposalid => articleid => 투표한 아티클 저장

    // id => (투표자주소 => 투표자 정보 등록)
    mapping(uint => mapping(address => Voter)) private _wvoters;
    mapping(uint => mapping(address => Voter)) private _avoters;

    uint public constant PARTICIPATIONEXPIRY = 100; // 투표참여 등록 기간
    uint public constant VOTINGEXPIRY = 100; // 투표 기간
    uint public constant ARTICLEREGISTRATIONEXPIRY = 100; // 아티클 등록 기간
    uint public constant CHALLEGEEXPIRY = 100; // 챌린지 기간
    uint public constant REGISTRATIONDEPOSIT = 100; // 작가 등록 보증금

    // 작가 화이트리스트 요청
    function writerRegister(string calldata twitterhandle) external {
        require(writers[msg.sender] == false, "Already registered");
        TransferHelper.safeTransferFrom(
            address(this),
            msg.sender,
            address(this),
            REGISTRATIONDEPOSIT
        );
        uint wRegisterid = wRegisterids.length;
        wRegisterids.push(wRegisterid);

        writerRegistrations[wRegisterid] = WriterRegistration({
            writer: Writer({
                _address: msg.sender,
                twitterHandle: twitterhandle
            }),
            applytime: block.timestamp,
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

    //작가 화이트리스트 투표 참여 등록
    function wVoteParticipate(uint wregisterid, uint stake) external {
        require(
            PARTICIPATIONEXPIRY >
                block.timestamp - writerRegistrations[wregisterid].applytime,
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
        writerRegistrations[wregisterid].totalstake += stake;
        writerRegistrations[wregisterid].totalchallenges += member.challenges;
        writerRegistrations[wregisterid].totalvotes += member.votes;
    }

    // 작가 화이트리스트 투표
    function voteRegister(uint wRegisterID, bool voteFor) external {
        WriterRegistration memory writerRegistry = writerRegistrations[
            wRegisterID
        ]; // 가스 절약
        require(
            PARTICIPATIONEXPIRY + VOTINGEXPIRY >
                block.timestamp - writerRegistry.applytime,
            "Voting expired"
        );
        require(
            PARTICIPATIONEXPIRY < block.timestamp - writerRegistry.applytime,
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
            writerRegistrations[wRegisterID].voteFor += weights;
            writerRegistrations[wRegisterID].voteForstake += voter.tokenstake;
        } else {
            writerRegistrations[wRegisterID].voteAgainst += weights;
            writerRegistrations[wRegisterID].voteAgainststake += voter
                .tokenstake;
            _wvoters[wRegisterID][msg.sender].voteFor = false;
        }
        _wvoters[wRegisterID][msg.sender].weights = weights;
        _wvoters[wRegisterID][msg.sender].voted = true;
        members[msg.sender].votes += 1;
    }

    //DAO에게 글 작성을 제안
    function propose(uint stake) external {
        TransferHelper.safeTransferFrom(
            address(this),
            msg.sender,
            address(this),
            stake
        );
        uint proposalId = proposalids.length;
        proposalids.push(proposalId);
        proposals[proposalId] = Proposal({
            proposer: msg.sender,
            applytime: block.timestamp,
            proposerstake: stake,
            totalstake: 0,
            totalvotes: 1,
            totalchallenges: 1,
            totalweights: 0,
            votingResult: VotingResult.NONE
        });
    }

    // 해당 proposal의 아티클에 대해 투표 참여 등록
    function aVoteParticipate(uint proposalid, uint stake) external {
        TransferHelper.safeTransferFrom(
            address(this),
            msg.sender,
            address(this),
            stake
        );
        require(
            PARTICIPATIONEXPIRY >
                block.timestamp - proposals[proposalid].applytime,
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

    // 작가가 Proposal에 아티클 등록
    function articleRegister(uint proposalid, string calldata url) external {
        Proposal memory proposal = proposals[proposalid];
        require(writers[msg.sender], "Not a writer");
        require(
            PARTICIPATIONEXPIRY + ARTICLEREGISTRATIONEXPIRY >
                block.timestamp - proposal.applytime,
            "Article registration expired"
        );
        require(
            PARTICIPATIONEXPIRY < block.timestamp - proposal.applytime,
            "Application not expired"
        );
        uint articleid = articles[proposalid].length;
        articles[proposalid].push(
            Article({
                writer: writermapping[msg.sender],
                articleid: articleid,
                url: url,
                votedweights: 0
            })
        );
    }

    // 아티클 순위 투표
    function voteRanking(uint proposalid, uint articleid) external {
        votedarticles[msg.sender][proposalid] = articleid;
        Proposal memory proposal = proposals[proposalid]; // gas 절약
        require(
            PARTICIPATIONEXPIRY + ARTICLEREGISTRATIONEXPIRY + VOTINGEXPIRY >
                block.timestamp - proposal.applytime,
            "Voting expired"
        );
        require(
            PARTICIPATIONEXPIRY + ARTICLEREGISTRATIONEXPIRY <
                block.timestamp - proposal.applytime,
            "Article registration not expired"
        );
        require(
            PARTICIPATIONEXPIRY < block.timestamp - proposal.applytime,
            "Application not expired"
        );
        Voter memory voter = _avoters[proposalid][msg.sender]; // gas 절약
        require(voter.voted == false, "Already voted");
        uint weights = (DECIMALS * voter.tokenstake) /
            proposal.totalstake +
            (DECIMALS * voter.votes) /
            proposal.totalvotes +
            (DECIMALS * voter.challenges) /
            proposal.totalchallenges;
        _avoters[proposalid][msg.sender].voted = true;
        _avoters[proposalid][msg.sender].weights = weights;
        articles[proposalid][articleid].votedweights += weights;
        proposals[proposalid].totalweights += weights;
    }

    // writeRegister 투표 종료시키기 후 보상
    function claimRewardW(uint wregisterid) external {
        WriterRegistration memory writerRegistry = writerRegistrations[
            wregisterid
        ]; // gas 절약
        Voter memory voter = _wvoters[wregisterid][msg.sender]; // gas 절약
        require(voter.voted, "Not voted");
        require(
            PARTICIPATIONEXPIRY + VOTINGEXPIRY <
                block.timestamp - writerRegistry.applytime,
            "Voting not expired"
        );
        if (writerRegistry.votingResult == VotingResult.NONE) {
            _endwregistervote(wregisterid);
        }
        WriterRegistration memory writerRegistry_u = writerRegistrations[
            wregisterid
        ]; // updated된 값
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
                (((writerRegistry_u.voteForstake + REGISTRATIONDEPOSIT) *
                    voter.weights) / writerRegistry_u.voteAgainst);
            TransferHelper.safeTransfer(address(this), msg.sender, reward);
        }
    }

    // 작가 TCR투표 종료하고 결과 확인
    function _endwregistervote(uint wregisterid) internal {
        WriterRegistration memory writerRegistry = writerRegistrations[
            wregisterid
        ]; // gas 절약
        if (
            (DECIMALS * writerRegistry.voteFor) /
                (writerRegistry.voteFor + writerRegistry.voteAgainst) >=
            _pi_quorum
        ) {
            writerRegistrations[wregisterid].votingResult = VotingResult.FOR;
            _updateforprob();
            _voteresult.push(true);
            writers[writerRegistry.writer._address] = true;
            // 투표 성공시 보증금 반환
            TransferHelper.safeTransfer(
                address(this),
                writerRegistry.writer._address,
                REGISTRATIONDEPOSIT
            );
        } else {
            writerRegistrations[wregisterid].votingResult = VotingResult
                .AGAINST;
            _updateagainstprob();
            _voteresult.push(false);
        }
    }

    // article 투표 종료 후 보상
    function claimRewardA(
        uint proposalid,
        uint articleid
    ) external returns (uint rewards) {
        require(
            votedarticles[msg.sender][proposalid] == articleid,
            "You voted another article!"
        );
        Proposal memory proposal = proposals[proposalid]; // gas 절약
        Voter memory voter = _avoters[proposalid][msg.sender]; // gas 절약
        Article memory article = articles[proposalid][articleid];
        require(voter.voted, "Not voted");
        require(
            PARTICIPATIONEXPIRY + VOTINGEXPIRY <
                block.timestamp - proposal.applytime,
            "Voting not expired"
        );
        if (proposal.votingResult == VotingResult.NONE) {
            proposals[proposalid].votingResult = VotingResult.END;
        }
        Proposal memory proposal_u = proposals[proposalid]; // updated된 값
        if (proposal_u.votingResult == VotingResult.END) {
            uint articlereward = ((DECIMALS *
                (proposal_u.proposerstake + proposal_u.totalstake) *
                article.votedweights) / proposal.totalweights) / DECIMALS;
            uint rewardraito = (DECIMALS * voter.weights) /
                article.votedweights;
            uint reward = (articlereward * rewardraito) / DECIMALS;
            TransferHelper.safeTransfer(address(this), msg.sender, reward);
            rewards = articlereward;
        }
    }

    //작가 리스트에 대한 challenge
    function challenge(uint wregisterid) external {}

    //찬성이 나온 경우 update
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

    //반대가 나온 경우 update
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
}
