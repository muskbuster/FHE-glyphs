/**
 *Submitted for verification at Etherscan.io on 2019-04-05
*/
import "fhevm/lib/TFHE.sol";
import "fhevm/gateway/GatewayCaller.sol";
pragma solidity ^0.8.19;

/**
 *
 *      ***    **     ** ********  *******   ******   **     **    ** ********  **     **  ******
 *     ** **   **     **    **    **     ** **    **  **      **  **  **     ** **     ** **    **
 *    **   **  **     **    **    **     ** **        **       ****   **     ** **     ** **
 *   **     ** **     **    **    **     ** **   **** **        **    ********  *********  ******
 *   ********* **     **    **    **     ** **    **  **        **    **        **     **       **
 *   **     ** **     **    **    **     ** **    **  **        **    **        **     ** **    **
 *   **     **  *******     **     *******   ******   ********  **    **        **     **  ******
 *
 *
 *                                                                by Matt Hall and John Watkinson
 *
 *
 * The output of the 'tokenURI' function is a set of instructions to make a drawing.
 * Each symbol in the output corresponds to a cell, and there are 64x64 cells arranged in a square grid.
 * The drawing can be any size, and the pen's stroke width should be between 1/5th to 1/10th the size of a cell.
 * The drawing instructions for the nine different symbols are as follows:
 *
 *   .  Draw nothing in the cell.
 *   O  Draw a circle bounded by the cell.
 *   +  Draw centered lines vertically and horizontally the length of the cell.
 *   X  Draw diagonal lines connecting opposite corners of the cell.
 *   |  Draw a centered vertical line the length of the cell.
 *   -  Draw a centered horizontal line the length of the cell.
 *   \  Draw a line connecting the top left corner of the cell to the bottom right corner.
 *   /  Draw a line connecting the bottom left corner of teh cell to the top right corner.
 *   #  Fill in the cell completely.
 *
 */
interface ERC721TokenReceiver
{

    function onERC721Received(address _operator, address _from, uint256 _tokenId, bytes memory _data) external returns(bytes4);

}

contract FHEglyphs is  GatewayCaller {

    event Generated(euint64 indexed index, address indexed a, string value);

    /// @dev This emits when ownership of any NFT changes by any mechanism.
    ///  This event emits when NFTs are created (`from` == 0) and destroyed
    ///  (`to` == 0). Exception: during contract creation, any number of NFTs
    ///  may be created and assigned without emitting Transfer. At the time of
    ///  any transfer, the approved address for that NFT (if any) is reset to none.
    event Transfer(address indexed _from, address indexed _to, uint64 indexed _tokenId);

    /// @dev This emits when the approved address for an NFT is changed or
    ///  reaffirmed. The zero address indicates there is no approved address.
    ///  When a Transfer event emits, this also indicates that the approved
    ///  address for that NFT (if any) is reset to none.
    event Approval(address indexed _owner, address indexed _approved, uint64 indexed _tokenId);

    /// @dev This emits when an operator is enabled or disabled for an owner.
    ///  The operator can manage all NFTs of the owner.
    event ApprovalForAll(address indexed _owner, address indexed _operator, bool _approved);

    bytes4 internal constant MAGIC_ON_ERC721_RECEIVED = 0x150b7a02;

    uint public constant TOKEN_LIMIT = 512; // 8 for testing, 256 or 512 for prod;
    uint public constant ARTIST_PRINTS = 128; // 2 for testing, 64 for prod;

    uint public constant PRICE = 0 gwei;

    // The beneficiary is 350.org
    address public constant BENEFICIARY = 0x50990F09d4f0cb864b8e046e7edC749dE410916b;

    mapping (uint64 => address) private idToCreator;
    mapping (uint64 => euint8) private eidToSymbolScheme;
    mapping (uint64 => uint8) private idToSymbolScheme;
    // ERC 165
    mapping(bytes4 => bool) internal supportedInterfaces;
        mapping(uint256 => uint64) public requestToID;
    /**
     * @dev A mapping from NFT ID to the address that owns it.
     */
    mapping (uint64 => address) internal idToOwner;

    /**
     * @dev A mapping from NFT ID to the seed used to make it.
     */
    mapping (uint64 => euint64) internal idToSeed;
    mapping (euint64 => uint64) internal seedToId;
    mapping (uint64=>address) internal tempOwner;
    /**
     * @dev Mapping from NFT ID to approved address.
     */
    mapping (uint64 => address) internal idToApproval;

    /**
     * @dev Mapping from owner address to mapping of operator addresses.
     */
    mapping (address => mapping (address => bool)) internal ownerToOperators;

    /**
     * @dev Mapping from owner to list of owned NFT IDs.
     */
    mapping(address => uint64[]) internal ownerToIds;
    mapping(uint64 => euint64) internal idTorand1;
    mapping(uint64 => euint64) internal idTorand2;
    /**
     * @dev Mapping from NFT ID to its index in the owner tokens list.
     */
    mapping(uint64 => uint64) internal idToOwnerIndex;

    /**
     * @dev Total number of tokens.
     */
    uint64 internal numTokens = 0;

    /**
     * @dev Guarantees that the msg.sender is an owner or operator of the given NFT.
     * @param _tokenId ID of the NFT to validate.
     */
    modifier canOperate(uint64 _tokenId) {
        address tokenOwner = idToOwner[_tokenId];
        require(tokenOwner == msg.sender || ownerToOperators[tokenOwner][msg.sender]);
        _;
    }

    /**
     * @dev Guarantees that the msg.sender is allowed to transfer NFT.
     * @param _tokenId ID of the NFT to transfer.
     */
    modifier canTransfer(uint64 _tokenId) {
        address tokenOwner = idToOwner[_tokenId];
        require(
            tokenOwner == msg.sender
            || idToApproval[_tokenId] == msg.sender
            || ownerToOperators[tokenOwner][msg.sender]
        );
        _;
    }

    /**
     * @dev Guarantees that _tokenId is a valid Token.
     * @param _tokenId ID of the NFT to validate.
     */
    modifier validNFToken(uint64 _tokenId) {
        require(idToOwner[_tokenId] != address(0));
        _;
    }

    /**
     * @dev Contract constructor.
     */
    constructor() public {
        supportedInterfaces[0x01ffc9a7] = true; // ERC165
        supportedInterfaces[0x80ac58cd] = true; // ERC721
        supportedInterfaces[0x780e9d63] = true; // ERC721 Enumerable
        supportedInterfaces[0x5b5e139f] = true; // ERC721 Metadata
    }

    ///////////////////
    //// GENERATOR ////
    ///////////////////

    int constant ONE = int(0x100000000);
    uint constant USIZE = 64;
    int constant SIZE = int(USIZE);
    int constant HALF_SIZE = SIZE / int(2);

    int constant SCALE = int(0x1b81a81ab1a81a823);
    int constant HALF_SCALE = SCALE / int(2);

    bytes prefix = "data:text/plain;charset=utf-8,";

    string internal nftName = "Autoglyphs";
    string internal nftSymbol = unicode"☵";

    // 0x2E = .
    // 0x4F = O
    // 0x2B = +
    // 0x58 = X
    // 0x7C = |
    // 0x2D = -
    // 0x5C = \
    // 0x2F = /
    // 0x23 = #

    function abs(int n) internal pure returns (int) {
        if (n >= 0) return n;
        return -n;
    }

function getScheme(euint64 a) internal  returns (euint8) {
    euint64 index = TFHE.rem(a, 83);
        euint64 limit1 = TFHE.asEuint64(20);
    euint64 limit2 = TFHE.asEuint64(35);
    euint64 limit3 = TFHE.asEuint64(48);
    euint64 limit4 = TFHE.asEuint64(59);
    euint64 limit5 = TFHE.asEuint64(68);
    euint64 limit6 = TFHE.asEuint64(73);
    euint64 limit7 = TFHE.asEuint64(77);
    euint64 limit8 = TFHE.asEuint64(80);
    euint64 limit9 = TFHE.asEuint64(82);

    euint8 scheme1 =TFHE.asEuint8(1) ;
    euint8 scheme2 = TFHE.asEuint8(2);
    euint8 scheme3 = TFHE.asEuint8(3);
    euint8 scheme4 = TFHE.asEuint8(4);
    euint8 scheme5 = TFHE.asEuint8(5);
    euint8 scheme6 = TFHE.asEuint8(6);
    euint8 scheme7 = TFHE.asEuint8(7);
    euint8 scheme8 = TFHE.asEuint8(8);
    euint8 scheme9 = TFHE.asEuint8(9);
    euint8 scheme10 = TFHE.asEuint8(10);

    euint8 result = TFHE.select(TFHE.lt(index, limit1), scheme1, scheme2);
    result = TFHE.select(TFHE.lt(index, limit2), result, scheme3);
    result = TFHE.select(TFHE.lt(index, limit3), result, scheme4);
    result = TFHE.select(TFHE.lt(index, limit4), result, scheme5);
    result = TFHE.select(TFHE.lt(index, limit5), result, scheme6);
    result = TFHE.select(TFHE.lt(index, limit6), result, scheme7);
    result = TFHE.select(TFHE.lt(index, limit7), result, scheme8);
    result = TFHE.select(TFHE.lt(index, limit8), result, scheme9);
    result = TFHE.select(TFHE.lt(index, limit9), result, scheme10);

return result;

}


    /* * ** *** ***** ******** ************* ******** ***** *** ** * */

    // The following code generates art.

    function draw(uint64 id,euint64 r1,euint64 r2) public view returns (string memory) {
       uint a = uint160(uint256(keccak256(abi.encodePacked(idToSeed[id]))));
        bytes memory output = new bytes(USIZE * (USIZE + 3) + 30);
        uint c;
        for (c = 0; c < 30; c++) {
            output[c] = prefix[c];
        }
        bytes5 symbols;
        if (idToSymbolScheme[id] == 0) {
            revert();
        } else if (idToSymbolScheme[id] == 1) {
            symbols = 0x2E582F5C23; // X/\
        } else if (idToSymbolScheme[id] == 2) {
            symbols = 0x2E2B2D7C2E; // +-|
        } else if (idToSymbolScheme[id] == 3) {
            symbols = 0x2E2F5C2E2E; // /\
        } else if (idToSymbolScheme[id] == 4) {
            symbols = 0x2E5C7C2D2F; // \|-/
        } else if (idToSymbolScheme[id] == 5) {
            symbols = 0x2E4F7C2D2E; // O|-
        } else if (idToSymbolScheme[id] == 6) {
            symbols = 0x2E5C5C2E4F; // \
        } else if (idToSymbolScheme[id] == 7) {
            symbols = 0x2E237C2D2B; // #|-+
        } else if (idToSymbolScheme[id] == 8) {
            symbols = 0x2E4F4F2E2E; // OO
        } else if (idToSymbolScheme[id] == 9) {
            symbols = 0x2E232E2E2E; // #
        } else {
            symbols = 0x2E234F2E2E; // #O
        }
uint additionalRandomness1 = (uint256(keccak256(abi.encodePacked(r1))) ) ;
uint additionalRandomness2 = (uint256(keccak256(abi.encodePacked(r2))) ) ;

uint index = 30; // Start filling after the prefix
for (uint y = 0; y < USIZE; y++) {
    for (uint x = 0; x < USIZE; x++) {
        // Introducing bit shifts to increase randomness
        uint combinedIndex = ((a << x) + (y >> 1) + additionalRandomness1 + (block.number << 1)) % 5;
        uint randomnessFactor = ((a >> 2) + (x << 2) * (y >> 1) + (additionalRandomness2 << 1)) % 31;
        

        if (randomnessFactor > 15)  {
            output[index++] = symbols[combinedIndex];
        } else {
            output[index++] = 0x20; // Place a space (ASCII 32)
        }
    }
    output[index++] = 0x0A; // New line character
}


    bytes memory trimmedOutput = new bytes(index);
    for (uint i = 0; i < index; i++) {
        trimmedOutput[i] = output[i];
    }
        string memory result = string(trimmedOutput);
        return result;
    }

    /* * ** *** ***** ******** ************* ******** ***** *** ** * */

    function creator(uint64 _id) external view returns (address) {
        return idToCreator[_id];
    }

    function symbolScheme(uint64 _id) external view returns (euint8) {
        return eidToSymbolScheme[_id];
    }

    function createGlyph() external payable returns (string memory) {
        euint64 seed = TFHE.randEuint64();
        _mint(msg.sender, seed);
    }

    //////////////////////////
    //// ERC 721 and 165  ////
    //////////////////////////


    function isContract(address _addr) internal view returns (bool addressCheck) {
        uint256 size;
        assembly { size := extcodesize(_addr) } // solhint-disable-line
        addressCheck = size > 0;
    }


    function supportsInterface(bytes4 _interfaceID) external view returns (bool) {
        return supportedInterfaces[_interfaceID];
    }

    /**
     * @dev Transfers the ownership of an NFT from one address to another address. This function can
     * be changed to payable.
     * @notice Throws unless `msg.sender` is the current owner, an authorized operator, or the
     * approved address for this NFT. Throws if `_from` is not the current owner. Throws if `_to` is
     * the zero address. Throws if `_tokenId` is not a valid NFT. When transfer is complete, this
     * function checks if `_to` is a smart contract (code size > 0). If so, it calls
     * `onERC721Received` on `_to` and throws if the return value is not
     * `bytes4(keccak256("onERC721Received(address,uint256,bytes)"))`.
     * @param _from The current owner of the NFT.
     * @param _to The new owner.
     * @param _tokenId The NFT to transfer.
     * @param _data Additional data with no specified format, sent in call to `_to`.
     */
    function safeTransferFrom(address _from, address _to, uint64 _tokenId, bytes memory _data) external {
        _safeTransferFrom(_from, _to, _tokenId, _data);
    }

    /**
     * @dev Transfers the ownership of an NFT from one address to another address. This function can
     * be changed to payable.
     * @notice This works identically to the other function with an extra data parameter, except this
     * function just sets data to ""
     * @param _from The current owner of the NFT.
     * @param _to The new owner.
     * @param _tokenId The NFT to transfer.
     */
    function safeTransferFrom(address _from, address _to, uint64 _tokenId) external {
        _safeTransferFrom(_from, _to, _tokenId, "");
    }

    /**
     * @dev Throws unless `msg.sender` is the current owner, an authorized operator, or the approved
     * address for this NFT. Throws if `_from` is not the current owner. Throws if `_to` is the zero
     * address. Throws if `_tokenId` is not a valid NFT. This function can be changed to payable.
     * @notice The caller is responsible to confirm that `_to` is capable of receiving NFTs or else
     * they maybe be permanently lost.
     * @param _from The current owner of the NFT.
     * @param _to The new owner.
     * @param _tokenId The NFT to transfer.
     */
    function transferFrom(address _from, address _to, uint64 _tokenId) external canTransfer(_tokenId) validNFToken(_tokenId) {
        address tokenOwner = idToOwner[_tokenId];
        require(tokenOwner == _from);
        require(_to != address(0));
        _transfer(_to, _tokenId);
    }

    /**
     * @dev Set or reaffirm the approved address for an NFT. This function can be changed to payable.
     * @notice The zero address indicates there is no approved address. Throws unless `msg.sender` is
     * the current NFT owner, or an authorized operator of the current owner.
     * @param _approved Address to be approved for the given NFT ID.
     * @param _tokenId ID of the token to be approved.
     */
    function approve(address _approved, uint64 _tokenId) external canOperate(_tokenId) validNFToken(_tokenId) {
        address tokenOwner = idToOwner[_tokenId];
        require(_approved != tokenOwner);
        idToApproval[_tokenId] = _approved;
        emit Approval(tokenOwner, _approved, _tokenId);
    }

    /**
     * @dev Enables or disables approval for a third party ("operator") to manage all of
     * `msg.sender`'s assets. It also emits the ApprovalForAll event.
     * @notice This works even if sender doesn't own any tokens at the time.
     * @param _operator Address to add to the set of authorized operators.
     * @param _approved True if the operators is approved, false to revoke approval.
     */
    function setApprovalForAll(address _operator, bool _approved) external {
        ownerToOperators[msg.sender][_operator] = _approved;
        emit ApprovalForAll(msg.sender, _operator, _approved);
    }

    /**
     * @dev Returns the number of NFTs owned by `_owner`. NFTs assigned to the zero address are
     * considered invalid, and this function throws for queries about the zero address.
     * @param _owner Address for whom to query the balance.
     * @return Balance of _owner.
     */
    function balanceOf(address _owner) external view returns (uint256) {
        require(_owner != address(0));
        return _getOwnerNFTCount(_owner);
    }

 
    function ownerOf(uint64 _tokenId) external view returns (address _owner) {
        _owner = idToOwner[_tokenId];
        require(_owner != address(0));
    }

    /**
     * @dev Get the approved address for a single NFT.
     * @notice Throws if `_tokenId` is not a valid NFT.
     * @param _tokenId ID of the NFT to query the approval of.
     * @return Address that _tokenId is approved for.
     */
    function getApproved(uint64 _tokenId) external view validNFToken(_tokenId) returns (address) {
        return idToApproval[_tokenId];
    }

    /**
     * @dev Checks if `_operator` is an approved operator for `_owner`.
     * @param _owner The address that owns the NFTs.
     * @param _operator The address that acts on behalf of the owner.
     * @return True if approved for all, false otherwise.
     */
    function isApprovedForAll(address _owner, address _operator) external view returns (bool) {
        return ownerToOperators[_owner][_operator];
    }

    /**
     * @dev Actually preforms the transfer.
     * @notice Does NO checks.
     * @param _to Address of a new owner.
     * @param _tokenId The NFT that is being transferred.
     */
    function _transfer(address _to, uint64 _tokenId) internal {
        address from = idToOwner[_tokenId];
        _clearApproval(_tokenId);

       
        _addNFToken(_to, _tokenId);

        emit Transfer(from, _to, _tokenId);
}

    /**
     * @dev Mints a new NFT.
     * @notice This is an internal function which should be called from user-implemented external
     * mint function. Its purpose is to show and properly initialize data structures when using this
     * implementation.
     * @param _to The address that will own the minted NFT.
     */
    function _mint(address _to, euint64 seed) public payable  {
        require(_to != address(0));
        require(numTokens < TOKEN_LIMIT);
        uint amount = 0;
        if (numTokens >= ARTIST_PRINTS) {
            amount = PRICE;
            require(msg.value >= amount);
        }
        uint64 id = (numTokens + 1);

        idToCreator[id] = _to;
        idToSeed[id] = seed;
        seedToId[seed] = id;
        tempOwner[id]=msg.sender;
       euint64 a = TFHE.asEuint64((uint160(uint256(keccak256(abi.encodePacked(seed))))));
       // get scheme as euint8 and store in idTosymbol
       // then send for decrypt request
        eidToSymbolScheme[id] = getScheme(a);
        // string memory uri = draw(id);
        // emit Generated(id, _to, uri);
    //-----------------------------------------------------------
    //Decrypt request
     TFHE.allow(eidToSymbolScheme[id], address(this));
     uint256[] memory cts = new uint256[](1);
      cts[0] = Gateway.toUint256(eidToSymbolScheme[id]);
       uint256 requestID = Gateway.requestDecryption(
            cts,
            this.randonNumberCallBackResolver.selector,
            0,
            block.timestamp + 100,
            false
        );
          requestToID[requestID] =id;
    //------------------------------------------------------------


        if (msg.value > amount) {
           payable(msg.sender).transfer(msg.value - amount);

        }
        if (amount > 0) {
            payable (BENEFICIARY).transfer(amount);
        }
    }
// callback resolver 
   function randonNumberCallBackResolver(uint256 requestID, uint8 decryptedInput) public onlyGateway returns (string memory){
    uint64 _id=requestToID[requestID];
    idToSymbolScheme[_id]=decryptedInput;
    idTorand1[_id]= TFHE.randEuint64();
    idTorand2[_id]= TFHE.randEuint64();
    string memory uri = draw(_id, idTorand1[_id],idTorand2[_id]);
    address _to= tempOwner[_id];
     numTokens = numTokens + 1;
        _addNFToken(_to, _id);

        // if (msg.value > amount) {
        //    payable(msg.sender).transfer(msg.value - amount);

        // }
        // if (amount > 0) {
        //     payable (BENEFICIARY).transfer(amount);
        // }
        emit Transfer(address(0), _to, _id);
    return uri;
   }






    /**
     * @dev Assigns a new NFT to an address.
     * @notice Use and override this function with caution. Wrong usage can have serious consequences.
     * @param _to Address to which we want to add the NFT.
     * @param _tokenId Which NFT we want to add.
     */
    function _addNFToken(address _to, uint64 _tokenId) internal {
        require(idToOwner[_tokenId] == address(0));
        idToOwner[_tokenId] = _to;

        ownerToIds[_to].push(_tokenId); 
    }



    /**
     * @dev Helper function that gets NFT count of owner. This is needed for overriding in enumerable
     * extension to remove double storage (gas optimization) of owner nft count.
     * @param _owner Address for whom to query the count.
     * @return Number of _owner NFTs.
     */
    function _getOwnerNFTCount(address _owner) internal view returns (uint256) {
        return ownerToIds[_owner].length;
    }

    /**
     * @dev Actually perform the safeTransferFrom.
     * @param _from The current owner of the NFT.
     * @param _to The new owner.
     * @param _tokenId The NFT to transfer.
     * @param _data Additional data with no specified format, sent in call to `_to`.
     */
    function _safeTransferFrom(address _from,  address _to,  uint64 _tokenId,  bytes memory _data) private canTransfer(_tokenId) validNFToken(_tokenId) {
        address tokenOwner = idToOwner[_tokenId];
        require(tokenOwner == _from);
        require(_to != address(0));

        _transfer(_to, _tokenId);
    }

    /**
     * @dev Clears the current approval of a given NFT ID.
     * @param _tokenId ID of the NFT to be transferred.
     */
    function _clearApproval(uint64 _tokenId) private {
        if (idToApproval[_tokenId] != address(0)) {
            delete idToApproval[_tokenId];
        }
    }

    //// Enumerable

    function totalSupply() public view returns (uint256) {
        return numTokens;
    }

    function tokenByIndex(uint256 index) public view returns (uint256) {
        require(index < numTokens);
        return index;
    }




    //// Metadata


    function name() external view returns (string memory _name) {
        _name = nftName;
    }


    function symbol() external view returns (string memory _symbol) {
        _symbol = nftSymbol;
    }

    /**
     * @dev A distinct URI (RFC 3986) for a given NFT.
     * @param _tokenId Id for which we want uri.
     * @return URI of _tokenId.
     */
    function tokenURI(uint64 _tokenId) external view validNFToken(_tokenId) returns (string memory) {
        return draw(_tokenId,idTorand1[_tokenId],idTorand2[_tokenId]);
    }

}