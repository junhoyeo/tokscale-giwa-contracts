// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title Tokscale Test USD
/// @notice A test-only six-decimal ERC-20 for GIWA Sepolia exact x402 experiments.
/// @dev This intentionally implements the EIP-3009 transfer-with-authorization
///      subset only. It is not a production stablecoin or a Permit2/upto asset.
contract TUSD {
    string private constant _NAME = "Tokscale Test USD";
    string private constant _SYMBOL = "tUSD";
    uint8 private constant _DECIMALS = 6;

    /// @notice Amount minted by one permissionless test-faucet call.
    uint256 public constant FAUCET_MINT_AMOUNT = 1_000_000 * 10 ** _DECIMALS;

    bytes32 public constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );
    bytes32 private constant _VERSION_HASH = keccak256("1");
    bytes32 private constant _NAME_HASH = keccak256("Tokscale Test USD");
    uint256 private constant _SECP256K1N_DIV_2 =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    uint256 public totalSupply;
    mapping(address account => uint256 amount) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;
    mapping(address authorizer => mapping(bytes32 nonce => bool used)) private _authorizationStates;

    uint256 private immutable _INITIAL_CHAIN_ID;
    bytes32 private immutable _INITIAL_DOMAIN_SEPARATOR;

    error ERC20InsufficientAllowance(address spender, uint256 allowanceAmount, uint256 needed);
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InvalidSender(address sender);
    error AuthorizationAlreadyUsed(address authorizer, bytes32 nonce);
    error AuthorizationExpired(uint256 validBefore, uint256 currentTimestamp);
    error AuthorizationNotYetValid(uint256 validAfter, uint256 currentTimestamp);
    error InvalidAuthorizationSignature();

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);
    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor() {
        _INITIAL_CHAIN_ID = block.chainid;
        _INITIAL_DOMAIN_SEPARATOR = _buildDomainSeparator();
    }

    function name() external pure returns (string memory) {
        return _NAME;
    }

    function symbol() external pure returns (string memory) {
        return _SYMBOL;
    }

    function decimals() external pure returns (uint8) {
        return _DECIMALS;
    }

    /// @notice Returns the EIP-712 domain separator for the active chain.
    /// @dev Rebuilding after a chain-id change prevents signatures from being reused after a fork.
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        if (block.chainid == _INITIAL_CHAIN_ID) {
            return _INITIAL_DOMAIN_SEPARATOR;
        }

        return _buildDomainSeparator();
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /// @notice Mints a fixed test balance for the caller on a permissionless local/testnet faucet.
    /// @dev The faucet is deliberately unsuitable for real value and must not be used outside testnet work.
    function faucetMint() external returns (bool) {
        _mint(msg.sender, FAUCET_MINT_AMOUNT);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 approved = allowance[from][msg.sender];
        if (approved != type(uint256).max) {
            if (approved < value) {
                revert ERC20InsufficientAllowance(msg.sender, approved, value);
            }

            unchecked {
                allowance[from][msg.sender] = approved - value;
            }
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }

        _transfer(from, to, value);
        return true;
    }

    /// @notice Returns whether an EIP-3009 authorization nonce has been consumed.
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool) {
        return _authorizationStates[authorizer][nonce];
    }

    /// @notice Transfers an exact amount after validating a signed EIP-3009 authorization.
    /// @dev Validity bounds are strict: an authorization is usable only when
    ///      validAfter < block.timestamp < validBefore, as specified by EIP-3009.
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bool) {
        if (block.timestamp <= validAfter) {
            revert AuthorizationNotYetValid(validAfter, block.timestamp);
        }
        if (block.timestamp >= validBefore) {
            revert AuthorizationExpired(validBefore, block.timestamp);
        }
        if (_authorizationStates[from][nonce]) {
            revert AuthorizationAlreadyUsed(from, nonce);
        }

        bytes32 structHash = keccak256(
            abi.encode(
                TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
                from,
                to,
                value,
                validAfter,
                validBefore,
                nonce
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));

        if (_recover(digest, v, r, s) != from) {
            revert InvalidAuthorizationSignature();
        }

        _authorizationStates[from][nonce] = true;
        emit AuthorizationUsed(from, nonce);
        _transfer(from, to, value);
        return true;
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH, _NAME_HASH, _VERSION_HASH, block.chainid, address(this)
            )
        );
    }

    function _mint(address to, uint256 value) private {
        if (to == address(0)) {
            revert ERC20InvalidReceiver(to);
        }

        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    function _transfer(address from, address to, uint256 value) private {
        if (from == address(0)) {
            revert ERC20InvalidSender(from);
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(to);
        }

        uint256 fromBalance = balanceOf[from];
        if (fromBalance < value) {
            revert ERC20InsufficientBalance(from, fromBalance, value);
        }

        unchecked {
            balanceOf[from] = fromBalance - value;
        }
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }

    function _recover(bytes32 digest, uint8 v, bytes32 r, bytes32 s)
        private
        pure
        returns (address)
    {
        if (v != 27 && v != 28 || uint256(s) > _SECP256K1N_DIV_2 || s == bytes32(0)) {
            revert InvalidAuthorizationSignature();
        }

        address signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) {
            revert InvalidAuthorizationSignature();
        }

        return signer;
    }
}
