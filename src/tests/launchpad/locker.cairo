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

use starknet::{contract_address_const, get_block_timestamp};
use starknet::contract_address::ContractAddress;
use starknet::testing::{set_caller_address, set_contract_address, pop_log};
use starknet::syscalls::deploy_syscall;
use starknet::SyscallResultTrait;
use starknet::class_hash::{Felt252TryIntoClassHash, class_hash_to_felt252}; 

use starkfinance::ERC20::{ERC20, IERC20Dispatcher, IERC20DispatcherTrait};
use starkfinance::ERC20::ERC20::{Event, Approval};
use starkfinance::Locker::{Locker, ILockerDispatcher, ILockerDispatcherTrait};
use starkfinance::Locker::Locker::{Event as LockerEvent, CreateLock};

const NAME: felt252 = 'Test';
const SYMBOL: felt252 = 'TET';
const DECIMALS: u8 = 18_u8;

fn setUp() -> (ContractAddress, IERC20Dispatcher, ContractAddress, ILockerDispatcher, ContractAddress) {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);

    // deploy ERC20
    let mut erc20_calldata = array![NAME, SYMBOL, DECIMALS.into()];
    let (erc20_address, _) = deploy_syscall(
        ERC20::TEST_CLASS_HASH.try_into().unwrap(), 0, erc20_calldata.span(), false
    )
        .unwrap();
    let mut erc20_token = IERC20Dispatcher { contract_address: erc20_address };
    erc20_token.mint(1000000000000000000000_u256);

    // deploy Locker
    let (locker_address, _) = deploy_syscall(
        Locker::TEST_CLASS_HASH.try_into().unwrap(), 0, ArrayTrait::new().span(), false
    )
        .unwrap();
    let mut locker = ILockerDispatcher { contract_address: locker_address };

    (caller, erc20_token, erc20_address, locker, locker_address)
}

#[test]
#[available_gas(20000000)]
fn test_create_lock() {
    let (caller, erc20_token, erc20_address, locker, locker_address) = setUp();
    let amount: u256 = 2000_u256;

    erc20_token.approve(locker_address, amount);
    assert(erc20_token.allowance(caller, locker_address) == amount, 'Approve should eq 2000');

    let current_time: u64 = get_block_timestamp();
    let end: u64 = current_time + 60;

    locker.create_lock(erc20_address, amount, end);
    assert(locker.get_total_lock() == 1_u256, 'Total lock should eq 1')
}

#[test]
#[available_gas(20000000)]
fn test_claim_lock() {
    let (caller, erc20_token, erc20_address, locker, locker_address) = setUp();
    let amount: u256 = 2000_u256;

    erc20_token.approve(locker_address, amount);

    let current_time: u64 = get_block_timestamp();
    let end: u64 = current_time;

    locker.create_lock(erc20_address, amount, end);
    locker.claim_lock(0_u256);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('LockNotEnd', 'ENTRYPOINT_FAILED', ))]
fn test_claim_lock_err_not_end() {
    let (caller, erc20_token, erc20_address, locker, locker_address) = setUp();
    let amount: u256 = 2000_u256;

    erc20_token.approve(locker_address, amount);

    let current_time: u64 = get_block_timestamp();
    let end: u64 = current_time + 60;

    locker.create_lock(erc20_address, amount, end);
    locker.claim_lock(0_u256);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('LockClaimed', 'ENTRYPOINT_FAILED', ))]
fn test_claim_lock_err_claimed() {
    let (caller, erc20_token, erc20_address, locker, locker_address) = setUp();
    let amount: u256 = 2000_u256;

    erc20_token.approve(locker_address, amount);

    let current_time: u64 = get_block_timestamp();
    let end: u64 = current_time;

    locker.create_lock(erc20_address, amount, end);

    locker.claim_lock(0_u256);
    locker.claim_lock(0_u256);
}
