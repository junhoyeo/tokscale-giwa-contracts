// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TUSD} from "../src/TUSD.sol";
import {TUSDDeployer} from "../src/TUSDDeployer.sol";

interface Vm {
    function addr(uint256 privateKey) external returns (address keyAddr);
    function chainId(uint256 newChainId) external;
    function expectEmit(
        bool checkTopic1,
        bool checkTopic2,
        bool checkTopic3,
        bool checkData,
        address emitter
    ) external;
    function expectPartialRevert(bytes4 revertData) external;
    function expectRevert(bytes4 revertData) external;
    function prank(address msgSender) external;
    function sign(uint256 privateKey, bytes32 digest)
        external
        returns (uint8 v, bytes32 r, bytes32 s);
    function warp(uint256 newTimestamp) external;
}

contract TUSDTest {
    uint256 private constant GIWA_SEPOLIA_CHAIN_ID = 91_342;
    uint256 private constant OTHER_CHAIN_ID = 11_155_111;
    uint256 private constant ALICE_PRIVATE_KEY = 0xA11CE;
    uint256 private constant BOB_PRIVATE_KEY = 0xB0B;
    uint256 private constant MALLORY_PRIVATE_KEY = 0xBAD;
    uint256 private constant SECP256K1N =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    bytes32 private constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 private constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );
    bytes32 private constant NAME_HASH = keccak256("Tokscale Test USD");
    bytes32 private constant VERSION_HASH = keccak256("1");

    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    TUSD private token;
    address private alice;
    address private bob;
    address private mallory;

    error AssertionFailed();

    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);

    function setUp() public {
        VM.chainId(GIWA_SEPOLIA_CHAIN_ID);
        token = new TUSD();
        alice = VM.addr(ALICE_PRIVATE_KEY);
        bob = VM.addr(BOB_PRIVATE_KEY);
        mallory = VM.addr(MALLORY_PRIVATE_KEY);
    }

    function test_MetadataAndDomainSeparatorBindToGiwaSepolia() public view {
        _assertEq(keccak256(bytes(token.name())), NAME_HASH);
        _assertEq(keccak256(bytes(token.symbol())), keccak256("tUSD"));
        _assertEq(uint256(token.decimals()), 6);
        _assertEq(
            token.DOMAIN_SEPARATOR(), _domainSeparatorFor(GIWA_SEPOLIA_CHAIN_ID, address(token))
        );
    }

    function test_DomainSeparatorChangesOnChainChange() public {
        bytes32 giwaSeparator = token.DOMAIN_SEPARATOR();
        VM.chainId(OTHER_CHAIN_ID);

        _assertTrue(token.DOMAIN_SEPARATOR() != giwaSeparator);
        _assertEq(token.DOMAIN_SEPARATOR(), _domainSeparatorFor(OTHER_CHAIN_ID, address(token)));
    }

    function test_ExactAuthorizationTransferUsesSignatureAndPreservesSupply() public {
        _faucet(alice);

        uint256 value = 123_456_789;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("exact-transfer");
        (uint8 v, bytes32 r, bytes32 s) =
            _signAuthorization(ALICE_PRIVATE_KEY, alice, bob, value, validAfter, validBefore, nonce);

        VM.expectEmit(true, true, false, false, address(token));
        emit AuthorizationUsed(alice, nonce);
        bool succeeded = token.transferWithAuthorization(
            alice, bob, value, validAfter, validBefore, nonce, v, r, s
        );

        _assertTrue(succeeded);
        _assertTrue(token.authorizationState(alice, nonce));
        _assertEq(token.balanceOf(alice), token.FAUCET_MINT_AMOUNT() - value);
        _assertEq(token.balanceOf(bob), value);
        _assertEq(token.totalSupply(), token.FAUCET_MINT_AMOUNT());
        _assertEq(token.balanceOf(alice) + token.balanceOf(bob), token.totalSupply());
    }

    function test_ReplayIsRejectedAndBalancesRemainUnchanged() public {
        _faucet(alice);

        uint256 value = 1 * 10 ** token.decimals();
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("replay");
        (uint8 v, bytes32 r, bytes32 s) =
            _signAuthorization(ALICE_PRIVATE_KEY, alice, bob, value, validAfter, validBefore, nonce);

        token.transferWithAuthorization(alice, bob, value, validAfter, validBefore, nonce, v, r, s);
        uint256 aliceBalance = token.balanceOf(alice);
        uint256 bobBalance = token.balanceOf(bob);

        VM.expectPartialRevert(TUSD.AuthorizationAlreadyUsed.selector);
        token.transferWithAuthorization(alice, bob, value, validAfter, validBefore, nonce, v, r, s);

        _assertEq(token.balanceOf(alice), aliceBalance);
        _assertEq(token.balanceOf(bob), bobBalance);
        _assertEq(token.totalSupply(), aliceBalance + bobBalance);
    }

    function test_RejectsAtValidAfterAndAllowsOneSecondLater() public {
        _faucet(alice);

        uint256 validAfter = block.timestamp;
        uint256 validBefore = validAfter + 1 hours;
        bytes32 nonce = keccak256("valid-after-boundary");
        (uint8 v, bytes32 r, bytes32 s) =
            _signAuthorization(ALICE_PRIVATE_KEY, alice, bob, 1, validAfter, validBefore, nonce);

        VM.expectPartialRevert(TUSD.AuthorizationNotYetValid.selector);
        token.transferWithAuthorization(alice, bob, 1, validAfter, validBefore, nonce, v, r, s);
        _assertTrue(!token.authorizationState(alice, nonce));

        VM.warp(validAfter + 1);
        token.transferWithAuthorization(alice, bob, 1, validAfter, validBefore, nonce, v, r, s);
        _assertTrue(token.authorizationState(alice, nonce));
    }

    function test_RejectsAtValidBeforeAndDoesNotConsumeNonce() public {
        _faucet(alice);

        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp;
        bytes32 nonce = keccak256("valid-before-boundary");
        (uint8 v, bytes32 r, bytes32 s) =
            _signAuthorization(ALICE_PRIVATE_KEY, alice, bob, 1, validAfter, validBefore, nonce);

        VM.expectPartialRevert(TUSD.AuthorizationExpired.selector);
        token.transferWithAuthorization(alice, bob, 1, validAfter, validBefore, nonce, v, r, s);
        _assertTrue(!token.authorizationState(alice, nonce));
        _assertEq(token.balanceOf(alice), token.FAUCET_MINT_AMOUNT());
        _assertEq(token.balanceOf(bob), 0);
    }

    function test_RejectsMalformedSignatureWithoutConsumingNonce() public {
        _faucet(alice);

        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("malformed-signature");
        (, bytes32 r, bytes32 s) =
            _signAuthorization(ALICE_PRIVATE_KEY, alice, bob, 1, validAfter, validBefore, nonce);

        VM.expectRevert(TUSD.InvalidAuthorizationSignature.selector);
        token.transferWithAuthorization(alice, bob, 1, validAfter, validBefore, nonce, 0, r, s);
        _assertTrue(!token.authorizationState(alice, nonce));
    }

    function test_RejectsMalleableHighSSignatureWithoutConsumingNonce() public {
        _faucet(alice);

        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("malleable-signature");
        (uint8 v, bytes32 r, bytes32 s) =
            _signAuthorization(ALICE_PRIVATE_KEY, alice, bob, 1, validAfter, validBefore, nonce);
        uint8 flippedV = v == 27 ? 28 : 27;
        bytes32 highS = bytes32(SECP256K1N - uint256(s));

        VM.expectRevert(TUSD.InvalidAuthorizationSignature.selector);
        token.transferWithAuthorization(
            alice, bob, 1, validAfter, validBefore, nonce, flippedV, r, highS
        );
        _assertTrue(!token.authorizationState(alice, nonce));
    }

    function test_RejectsWrongSignerWithoutConsumingNonce() public {
        _faucet(alice);

        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("wrong-signer");
        (uint8 v, bytes32 r, bytes32 s) =
            _signAuthorization(MALLORY_PRIVATE_KEY, alice, bob, 1, validAfter, validBefore, nonce);

        VM.expectRevert(TUSD.InvalidAuthorizationSignature.selector);
        token.transferWithAuthorization(alice, bob, 1, validAfter, validBefore, nonce, v, r, s);
        _assertTrue(!token.authorizationState(alice, nonce));
        _assertEq(token.balanceOf(mallory), 0);
    }

    function test_RejectsSignatureFromAnotherChain() public {
        _faucet(alice);

        uint256 value = 1;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("wrong-chain");
        bytes32 wrongChainDigest = _authorizationDigestFor(
            OTHER_CHAIN_ID, alice, bob, value, validAfter, validBefore, nonce
        );
        (uint8 v, bytes32 r, bytes32 s) = VM.sign(ALICE_PRIVATE_KEY, wrongChainDigest);

        VM.expectRevert(TUSD.InvalidAuthorizationSignature.selector);
        token.transferWithAuthorization(alice, bob, value, validAfter, validBefore, nonce, v, r, s);
        _assertTrue(!token.authorizationState(alice, nonce));
    }

    function test_RejectsTamperedAuthorizationTerms() public {
        _faucet(alice);

        uint256 value = 20;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("tampered-terms");
        (uint8 v, bytes32 r, bytes32 s) =
            _signAuthorization(ALICE_PRIVATE_KEY, alice, bob, value, validAfter, validBefore, nonce);

        VM.expectRevert(TUSD.InvalidAuthorizationSignature.selector);
        token.transferWithAuthorization(
            alice, mallory, value, validAfter, validBefore, nonce, v, r, s
        );
        _assertTrue(!token.authorizationState(alice, nonce));
        _assertEq(token.balanceOf(mallory), 0);
    }

    function test_FaucetAndErc20TransfersConserveSupply() public {
        _faucet(alice);
        _faucet(bob);
        uint256 transferValue = 42 * 10 ** token.decimals();

        VM.prank(alice);
        _assertTrue(token.transfer(bob, transferValue));

        _assertEq(token.totalSupply(), token.FAUCET_MINT_AMOUNT() * 2);
        _assertEq(token.balanceOf(alice) + token.balanceOf(bob), token.totalSupply());

        VM.prank(alice);
        token.approve(mallory, transferValue);
        VM.prank(mallory);
        _assertTrue(token.transferFrom(alice, bob, transferValue));

        _assertEq(token.totalSupply(), token.FAUCET_MINT_AMOUNT() * 2);
        _assertEq(token.balanceOf(alice) + token.balanceOf(bob), token.totalSupply());
        _assertEq(token.allowance(alice, mallory), 0);
    }

    function test_DeterministicFactoryCreatesTokenAtConstruction() public {
        TUSDDeployer deployer = new TUSDDeployer();
        address predicted = deployer.predictTokenAddress();
        TUSD deployed = deployer.token();

        _assertEq(address(deployed), predicted);
        _assertEq(keccak256(bytes(deployed.symbol())), keccak256("tUSD"));
    }

    function testFuzz_ExactAuthorizationPreservesSupply(uint96 fuzzedValue, bytes32 nonce) public {
        _faucet(alice);

        uint256 value = uint256(fuzzedValue) % (token.FAUCET_MINT_AMOUNT() + 1);
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) =
            _signAuthorization(ALICE_PRIVATE_KEY, alice, bob, value, validAfter, validBefore, nonce);

        token.transferWithAuthorization(alice, bob, value, validAfter, validBefore, nonce, v, r, s);

        _assertTrue(token.authorizationState(alice, nonce));
        _assertEq(token.balanceOf(alice), token.FAUCET_MINT_AMOUNT() - value);
        _assertEq(token.balanceOf(bob), value);
        _assertEq(token.balanceOf(alice) + token.balanceOf(bob), token.totalSupply());
    }

    function _authorizationDigestFor(
        uint256 chainId,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) private view returns (bytes32) {
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
        return keccak256(
            abi.encodePacked("\x19\x01", _domainSeparatorFor(chainId, address(token)), structHash)
        );
    }

    function _domainSeparatorFor(uint256 chainId, address verifyingContract)
        private
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, chainId, verifyingContract)
        );
    }

    function _faucet(address account) private {
        VM.prank(account);
        token.faucetMint();
    }

    function _signAuthorization(
        uint256 signerPrivateKey,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) private returns (uint8 v, bytes32 r, bytes32 s) {
        return VM.sign(
            signerPrivateKey,
            _authorizationDigestFor(
                GIWA_SEPOLIA_CHAIN_ID, from, to, value, validAfter, validBefore, nonce
            )
        );
    }

    function _assertEq(uint256 left, uint256 right) private pure {
        if (left != right) {
            revert AssertionFailed();
        }
    }

    function _assertEq(address left, address right) private pure {
        if (left != right) {
            revert AssertionFailed();
        }
    }

    function _assertEq(bytes32 left, bytes32 right) private pure {
        if (left != right) {
            revert AssertionFailed();
        }
    }

    function _assertTrue(bool value) private pure {
        if (!value) {
            revert AssertionFailed();
        }
    }
}
