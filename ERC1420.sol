// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;


abstract contract DN404 {
   
    event Transfer(address indexed from, address indexed to, uint256 amount);

    
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    
    event SkipNFTSet(address indexed target, bool status);

    
    error DNAlreadyInitialized();
 
    error InsufficientBalance();
 
    error InsufficientAllowance();

    error TotalSupplyOverflow();
 
    error SenderNotMirror();

    error TransferToZeroAddress();

    error MirrorAddressIsZero();

    error LinkMirrorContractFailed();

    error ApprovalCallerNotOwnerNorApproved();

    error TransferCallerNotOwnerNorApproved();

    error TransferFromIncorrectOwner();

    error TokenDoesNotExist();

 
    uint256 internal constant _WAD = 10 ** 18;
    uint256 internal constant _MAX_TOKEN_ID = 0xffffffff;
    uint256 internal constant _MAX_SUPPLY = 10 ** 18 * 0xffffffff - 1;
    uint8 internal constant _ADDRESS_DATA_INITIALIZED_FLAG = 1 << 0;
    uint8 internal constant _ADDRESS_DATA_SKIP_NFT_FLAG = 1 << 1;

    struct AddressData {
       
        uint88 aux;
       
        uint8 flags;
       
        uint32 addressAlias;
        
        uint32 ownedLength;
        
        uint96 balance;
    }

    
    struct Uint32Map {
        mapping(uint256 => uint256) map;
    }

    
    struct DN404Storage {
      
        uint32 numAliases;
        
        uint32 nextTokenId;
       
        uint32 totalNFTSupply;
       
        uint96 totalSupply;
       
        address mirrorERC721;
        
        mapping(uint32 => address) aliasToAddress;
        
        mapping(address => mapping(address => bool)) operatorApprovals;
   
        mapping(uint256 => address) tokenApprovals;
      
        mapping(address => mapping(address => uint256)) allowance;
       
        mapping(address => Uint32Map) owned;
      
        Uint32Map oo;
      
        mapping(address => AddressData) addressData;
    }

    
    function _getDN404Storage() internal pure virtual returns (DN404Storage storage $) {
       
        assembly {
            
            $.slot := 0xa20d6e21d0e5255308 
        }
    }

 
    function _initializeDN404(
        uint256 initialTokenSupply,
        address initialSupplyOwner,
        address mirror
    ) internal virtual {
        DN404Storage storage $ = _getDN404Storage();

        if ($.nextTokenId != 0) revert DNAlreadyInitialized();

        if (mirror == address(0)) revert MirrorAddressIsZero();
        _linkMirrorContract(mirror);

        $.nextTokenId = 1;
        $.mirrorERC721 = mirror;

        if (initialTokenSupply > 0) {
            if (initialSupplyOwner == address(0)) revert TransferToZeroAddress();
            if (initialTokenSupply > _MAX_SUPPLY) revert TotalSupplyOverflow();

            $.totalSupply = uint96(initialTokenSupply);
            AddressData storage initialOwnerAddressData = _addressData(initialSupplyOwner);
            initialOwnerAddressData.balance = uint96(initialTokenSupply);

            emit Transfer(address(0), initialSupplyOwner, initialTokenSupply);

            _setSkipNFT(initialSupplyOwner, true);
        }
    }


    function name() public view virtual returns (string memory);


    function symbol() public view virtual returns (string memory);

    function tokenURI(uint256 id) public view virtual returns (string memory);


    function decimals() public pure returns (uint8) {
        return 18;
    }


    function totalSupply() public view virtual returns (uint256) {
        return uint256(_getDN404Storage().totalSupply);
    }


    function balanceOf(address owner) public view virtual returns (uint256) {
        return _getDN404Storage().addressData[owner].balance;
    }

    
    function allowance(address owner, address spender) public view returns (uint256) {
        return _getDN404Storage().allowance[owner][spender];
    }


    function approve(address spender, uint256 amount) public virtual returns (bool) {
        DN404Storage storage $ = _getDN404Storage();

        $.allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

 
    function transfer(address to, uint256 amount) public virtual returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        DN404Storage storage $ = _getDN404Storage();

        uint256 allowed = $.allowance[from][msg.sender];

        if (allowed != type(uint256).max) {
            if (amount > allowed) revert InsufficientAllowance();
            unchecked {
                $.allowance[from][msg.sender] = allowed - amount;
            }
        }

        _transfer(from, to, amount);

        return true;
    }



    function _mint(address to, uint256 amount) internal virtual {
        if (to == address(0)) revert TransferToZeroAddress();

        DN404Storage storage $ = _getDN404Storage();

        AddressData storage toAddressData = _addressData(to);

        unchecked {
            uint256 currentTokenSupply = uint256($.totalSupply) + amount;
            if (amount > _MAX_SUPPLY || currentTokenSupply > _MAX_SUPPLY) {
                revert TotalSupplyOverflow();
            }
            $.totalSupply = uint96(currentTokenSupply);

            uint256 toBalance = toAddressData.balance + amount;
            toAddressData.balance = uint96(toBalance);

            if (toAddressData.flags & _ADDRESS_DATA_SKIP_NFT_FLAG == 0) {
                Uint32Map storage toOwned = $.owned[to];
                uint256 toIndex = toAddressData.ownedLength;
                uint256 toEnd = toBalance / _WAD;
                _PackedLogs memory packedLogs = _packedLogsMalloc(_zeroFloorSub(toEnd, toIndex));

                if (packedLogs.logs.length != 0) {
                    uint256 maxNFTId = $.totalSupply / _WAD;
                    uint32 toAlias = _registerAndResolveAlias(toAddressData, to);
                    uint256 id = $.nextTokenId;
                    $.totalNFTSupply += uint32(packedLogs.logs.length);
                    toAddressData.ownedLength = uint32(toEnd);
                   
                    do {
                        while (_get($.oo, _ownershipIndex(id)) != 0) {
                            if (++id > maxNFTId) id = 1;
                        }
                        _set(toOwned, toIndex, uint32(id));
                        _setOwnerAliasAndOwnedIndex($.oo, id, toAlias, uint32(toIndex++));
                        _packedLogsAppend(packedLogs, to, id, 0);
                        if (++id > maxNFTId) id = 1;
                    } while (toIndex != toEnd);
                    $.nextTokenId = uint32(id);
                    _packedLogsSend(packedLogs, $.mirrorERC721);
                }
            }
        }
        emit Transfer(address(0), to, amount);
    }


    function _burn(address from, uint256 amount) internal virtual {
        DN404Storage storage $ = _getDN404Storage();

        AddressData storage fromAddressData = _addressData(from);

        uint256 fromBalance = fromAddressData.balance;
        if (amount > fromBalance) revert InsufficientBalance();

        uint256 currentTokenSupply = $.totalSupply;

        unchecked {
            fromBalance -= amount;
            fromAddressData.balance = uint96(fromBalance);
            currentTokenSupply -= amount;
            $.totalSupply = uint96(currentTokenSupply);

            Uint32Map storage fromOwned = $.owned[from];
            uint256 fromIndex = fromAddressData.ownedLength;
            uint256 nftAmountToBurn = _zeroFloorSub(fromIndex, fromBalance / _WAD);

            if (nftAmountToBurn != 0) {
                $.totalNFTSupply -= uint32(nftAmountToBurn);

                _PackedLogs memory packedLogs = _packedLogsMalloc(nftAmountToBurn);

                uint256 fromEnd = fromIndex - nftAmountToBurn;
                // Burn loop.
                do {
                    uint256 id = _get(fromOwned, --fromIndex);
                    _setOwnerAliasAndOwnedIndex($.oo, id, 0, 0);
                    delete $.tokenApprovals[id];
                    _packedLogsAppend(packedLogs, from, id, 1);
                } while (fromIndex != fromEnd);

                fromAddressData.ownedLength = uint32(fromIndex);
                _packedLogsSend(packedLogs, $.mirrorERC721);
            }
        }
        emit Transfer(from, address(0), amount);
    }

 
    function _transfer(address from, address to, uint256 amount) internal virtual {
        if (to == address(0)) revert TransferToZeroAddress();

        DN404Storage storage $ = _getDN404Storage();

        AddressData storage fromAddressData = _addressData(from);
        AddressData storage toAddressData = _addressData(to);

        _TransferTemps memory t;
        t.fromOwnedLength = fromAddressData.ownedLength;
        t.toOwnedLength = toAddressData.ownedLength;
        t.fromBalance = fromAddressData.balance;

        if (amount > t.fromBalance) revert InsufficientBalance();

        unchecked {
            t.fromBalance -= amount;
            fromAddressData.balance = uint96(t.fromBalance);
            toAddressData.balance = uint96(t.toBalance = toAddressData.balance + amount);

            t.nftAmountToBurn = _zeroFloorSub(t.fromOwnedLength, t.fromBalance / _WAD);

            if (toAddressData.flags & _ADDRESS_DATA_SKIP_NFT_FLAG == 0) {
                if (from == to) t.toOwnedLength = t.fromOwnedLength - t.nftAmountToBurn;
                t.nftAmountToMint = _zeroFloorSub(t.toBalance / _WAD, t.toOwnedLength);
            }

            _PackedLogs memory packedLogs = _packedLogsMalloc(t.nftAmountToBurn + t.nftAmountToMint);

            if (t.nftAmountToBurn != 0) {
                Uint32Map storage fromOwned = $.owned[from];
                uint256 fromIndex = t.fromOwnedLength;
                uint256 fromEnd = fromIndex - t.nftAmountToBurn;
                $.totalNFTSupply -= uint32(t.nftAmountToBurn);
                fromAddressData.ownedLength = uint32(fromEnd);
               
                do {
                    uint256 id = _get(fromOwned, --fromIndex);
                    _setOwnerAliasAndOwnedIndex($.oo, id, 0, 0);
                    delete $.tokenApprovals[id];
                    _packedLogsAppend(packedLogs, from, id, 1);
                } while (fromIndex != fromEnd);
            }

            if (t.nftAmountToMint != 0) {
                Uint32Map storage toOwned = $.owned[to];
                uint256 toIndex = t.toOwnedLength;
                uint256 toEnd = toIndex + t.nftAmountToMint;
                uint32 toAlias = _registerAndResolveAlias(toAddressData, to);
                uint256 maxNFTId = $.totalSupply / _WAD;
                uint256 id = $.nextTokenId;
                $.totalNFTSupply += uint32(t.nftAmountToMint);
                toAddressData.ownedLength = uint32(toEnd);
               
                do {
                    while (_get($.oo, _ownershipIndex(id)) != 0) {
                        if (++id > maxNFTId) id = 1;
                    }
                    _set(toOwned, toIndex, uint32(id));
                    _setOwnerAliasAndOwnedIndex($.oo, id, toAlias, uint32(toIndex++));
                    _packedLogsAppend(packedLogs, to, id, 0);
                    if (++id > maxNFTId) id = 1;
                } while (toIndex != toEnd);
                $.nextTokenId = uint32(id);
            }

            if (packedLogs.logs.length != 0) {
                _packedLogsSend(packedLogs, $.mirrorERC721);
            }
        }
        emit Transfer(from, to, amount);
    }

    
    function _transferFromNFT(address from, address to, uint256 id, address msgSender)
        internal
        virtual
    {
        DN404Storage storage $ = _getDN404Storage();

        if (to == address(0)) revert TransferToZeroAddress();

        address owner = $.aliasToAddress[_get($.oo, _ownershipIndex(id))];

        if (from != owner) revert TransferFromIncorrectOwner();

        if (msgSender != from) {
            if (!$.operatorApprovals[from][msgSender]) {
                if (msgSender != $.tokenApprovals[id]) {
                    revert TransferCallerNotOwnerNorApproved();
                }
            }
        }

        AddressData storage fromAddressData = _addressData(from);
        AddressData storage toAddressData = _addressData(to);

        fromAddressData.balance -= uint96(_WAD);

        unchecked {
            toAddressData.balance += uint96(_WAD);

            _set($.oo, _ownershipIndex(id), _registerAndResolveAlias(toAddressData, to));
            delete $.tokenApprovals[id];

            uint256 updatedId = _get($.owned[from], --fromAddressData.ownedLength);
            _set($.owned[from], _get($.oo, _ownedIndex(id)), uint32(updatedId));

            uint256 n = toAddressData.ownedLength++;
            _set($.oo, _ownedIndex(updatedId), _get($.oo, _ownedIndex(id)));
            _set($.owned[to], n, uint32(id));
            _set($.oo, _ownedIndex(id), uint32(n));
        }

        emit Transfer(from, to, _WAD);
    }


    function _getAux(address owner) internal view virtual returns (uint88) {
        return _getDN404Storage().addressData[owner].aux;
    }


    function _setAux(address owner, uint88 value) internal virtual {
        _getDN404Storage().addressData[owner].aux = value;
    }


    function getSkipNFT(address a) public view virtual returns (bool) {
        AddressData storage d = _getDN404Storage().addressData[a];
        if (d.flags & _ADDRESS_DATA_INITIALIZED_FLAG == 0) return _hasCode(a);
        return d.flags & _ADDRESS_DATA_SKIP_NFT_FLAG != 0;
    }

 
    function setSkipNFT(bool skipNFT) public virtual {
        _setSkipNFT(msg.sender, skipNFT);
    }


    function _setSkipNFT(address a, bool state) internal virtual {
        AddressData storage d = _addressData(a);
        if ((d.flags & _ADDRESS_DATA_SKIP_NFT_FLAG != 0) != state) {
            d.flags ^= _ADDRESS_DATA_SKIP_NFT_FLAG;
        }
        emit SkipNFTSet(a, state);
    }


    function _addressData(address a) internal virtual returns (AddressData storage d) {
        DN404Storage storage $ = _getDN404Storage();
        d = $.addressData[a];

        if (d.flags & _ADDRESS_DATA_INITIALIZED_FLAG == 0) {
            uint8 flags = _ADDRESS_DATA_INITIALIZED_FLAG;
            if (_hasCode(a)) flags |= _ADDRESS_DATA_SKIP_NFT_FLAG;
            d.flags = flags;
        }
    }

 
    function _registerAndResolveAlias(AddressData storage toAddressData, address to)
        internal
        virtual
        returns (uint32 addressAlias)
    {
        DN404Storage storage $ = _getDN404Storage();
        addressAlias = toAddressData.addressAlias;
        if (addressAlias == 0) {
            addressAlias = ++$.numAliases;
            toAddressData.addressAlias = addressAlias;
            $.aliasToAddress[addressAlias] = to;
        }
    }


    function mirrorERC721() public view virtual returns (address) {
        return _getDN404Storage().mirrorERC721;
    }

  
    function _totalNFTSupply() internal view virtual returns (uint256) {
        return _getDN404Storage().totalNFTSupply;
    }

   
    function _balanceOfNFT(address owner) internal view virtual returns (uint256) {
        return _getDN404Storage().addressData[owner].ownedLength;
    }

 
    function _ownerAt(uint256 id) internal view virtual returns (address) {
        DN404Storage storage $ = _getDN404Storage();
        return $.aliasToAddress[_get($.oo, _ownershipIndex(id))];
    }

  
    function _ownerOf(uint256 id) internal view virtual returns (address) {
        if (!_exists(id)) revert TokenDoesNotExist();
        return _ownerAt(id);
    }

  
    function _exists(uint256 id) internal view virtual returns (bool) {
        return _ownerAt(id) != address(0);
    }

 
    function _getApproved(uint256 id) internal view virtual returns (address) {
        if (!_exists(id)) revert TokenDoesNotExist();
        return _getDN404Storage().tokenApprovals[id];
    }

  
    function _approveNFT(address spender, uint256 id, address msgSender)
        internal
        virtual
        returns (address)
    {
        DN404Storage storage $ = _getDN404Storage();

        address owner = $.aliasToAddress[_get($.oo, _ownershipIndex(id))];

        if (msgSender != owner) {
            if (!$.operatorApprovals[owner][msgSender]) {
                revert ApprovalCallerNotOwnerNorApproved();
            }
        }

        $.tokenApprovals[id] = spender;

        return owner;
    }


    function _setApprovalForAll(address operator, bool approved, address msgSender)
        internal
        virtual
    {
        _getDN404Storage().operatorApprovals[msgSender][operator] = approved;
    }

   
    function _linkMirrorContract(address mirror) internal virtual {
      
        assembly {
            mstore(0x00, 0x0f4599e5) 
            mstore(0x20, caller())
            if iszero(and(eq(mload(0x00), 1), call(gas(), mirror, 0, 0x1c, 0x24, 0x00, 0x20))) {
                mstore(0x00, 0xd125259c) 
                revert(0x1c, 0x04)
            }
        }
    }

   
    modifier dn404Fallback() virtual {
        DN404Storage storage $ = _getDN404Storage();

        uint256 fnSelector = _calldataload(0x00) >> 224;

       
        if (fnSelector == 0xe985e9c5) {
            if (msg.sender != $.mirrorERC721) revert SenderNotMirror();
            if (msg.data.length < 0x44) revert();

            address owner = address(uint160(_calldataload(0x04)));
            address operator = address(uint160(_calldataload(0x24)));

            _return($.operatorApprovals[owner][operator] ? 1 : 0);
        }
       
        if (fnSelector == 0x6352211e) {
            if (msg.sender != $.mirrorERC721) revert SenderNotMirror();
            if (msg.data.length < 0x24) revert();

            uint256 id = _calldataload(0x04);

            _return(uint160(_ownerOf(id)));
        }
       
        if (fnSelector == 0xe5eb36c8) {
            if (msg.sender != $.mirrorERC721) revert SenderNotMirror();
            if (msg.data.length < 0x84) revert();

            address from = address(uint160(_calldataload(0x04)));
            address to = address(uint160(_calldataload(0x24)));
            uint256 id = _calldataload(0x44);
            address msgSender = address(uint160(_calldataload(0x64)));

            _transferFromNFT(from, to, id, msgSender);
            _return(1);
        }
       
        if (fnSelector == 0x813500fc) {
            if (msg.sender != $.mirrorERC721) revert SenderNotMirror();
            if (msg.data.length < 0x64) revert();

            address spender = address(uint160(_calldataload(0x04)));
            bool status = _calldataload(0x24) != 0;
            address msgSender = address(uint160(_calldataload(0x44)));

            _setApprovalForAll(spender, status, msgSender);
            _return(1);
        }
       
        if (fnSelector == 0xd10b6e0c) {
            if (msg.sender != $.mirrorERC721) revert SenderNotMirror();
            if (msg.data.length < 0x64) revert();

            address spender = address(uint160(_calldataload(0x04)));
            uint256 id = _calldataload(0x24);
            address msgSender = address(uint160(_calldataload(0x44)));

            _return(uint160(_approveNFT(spender, id, msgSender)));
        }
       
        if (fnSelector == 0x081812fc) {
            if (msg.sender != $.mirrorERC721) revert SenderNotMirror();
            if (msg.data.length < 0x24) revert();

            uint256 id = _calldataload(0x04);

            _return(uint160(_getApproved(id)));
        }
       
        if (fnSelector == 0xf5b100ea) {
            if (msg.sender != $.mirrorERC721) revert SenderNotMirror();
            if (msg.data.length < 0x24) revert();

            address owner = address(uint160(_calldataload(0x04)));

            _return(_balanceOfNFT(owner));
        }
        
        if (fnSelector == 0xe2c79281) {
            if (msg.sender != $.mirrorERC721) revert SenderNotMirror();
            if (msg.data.length < 0x04) revert();

            _return(_totalNFTSupply());
        }
        // `implementsDN404()`.
        if (fnSelector == 0xb7a94eb8) {
            _return(1);
        }
        _;
    }

    
    fallback() external payable virtual dn404Fallback {}

    receive() external payable virtual {}

  
    struct _PackedLogs {
        uint256[] logs;
        uint256 offset;
    }

   
    function _packedLogsMalloc(uint256 n) private pure returns (_PackedLogs memory p) {
       
        assembly {
            let logs := add(mload(0x40), 0x40) 
            mstore(logs, n)
            let offset := add(0x20, logs)
            mstore(0x40, add(offset, shl(5, n)))
            mstore(p, logs)
            mstore(add(0x20, p), offset)
        }
    }

   
    function _packedLogsAppend(_PackedLogs memory p, address a, uint256 id, uint256 burnBit)
        private
        pure
    {
        
        assembly {
            let offset := mload(add(0x20, p))
            mstore(offset, or(or(shl(96, a), shl(8, id)), burnBit))
            mstore(add(0x20, p), add(offset, 0x20))
        }
    }

   
    function _packedLogsSend(_PackedLogs memory p, address mirror) private {
       
        assembly {
            let logs := mload(p)
            let o := sub(logs, 0x40) // Start of calldata to send.
            mstore(o, 0x263c69d6) // `logTransfer(uint256[])`.
            mstore(add(o, 0x20), 0x20) // Offset of `logs` in the calldata to send.
            let n := add(0x44, shl(5, mload(logs))) // Length of calldata to send.
            if iszero(and(eq(mload(o), 1), call(gas(), mirror, 0, add(o, 0x1c), n, o, 0x20))) {
                revert(o, 0x00)
            }
        }
    }

  
    struct _TransferTemps {
        uint256 nftAmountToBurn;
        uint256 nftAmountToMint;
        uint256 fromBalance;
        uint256 toBalance;
        uint256 fromOwnedLength;
        uint256 toOwnedLength;
    }

    /// @dev Returns if `a` has bytecode of non-zero length.
    function _hasCode(address a) private view returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := extcodesize(a) // Can handle dirty upper bits.
        }
    }

    /// @dev Returns the calldata value at `offset`.
    function _calldataload(uint256 offset) private pure returns (uint256 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := calldataload(offset)
        }
    }

    /// @dev Executes a return opcode to return `x` and end the current call frame.
    function _return(uint256 x) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, x)
            return(0x00, 0x20)
        }
    }

    /// @dev Returns `max(0, x - y)`.
    function _zeroFloorSub(uint256 x, uint256 y) private pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := mul(gt(x, y), sub(x, y))
        }
    }

    /// @dev Returns `i << 1`.
    function _ownershipIndex(uint256 i) private pure returns (uint256) {
        return i << 1;
    }

    /// @dev Returns `(i << 1) + 1`.
    function _ownedIndex(uint256 i) private pure returns (uint256) {
        unchecked {
            return (i << 1) + 1;
        }
    }

    /// @dev Returns the uint32 value at `index` in `map`.
    function _get(Uint32Map storage map, uint256 index) private view returns (uint32 result) {
        result = uint32(map.map[index >> 3] >> ((index & 7) << 5));
    }

    /// @dev Updates the uint32 value at `index` in `map`.
    function _set(Uint32Map storage map, uint256 index, uint32 value) private {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x20, map.slot)
            mstore(0x00, shr(3, index))
            let s := keccak256(0x00, 0x40) // Storage slot.
            let o := shl(5, and(index, 7)) // Storage slot offset (bits).
            let v := sload(s) // Storage slot value.
            let m := 0xffffffff // Value mask.
            sstore(s, xor(v, shl(o, and(m, xor(shr(o, v), value)))))
        }
    }

    /// @dev Sets the owner alias and the owned index together.
    function _setOwnerAliasAndOwnedIndex(
        Uint32Map storage map,
        uint256 id,
        uint32 ownership,
        uint32 ownedIndex
    ) private {
        /// @solidity memory-safe-assembly
        assembly {
            let value := or(shl(32, ownedIndex), and(0xffffffff, ownership))
            mstore(0x20, map.slot)
            mstore(0x00, shr(2, id))
            let s := keccak256(0x00, 0x40) // Storage slot.
            let o := shl(6, and(id, 3)) // Storage slot offset (bits).
            let v := sload(s) // Storage slot value.
            let m := 0xffffffffffffffff // Value mask.
            sstore(s, xor(v, shl(o, and(m, xor(shr(o, v), value)))))
        }
    }
}