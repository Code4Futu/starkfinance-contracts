use core::clone::Clone;
use core::fmt::Debug;
use core::serde::Serde;
use integer::u256;
use integer::u256_from_felt252;
use integer::BoundedInt;

use array::ArrayTrait;
use array::SpanTrait;
use debug::PrintTrait;
use traits::TryInto;
use traits::Into;
use result::ResultTrait;
use option::OptionTrait;

use starknet::{contract_address_try_from_felt252, get_block_timestamp};
use starknet::contract_address::ContractAddress;
use starknet::testing::{set_contract_address, pop_log, set_block_timestamp};
use starknet::syscalls::deploy_syscall;
use starknet::SyscallResultTrait;
use starknet::class_hash::{Felt252TryIntoClassHash, class_hash_to_felt252}; 

use starkfinance::interfaces::token::{
    erc20::{IERC20Dispatcher, IERC20DispatcherTrait},
    erc721::{IERC721Dispatcher, IERC721DispatcherTrait}
};
use starkfinance::mocks::erc20::{ERC20};
use starkfinance::mocks::erc721::{ERC721};
use starkfinance::interfaces::launchpad::launchpad::{
    ISFLaunchpadDispatcher, ISFLaunchpadDispatcherTrait,
};
use starkfinance::launchpad::launchpad::{SFLaunchpad};

const NAME: felt252 = 'Test';
const SYMBOL: felt252 = 'TEST';
const DECIMALS: u8 = 18_u8;

const OTHER_NAME: felt252 = 'Other Test';
const OTHER_SYMBOL: felt252 = 'OTHER_TEST';
const OTHER_DECIMALS: u8 = 18_u8;

const ERC721_NAME: felt252 = 'ERC721 Name';
const ERC721_SYMBOL: felt252 = 'ERC721_SYMBOL';

const LAUNCHPAD_PERCENT_FEE: u256 = 500_u256; // 0.5%
const LAUNCHPAD_TOTAL_SALE: u256 = 1_000_000_u256;
const LAUNCHPAD_TOTAL_RAISE: u256 = 500_000_u256;
const LAUNCHPAD_MIN_COMMIT: u256 = 10_u256;
const LAUNCHPAD_MAX_COMMIT: u256 = 2_000_000_u256;
const LAUNCHPAD_VESTING_TIME: u64 = 259200_u64;

const ONE_HUNDRED_PERCENT: u256 = 100_000_u256;
const TEN_PERCENT: u256 = 10_000_u256;

fn setUp() -> (
    ContractAddress, 
    ContractAddress,
    IERC721Dispatcher,
    ContractAddress,
    IERC20Dispatcher, 
    ContractAddress, 
    IERC20Dispatcher, 
    ContractAddress
) {
    let caller = contract_address_try_from_felt252('admin').unwrap();
    set_contract_address(caller);

    let other_caller = contract_address_try_from_felt252('user2').unwrap();

    // deploy ERC721
    let mut erc721_calldata = array![ERC721_NAME, ERC721_SYMBOL];
    let (erc721_address, _) = deploy_syscall(
        ERC721::TEST_CLASS_HASH.try_into().unwrap(), 0, erc721_calldata.span(), false
    )
        .unwrap();
    let mut erc721_token = IERC721Dispatcher { contract_address: erc721_address };

    // deploy ERC20
    let mut erc20_calldata = array![NAME, SYMBOL, DECIMALS.into()];
    let (erc20_address, _) = deploy_syscall(
        ERC20::TEST_CLASS_HASH.try_into().unwrap(), 0, erc20_calldata.span(), false
    )
        .unwrap();
    let mut erc20_token = IERC20Dispatcher { contract_address: erc20_address };

    let mut other_erc20_calldata = array![OTHER_NAME, OTHER_SYMBOL, OTHER_DECIMALS.into()];
    let (other_erc20_address, _) = deploy_syscall(
        ERC20::TEST_CLASS_HASH.try_into().unwrap(), 0, other_erc20_calldata.span(), false
    )
        .unwrap();
    let mut other_erc20_token = IERC20Dispatcher { contract_address: other_erc20_address };

    (
        caller, 
        other_caller, 
        erc721_token,
        erc721_address,
        erc20_token, 
        erc20_address, 
        other_erc20_token, 
        other_erc20_address,
    )
}

fn deploy_launchpad(
    admin: ContractAddress,
    nft: ContractAddress,
    owner: ContractAddress,
    percent_fee: u256,
    token_sale: ContractAddress,
    token_raise: ContractAddress,
    total_sale: u256,
    total_raise: u256,
    start: u64,
    end: u64,
    min_commit: u256,
    max_commit: u256,
    vesting_time: Array<u64>,
    vesting_percent: Array<u256>,
) -> (ISFLaunchpadDispatcher, ContractAddress) {
    let mut metadata = ArrayTrait::new();
    admin.serialize(ref metadata);
    nft.serialize(ref metadata);
    owner.serialize(ref metadata); 
    percent_fee.serialize(ref metadata); 
    token_sale.serialize(ref metadata); 
    token_raise.serialize(ref metadata); 
    total_sale.serialize(ref metadata);
    total_raise.serialize(ref metadata); 
    start.serialize(ref metadata);
    end.serialize(ref metadata); 
    min_commit.serialize(ref metadata); 
    max_commit.serialize(ref metadata); 
    vesting_time.serialize(ref metadata); 
    vesting_percent.serialize(ref metadata); 
    
    let (launchpad_address, _) = deploy_syscall(
        SFLaunchpad::TEST_CLASS_HASH.try_into().unwrap(), 0, metadata.span(), false
    )
        .unwrap();
    let mut launchpad = ISFLaunchpadDispatcher { contract_address: launchpad_address };

    (launchpad, launchpad_address)
}

#[test]
#[available_gas(20000000)]
fn test_stake_nft() {
    let (
        caller, 
        other_caller, 
        erc721_token,
        erc721_address,
        erc20_token, 
        erc20_address, 
        other_erc20_token, 
        other_erc20_address,
    ) = setUp();

    let current = get_block_timestamp();
    let start = current + 10;
    let end = start + 1000;

    let (launchpad, launchpad_address) = deploy_launchpad(
        caller,
        erc721_address,
        caller,
        LAUNCHPAD_PERCENT_FEE,
        erc20_address, // token sale
        other_erc20_address, // token raise
        LAUNCHPAD_TOTAL_SALE,
        LAUNCHPAD_TOTAL_RAISE,
        start,
        end,
        LAUNCHPAD_MIN_COMMIT,
        LAUNCHPAD_MAX_COMMIT,
        array![LAUNCHPAD_VESTING_TIME],
        vesting_percent: array![ONE_HUNDRED_PERCENT]
    );

    set_contract_address(caller);
    erc20_token.mint(LAUNCHPAD_TOTAL_SALE);

    erc20_token.approve(launchpad_address, LAUNCHPAD_TOTAL_SALE);
    erc20_token.transfer(launchpad_address, LAUNCHPAD_TOTAL_SALE);

    let nft_id = 0;
    erc721_token.mint(caller);
    assert(erc721_token.ownerOf(nft_id) == caller, 'User does not have NFT');

    erc721_token.approve(launchpad_address, nft_id);
    launchpad.stake_nft(nft_id);

    assert(erc721_token.ownerOf(nft_id) == launchpad_address, 'NFT is not staked to launchpad');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('NotStart', 'ENTRYPOINT_FAILED', ))]
fn test_commit_when_launchpad_not_start() {
    let (
        caller, 
        other_caller, 
        erc721_token,
        erc721_address,
        erc20_token, 
        erc20_address, 
        other_erc20_token, 
        other_erc20_address,
    ) = setUp();

    let current = get_block_timestamp();
    let start = current + 100_u64;
    let end = start + 10_u64;

    let (launchpad, launchpad_address) = deploy_launchpad(
        caller,
        erc721_address,
        caller,
        LAUNCHPAD_PERCENT_FEE,
        erc20_address, // token sale
        other_erc20_address, // token raise
        LAUNCHPAD_TOTAL_SALE,
        LAUNCHPAD_TOTAL_RAISE,
        start,
        end,
        LAUNCHPAD_MIN_COMMIT,
        LAUNCHPAD_MAX_COMMIT,
        array![LAUNCHPAD_VESTING_TIME],
        vesting_percent: array![ONE_HUNDRED_PERCENT]
    );

    set_contract_address(caller);
    erc20_token.mint(LAUNCHPAD_TOTAL_SALE);

    erc20_token.approve(launchpad_address, LAUNCHPAD_TOTAL_SALE);
    erc20_token.transfer(launchpad_address, LAUNCHPAD_TOTAL_SALE);

    let commit_amount = 1000_u256;
    
    launchpad.commit(commit_amount)
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Ended', 'ENTRYPOINT_FAILED', ))]
fn test_commit_when_launchpad_ended() {
    let (
        caller, 
        other_caller, 
        erc721_token,
        erc721_address,
        erc20_token, 
        erc20_address, 
        other_erc20_token, 
        other_erc20_address,
    ) = setUp();

    set_block_timestamp(1000);
    let current = get_block_timestamp();
    let start = current - 100_u64;
    let end = start + 10_u64;

    let (launchpad, launchpad_address) = deploy_launchpad(
        caller,
        erc721_address,
        caller,
        LAUNCHPAD_PERCENT_FEE,
        erc20_address, // token sale
        other_erc20_address, // token raise
        LAUNCHPAD_TOTAL_SALE,
        LAUNCHPAD_TOTAL_RAISE,
        start,
        end,
        LAUNCHPAD_MIN_COMMIT,
        LAUNCHPAD_MAX_COMMIT,
        array![LAUNCHPAD_VESTING_TIME],
        vesting_percent: array![ONE_HUNDRED_PERCENT]
    );

    set_contract_address(caller);
    erc20_token.mint(LAUNCHPAD_TOTAL_SALE);

    erc20_token.approve(launchpad_address, LAUNCHPAD_TOTAL_SALE);
    erc20_token.transfer(launchpad_address, LAUNCHPAD_TOTAL_SALE);

    let commit_amount = 1000_u256;
    
    launchpad.commit(commit_amount)
}

#[test]
#[available_gas(20000000)]
fn test_commit() {
    let (
        caller, 
        other_caller, 
        erc721_token,
        erc721_address,
        erc20_token, 
        erc20_address, 
        other_erc20_token, 
        other_erc20_address,
    ) = setUp();

    let current = get_block_timestamp();
    let start = current;
    let end = start + 10_u64;

    let (launchpad, launchpad_address) = deploy_launchpad(
        caller,
        erc721_address,
        caller,
        LAUNCHPAD_PERCENT_FEE,
        erc20_address, // token sale
        other_erc20_address, // token raise
        LAUNCHPAD_TOTAL_SALE,
        LAUNCHPAD_TOTAL_RAISE,
        start,
        end,
        LAUNCHPAD_MIN_COMMIT,
        LAUNCHPAD_MAX_COMMIT,
        array![LAUNCHPAD_VESTING_TIME],
        vesting_percent: array![ONE_HUNDRED_PERCENT]
    );

    set_contract_address(caller);
    erc20_token.mint(LAUNCHPAD_TOTAL_SALE);

    erc20_token.approve(launchpad_address, LAUNCHPAD_TOTAL_SALE);
    erc20_token.transfer(launchpad_address, LAUNCHPAD_TOTAL_SALE);

    let commit_amount = LAUNCHPAD_MIN_COMMIT;
    other_erc20_token.mint(commit_amount);
    other_erc20_token.approve(launchpad_address, commit_amount);
    
    launchpad.commit(commit_amount);

    assert(launchpad.get_user_stats(caller).committed == commit_amount, 'Invalid commit amount');
}

#[test]
#[available_gas(20000000)]
fn test_claim() {
    let (
        caller, 
        other_caller, 
        erc721_token,
        erc721_address,
        erc20_token, 
        erc20_address, 
        other_erc20_token, 
        other_erc20_address,
    ) = setUp();

    let current = get_block_timestamp();
    let start = current;
    let end = start + 10_u64;

    let (launchpad, launchpad_address) = deploy_launchpad(
        caller,
        erc721_address,
        caller,
        LAUNCHPAD_PERCENT_FEE,
        erc20_address, // token sale
        other_erc20_address, // token raise
        LAUNCHPAD_TOTAL_SALE,
        LAUNCHPAD_TOTAL_RAISE,
        start,
        end,
        LAUNCHPAD_MIN_COMMIT,
        LAUNCHPAD_MAX_COMMIT,
        array![LAUNCHPAD_VESTING_TIME],
        vesting_percent: array![ONE_HUNDRED_PERCENT]
    );

    set_contract_address(caller);
    erc20_token.mint(LAUNCHPAD_TOTAL_SALE);

    erc20_token.approve(launchpad_address, LAUNCHPAD_TOTAL_SALE);
    erc20_token.transfer(launchpad_address, LAUNCHPAD_TOTAL_SALE);

    // user commit
    let commit_amount = LAUNCHPAD_MAX_COMMIT - 10000;
    other_erc20_token.mint(commit_amount);
    other_erc20_token.approve(launchpad_address, commit_amount);

    launchpad.commit(commit_amount);

    assert(launchpad.get_user_stats(caller).committed == commit_amount, 'Invalid commit amount');

    // other user commit
    set_contract_address(other_caller);
    let other_commit_amount = 10_000_u256;
    other_erc20_token.mint(other_commit_amount);
    other_erc20_token.approve(launchpad_address, other_commit_amount);

    launchpad.commit(other_commit_amount);

    set_block_timestamp(end + LAUNCHPAD_VESTING_TIME);

    launchpad.claim();

    assert(erc20_token.balanceOf(other_caller) == launchpad.get_user_stats(other_caller).claimed, 'Invalid claim amount')
}

#[test]
#[available_gas(2000000000)]
fn test_claim_with_stake_nft() {
    let (
        caller, 
        other_caller, 
        erc721_token,
        erc721_address,
        erc20_token, 
        erc20_address, 
        other_erc20_token, 
        other_erc20_address,
    ) = setUp();

    let current = get_block_timestamp();
    let start = current;
    let end = start + 10_u64;

    let total_sale = 1_000_000;
    let total_raise = 500000;
    let max_commit = 2_000_000;
    let (launchpad, launchpad_address) = deploy_launchpad(
        caller,
        erc721_address,
        caller,
        LAUNCHPAD_PERCENT_FEE,
        erc20_address, // token sale
        other_erc20_address, // token raise
        total_sale,
        total_raise,
        start,
        end,
        1,
        2_000_000,
        array![LAUNCHPAD_VESTING_TIME],
        vesting_percent: array![ONE_HUNDRED_PERCENT]
    );

    set_contract_address(caller);
    erc20_token.mint(total_sale);

    erc20_token.approve(launchpad_address, total_sale);
    erc20_token.transfer(launchpad_address, total_sale);

    // user commit
                     // 1_000_000_000_000_000_000_000_000_u256
    let commit_amount = 30000;
    other_erc20_token.mint(commit_amount);
    other_erc20_token.approve(launchpad_address, commit_amount);
    let nft_id: u256 = 0_u256;
    erc721_token.mint(caller);
    erc721_token.approve(launchpad_address, nft_id);
    launchpad.stake_nft(nft_id);
    
    // assert(erc721_token.ownerOf(nft_id) == launchpad_address, 'stake nft failed');

    // println!("caller {}", caller);
    caller.print();
    let owner_of = erc721_token.ownerOf(nft_id);
    // println!("Owner nft {}", owner_of);
    owner_of.print();

    launchpad.commit(commit_amount);

    // other user commit
    set_contract_address(other_caller);
    let other_commit = max_commit - commit_amount;
    other_erc20_token.mint(other_commit);
    other_erc20_token.approve(launchpad_address, other_commit);
    
    launchpad.commit(other_commit);

    set_block_timestamp(end + LAUNCHPAD_VESTING_TIME);

    let committed = launchpad.get_user_stats(caller).committed;
    assert(committed + committed *TEN_PERCENT/ONE_HUNDRED_PERCENT   == commit_amount + commit_amount*TEN_PERCENT/ONE_HUNDRED_PERCENT, 'Invalid commit amount 1');
    assert(launchpad.get_user_stats(other_caller).committed == other_commit, 'Invalid commit amount 2');

    launchpad.claim();
    assert(erc20_token.balanceOf(other_caller) == launchpad.get_user_stats(other_caller).claimed, 'Invalid claim amount');

    set_contract_address(caller);
    launchpad.claim();
    assert(erc721_token.ownerOf(nft_id) == caller, 'claim stake nft falied');
    assert(erc20_token.balanceOf(other_caller) == launchpad.get_user_stats(other_caller).claimed, 'Invalid claim amount 2');

}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('VestingRoundNotStart', 'ENTRYPOINT_FAILED', ))]
fn test_claim_if_vesting_time_not_start() {
    let (
        caller, 
        other_caller, 
        erc721_token,
        erc721_address,
        erc20_token, 
        erc20_address, 
        other_erc20_token, 
        other_erc20_address,
    ) = setUp();

    let current = get_block_timestamp();
    let start = current;
    let end = start + 10_u64;

    let (launchpad, launchpad_address) = deploy_launchpad(
        caller,
        erc721_address,
        caller,
        LAUNCHPAD_PERCENT_FEE,
        erc20_address, // token sale
        other_erc20_address, // token raise
        LAUNCHPAD_TOTAL_SALE,
        LAUNCHPAD_TOTAL_RAISE,
        start,
        end,
        LAUNCHPAD_MIN_COMMIT,
        LAUNCHPAD_MAX_COMMIT,
        array![LAUNCHPAD_VESTING_TIME],
        vesting_percent: array![ONE_HUNDRED_PERCENT]
    );

    set_contract_address(caller);
    erc20_token.mint(LAUNCHPAD_TOTAL_SALE);
    erc20_token.approve(launchpad_address, LAUNCHPAD_TOTAL_SALE);
    erc20_token.transfer(launchpad_address, LAUNCHPAD_TOTAL_SALE);

    // user commit
    let commit_amount = LAUNCHPAD_MAX_COMMIT - 10000;
    other_erc20_token.mint(commit_amount);
    other_erc20_token.approve(launchpad_address, commit_amount);
    launchpad.commit(commit_amount);

    set_block_timestamp(start + LAUNCHPAD_VESTING_TIME - 1);

    launchpad.claim();
}

#[test]
#[available_gas(20000000)]
fn test_claim_if_vesting_time_start() {
    let (
        caller, 
        other_caller, 
        erc721_token,
        erc721_address,
        erc20_token, 
        erc20_address, 
        other_erc20_token, 
        other_erc20_address,
    ) = setUp();

    let current = get_block_timestamp();
    let start = current;
    let end = start + 10_u64;

    let (launchpad, launchpad_address) = deploy_launchpad(
        caller,
        erc721_address,
        caller,
        LAUNCHPAD_PERCENT_FEE,
        erc20_address, // token sale
        other_erc20_address, // token raise
        LAUNCHPAD_TOTAL_SALE,
        LAUNCHPAD_TOTAL_RAISE,
        start,
        end,
        LAUNCHPAD_MIN_COMMIT,
        LAUNCHPAD_MAX_COMMIT,
        array![LAUNCHPAD_VESTING_TIME],
        vesting_percent: array![ONE_HUNDRED_PERCENT]
    );

    set_contract_address(caller);
    erc20_token.mint(LAUNCHPAD_TOTAL_SALE);
    erc20_token.approve(launchpad_address, LAUNCHPAD_TOTAL_SALE);
    erc20_token.transfer(launchpad_address, LAUNCHPAD_TOTAL_SALE);

    // user commit
    let commit_amount = LAUNCHPAD_MAX_COMMIT - 10000;
    other_erc20_token.mint(commit_amount);
    other_erc20_token.approve(launchpad_address, commit_amount);
    launchpad.commit(commit_amount);

    set_block_timestamp(end + LAUNCHPAD_VESTING_TIME + 1);

    launchpad.claim();
}

#[test]
#[available_gas(20000000)]
fn test_allocation_remainning() {
    let (
        caller, 
        other_caller, 
        erc721_token,
        erc721_address,
        erc20_token, 
        erc20_address, 
        other_erc20_token, 
        other_erc20_address,
    ) = setUp();

    let current = get_block_timestamp();
    let start = current;
    let end = start + 10_u64;
    let total_sale = 1000;
    let total_raise = 5000;
    let min_commit = 1;
    let max_commit = 1000;
    let vesting_time = array![0, 3600];
    let vesting_percent = array![50000,50000];

    let (launchpad, launchpad_address) = deploy_launchpad(
        caller,
        erc721_address,
        caller,
        LAUNCHPAD_PERCENT_FEE,
        erc20_address, // token sale
        other_erc20_address, // token raise
        total_sale,
        total_raise,
        start,
        end,
        min_commit,
        max_commit,
        vesting_time,
        vesting_percent
    );

    set_contract_address(caller);
    erc20_token.mint(total_sale);

    erc20_token.approve(launchpad_address, total_sale);
    erc20_token.transfer(launchpad_address, total_sale);

    let commit_amount = 250;
    other_erc20_token.mint(commit_amount);
    other_erc20_token.approve(launchpad_address, commit_amount);

    launchpad.commit(commit_amount);

    let last_committed_time = launchpad.get_user_stats(caller).last_committed_time;

    set_block_timestamp(last_committed_time + end + 1 + 0);

    launchpad.claim();

    let user_stats = launchpad.get_user_stats(caller);

    // user_stats.allocation.print();

    // assert(launchpad.get_user_stats(caller).claimed == erc20_token.balanceOf(caller), 'Invalid claim 1');

    set_block_timestamp(last_committed_time + end + 1 + 3600);

    launchpad.claim();

    // assert(launchpad.get_user_stats(caller).claimed == erc20_token.balanceOf(caller), 'Invalid claim 2');
}