// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/////////////
///Imports///
/////////////
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

////////////
///Errors///
////////////
error SBFunctions_UnexpectedRequestID(bytes32 requestId);
error SBFunctions_YouDontHaveAnyBetInThisGame();
error SBFunctions_EmptyArgs();

///////////////////////////
///Interfaces, Libraries///
///////////////////////////

contract SBFunctions is FunctionsClient, Ownable{
    using FunctionsRequest for FunctionsRequest.Request;
    using SafeERC20 for IERC20;

    ///////////////////////
    ///Type declarations///
    ///////////////////////
    enum BetStatus {
        Winner,
        Loser,
        Ongoing
    }
    
    struct GamesToBet{
        string fixture;
        string winnerTeam;
    }

    struct SmartBet{
        uint256 betDate;
        uint256 matchId;
        string team;
        uint256 amountBet;
        uint256 possibleEarnings;
        BetStatus status;
    }

    struct FunctionsResponse{
        bytes lastResponse;
        bytes lastError;
        uint256 betId;
        bool exists;
    }

    /////////////
    ///Storage///
    /////////////
    mapping(uint256 matchId => GamesToBet) public s_games;
    mapping(uint256 betId => address[] bettors) public s_bettors;
    mapping(address user => mapping(uint256 betId => SmartBet)) public s_smartBet;
    mapping(bytes32 requestId => FunctionsResponse) public s_functionsRequest;

    ///////////////
    ///Variables///
    ///////////////
    uint256 private s_betId;

    ///@notice Java Script code to interact with API
    string private constant GET =
        "const response = await Functions.makeHttpRequest({"
        "url: `LINK-AQUI`,"
        "method: 'GET',"
        "});"
        "if (response.error) {"
        "  throw Error(`Request failed message ${response.message}`);"
        "}"
        "const { data } = response;"
        "return Functions.encodeString(data);"
    ;

    ///@notice Magic Number Removal
    uint256 private constant ONE = 1;
    ///@notice the token accepted for payments
    address private immutable i_bet;
    ///@notice Chainlink Functions donID
    bytes32 private immutable i_donID;
    ///@notice Chainlink Functions Subscription ID
    uint64 private immutable i_subscriptionId;
    ///@notice Chainlink Function Gas Limit
    uint32 private constant GAS_LIMIT = 300_000;

    ////////////
    ///Events///
    ////////////
    event SBFunctions_BetCreated(uint256 matchId);
    event SBFunctions_NewBetCreated(uint256 betId, address bettor, uint256 amountBet);
    event SBFunctions_Response(bytes32 indexed requestId, bytes response, bytes err);

    ///////////////
    ///Modifiers///
    ///////////////

    ///////////////
    ///Functions///
    ///////////////

    /////////////////
    ///constructor///
    /////////////////
    /**
     * 
     * @param _router Chainlink Functions Router Address
     * @param _donId Chainlink Functions DonId
     * @param _subId Chainlink Functions Subscription Id
     * @param _owner Chainlink Functions Contract Owner
    */
    constructor(address _router, bytes32 _donId, uint64 _subId, address _owner, address _bet) FunctionsClient(_router) Ownable(_owner) {
        i_donID = _donId;
        i_subscriptionId = _subId;
        i_bet = _bet;
    }

    ///////////////////////
    ///receive function ///
    ///fallback function///
    ///////////////////////

    //////////////
    ///external///
    //////////////
    /**
     * @notice Function to create new bets
     * @param _matchId the Id of the match
     * @param _fixture the team of the fixture team
     * @param _teamWinner the winner team
     */
    function createBet(
        uint256 _matchId,
        string memory _fixture,
        string memory _teamWinner
    ) external onlyOwner {
        s_games[_matchId] = GamesToBet({
            fixture: _fixture,
            winnerTeam: _teamWinner
        });

        emit SBFunctions_BetCreated(_matchId);
    }

    function bet(
        uint256 _matchId,
        string memory _team, 
        uint256 _amountBet, 
        uint256 _possibleEarnings
    ) external returns(uint256 betId){
        SmartBet memory smartBet = SmartBet({
            betDate: block.timestamp,
            matchId: _matchId,
            team: _team,
            amountBet: _amountBet,
            possibleEarnings: _possibleEarnings,
            status: BetStatus.Ongoing
        });

        s_smartBet[msg.sender][++s_betId] = (smartBet);
        s_bettors[s_betId].push(msg.sender);

        betId = s_betId;

        emit SBFunctions_NewBetCreated(s_betId, msg.sender, _amountBet);

        IERC20(i_bet).safeTransferFrom(msg.sender, address(this), _amountBet);
    }

    /**
     * @notice function for user to withdraw
     * @param _betId Id of the bet to withdraw
     */
    function winnerWithdraw(uint256 _betId) external {
        SmartBet storage smartBet = s_smartBet[msg.sender][_betId];
        GamesToBet memory game = s_games[smartBet.matchId];
        
        if(keccak256(abi.encode(smartBet.team)) == keccak256(abi.encode(game.winnerTeam))){
            smartBet.status = BetStatus.Winner;
            IERC20(i_bet).safeTransfer(msg.sender, s_smartBet[msg.sender][_betId].possibleEarnings);
        }
    }

    /**
     * @notice Sends an HTTP request for character information
     * @return requestId The ID of the request
    */
    function sendRequestToGet(
    ) external onlyOwner returns(bytes32 requestId) {

        FunctionsRequest.Request memory req;
        // Initialize the request with JS code
        req.initializeRequestForInlineJavaScript(GET);

        // Send the request and store the request ID
        requestId = _sendRequest(
            req.encodeCBOR(),
            i_subscriptionId,
            GAS_LIMIT,
            i_donID
        );

        s_functionsRequest[requestId] = FunctionsResponse ({
            lastResponse: "",
            lastError: "",
            betId: 0,
            exists: true
        });
    }

    //////////////
    ///internal///
    //////////////
    function fulfillRequest(
        bytes32 _requestId, 
        bytes memory _response, 
        bytes memory _err
    ) internal override {
        if (!s_functionsRequest[_requestId].exists) revert SBFunctions_UnexpectedRequestID(_requestId);
        
        FunctionsResponse storage request = s_functionsRequest[_requestId];

        request.lastResponse = _response;
        request.lastError = _err;

        (
            uint256 matchId, 
            string memory fixture,
            string memory teamWinner
        ) = abi.decode(_response, (uint256,string,string));

        GamesToBet storage game = s_games[matchId];
        
        game.fixture = fixture;
        game.winnerTeam = teamWinner;

        emit SBFunctions_Response(_requestId, _response, _err);
    }

    /////////////
    ///private///
    /////////////

    /////////////////
    ///view & pure///
    /////////////////
}
