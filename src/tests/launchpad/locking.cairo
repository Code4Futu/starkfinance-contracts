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
use starknet::testing::{set_caller_address, set_contract_address, pop_log, set_block_timestamp};
use starknet::syscalls::deploy_syscall;
use starknet::SyscallResultTrait;
use starknet::class_hash::{Felt252TryIntoClassHash, class_hash_to_felt252}; 

use starkfinance::interfaces::token::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use starkfinance::mocks::erc20::{ERC20};
use starkfinance::interfaces::launchpad::locking::{ISFLockingDispatcher, ISFLockingDispatcherTrait};
use starkfinance::launchpad::locking::{SFLocking,};
// use starkfinance::Locker::Locker::{Event as LockerEvent, lockLock};

const NAME: felt252 = 'Test';
const SYMBOL: felt252 = 'TET';
const DECIMALS: u8 = 18_u8;

#[derive(Clone, Drop, Serde)] 
struct Lock {
    
}

fn deploy_erc20(init_supply: u256) -> (
        ContractAddress, 
        ContractAddress, 
        IERC20Dispatcher, 
        ContractAddress, 
        ISFLockingDispatcher, 
        ContractAddress
    ) {
    let caller = contract_address_const::<1>();
    let other_caller = contract_address_const::<2>();
    set_contract_address(caller);

    // deploy ERC20
    let mut erc20_calldata = array![NAME, SYMBOL, DECIMALS.into()];
    let (erc20_address, _) = deploy_syscall(
        ERC20::TEST_CLASS_HASH.try_into().unwrap(), 0, erc20_calldata.span(), false
    )
        .unwrap();
    let mut erc20_token = IERC20Dispatcher { contract_address: erc20_address };
    erc20_token.mint(init_supply);

    // deploy Locker
    let (locking_address, _) = deploy_syscall(
        SFLocking::TEST_CLASS_HASH.try_into().unwrap(), 0, ArrayTrait::new().span(), false
    )
        .unwrap();

    (
        caller, 
        other_caller, 
        erc20_token, 
        erc20_address,
        ISFLockingDispatcher { contract_address: locking_address }, 
        locking_address
    )
}


fn lock_lock(
    locking_address: ContractAddress,
    owner: ContractAddress,
    token: ContractAddress,
    amount: u256,
    tge: u64,
    is_vesting: bool,
    tge_percent: u256,
    vesting_time: Array<u64>,
    vesting_percent: Array<u256>,
) {
    let mut calldata = ArrayTrait::new();
    owner.serialize(ref calldata);
    token.serialize(ref calldata);
    amount.serialize(ref calldata); 
    tge.serialize(ref calldata); 
    is_vesting.serialize(ref calldata); 
    tge_percent.serialize(ref calldata);
    vesting_time.serialize(ref calldata); 
    vesting_percent.serialize(ref calldata);
    
    let locking = ISFLockingDispatcher { contract_address: locking_address };
    locking.lock(
        owner,
        token,
        amount,
        tge,
        is_vesting,
        tge_percent,
        vesting_time,
        vesting_percent,
    );
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('InvalidVesting', 'ENTRYPOINT_FAILED', ))]
fn test_lock_lock_invalid_vesting() {
    let init_supply = 1_000_000_u256;
    let (
        caller, 
        other_caller, 
        erc20_token, 
        erc20_address, 
        locking, 
        locking_address
    ) = deploy_erc20(init_supply);

    let amount: u256 = init_supply;

    let current_time: u64 = get_block_timestamp();

    erc20_token.approve(locking_address, amount);

    lock_lock(
        locking_address: locking_address,
        owner: caller,
        token: erc20_address,
        amount: amount,
        tge: current_time + 10,
        is_vesting: true,
        tge_percent: 50_000,
        vesting_time: array![],
        vesting_percent: array![50_000],
    );
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('MustEq100%', 'ENTRYPOINT_FAILED', ))]
fn test_lock_lock_invalid_vestting_percent() {
    let init_supply = 1_000_000_u256;
    let (
        caller, 
        other_caller, 
        erc20_token, 
        erc20_address, 
        locking, 
        locking_address
    ) = deploy_erc20(init_supply);

    let amount: u256 = init_supply;

    let current_time: u64 = get_block_timestamp();

    erc20_token.approve(locking_address, amount);

    lock_lock(
        locking_address: locking_address,
        owner: caller,
        token: erc20_address,
        amount: amount,
        tge: current_time + 10,
        is_vesting: true,
        tge_percent: 50_000,
        vesting_time: array![6000],
        vesting_percent: array![50_001],
    );
}


#[test]
#[available_gas(20000000)]
fn test_lock_lock_no_vesting_success() {
    let init_supply = 1_000_000_u256;
    let (
        caller, 
        other_caller, 
        erc20_token, 
        erc20_address, 
        locking, 
        locking_address
    ) = deploy_erc20(init_supply);

    let amount: u256 = init_supply;

    let current_time: u64 = get_block_timestamp();

    erc20_token.approve(locking_address, amount);

    lock_lock(
        locking_address: locking_address,
        owner: caller,
        token: erc20_address,
        amount: amount,
        tge: current_time + 10,
        is_vesting: false,
        tge_percent: 100_000,
        vesting_time: array![],
        vesting_percent: array![],
    );

    assert(erc20_token.balanceOf(caller) == 0, 'Blance should eq 0');
}

#[test]
#[available_gas(20000000)]
fn test_lock_lock_vesting_success() {
    let init_supply = 1_000_000_u256;
    let (
        caller, 
        other_caller, 
        erc20_token, 
        erc20_address, 
        locking, 
        locking_address
    ) = deploy_erc20(init_supply);

    let amount: u256 = init_supply;

    let current_time: u64 = get_block_timestamp();

    erc20_token.approve(locking_address, amount);

    lock_lock(
        locking_address: locking_address,
        owner: caller,
        token: erc20_address,
        amount: amount,
        tge: current_time + 10,
        is_vesting: true,
        tge_percent: 50_000,
        vesting_time: array![6000],
        vesting_percent: array![50_000],
    );

    assert(erc20_token.balanceOf(caller) == 0, 'Blance should eq 0');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('InvalidLockId', 'ENTRYPOINT_FAILED'))]
fn test_unlock_invalid_lock() {
    let init_supply = 1_000_000_u256;
    let (
        caller, 
        other_caller, 
        erc20_token, 
        erc20_address, 
        locking, 
        locking_address
    ) = deploy_erc20(init_supply);

    let amount: u256 = init_supply;

    let current_time: u64 = get_block_timestamp();

    erc20_token.approve(locking_address, amount);

    lock_lock(
        locking_address: locking_address,
        owner: caller,
        token: erc20_address,
        amount: amount,
        tge: current_time + 10,
        is_vesting: true,
        tge_percent: 50_000,
        vesting_time: array![6000],
        vesting_percent: array![50_000],
    );

    locking.unlock(erc20_address, 1);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Unauthorzied', 'ENTRYPOINT_FAILED'))]
fn test_unlock_unauthorzied_lock() {
    let init_supply = 1_000_000_u256;
    let (
        caller, 
        other_caller, 
        erc20_token, 
        erc20_address, 
        locking, 
        locking_address
    ) = deploy_erc20(init_supply);

    let amount: u256 = init_supply;

    let current_time: u64 = get_block_timestamp();

    erc20_token.approve(locking_address, amount);

    lock_lock(
        locking_address: locking_address,
        owner: caller,
        token: erc20_address,
        amount: amount,
        tge: current_time + 10,
        is_vesting: true,
        tge_percent: 50_000,
        vesting_time: array![6000],
        vesting_percent: array![50_000],
    );

    set_contract_address(other_caller);
    locking.unlock(erc20_address, 0);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('NotTimeToUnlock', 'ENTRYPOINT_FAILED'))]
fn test_unlock_invalid_unlock_time() {
    let init_supply = 1_000_000_u256;
    let (
        caller, 
        other_caller, 
        erc20_token, 
        erc20_address, 
        locking, 
        locking_address
    ) = deploy_erc20(init_supply);

    let amount: u256 = init_supply;

    let current_time: u64 = get_block_timestamp();

    erc20_token.approve(locking_address, amount);

    lock_lock(
        locking_address: locking_address,
        owner: caller,
        token: erc20_address,
        amount: amount,
        tge: current_time + 10,
        is_vesting: true,
        tge_percent: 50_000,
        vesting_time: array![6000],
        vesting_percent: array![50_000],
    );

    locking.unlock(erc20_address, 0);
}

#[test]
#[available_gas(20000000)]
fn test_unlock_lock_no_vesting_success() {
    let init_supply = 1_000_000_u256;
    let (
        caller, 
        other_caller, 
        erc20_token, 
        erc20_address, 
        locking, 
        locking_address
    ) = deploy_erc20(init_supply);

    let amount: u256 = init_supply;

    let current_time: u64 = get_block_timestamp();

    erc20_token.approve(locking_address, amount);

    lock_lock(
        locking_address: locking_address,
        owner: caller,
        token: erc20_address,
        amount: amount,
        tge: current_time + 10,
        is_vesting: true,
        tge_percent: 100_000,
        vesting_time: array![],
        vesting_percent: array![],
    );
    
    assert(erc20_token.balanceOf(locking_address) == init_supply, 'Balance should eq init supply');

    set_block_timestamp(current_time + 10);

    locking.unlock(erc20_address, 0);

    assert(erc20_token.balanceOf(caller) == init_supply, 'Balance should eq init supply');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Unlocked', 'ENTRYPOINT_FAILED'))]
fn test_unlock_lock_no_vesting_twince() {
    let init_supply = 1_000_000_u256;
    let (
        caller, 
        other_caller, 
        erc20_token, 
        erc20_address, 
        locking, 
        locking_address
    ) = deploy_erc20(init_supply);

    let amount: u256 = init_supply;

    let current_time: u64 = get_block_timestamp();

    erc20_token.approve(locking_address, amount);

    lock_lock(
        locking_address: locking_address,
        owner: caller,
        token: erc20_address,
        amount: amount,
        tge: current_time + 10,
        is_vesting: false,
        tge_percent: 100_000,
        vesting_time: array![],
        vesting_percent: array![],
    );
    
    assert(erc20_token.balanceOf(locking_address) == init_supply, 'Balance should eq init supply');

    set_block_timestamp(current_time + 10);

    locking.unlock(erc20_address, 0);

    assert(erc20_token.balanceOf(caller) == init_supply, 'Balance should eq init supply');

    locking.unlock(erc20_address, 0);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('NotTimeToUnlockVesting', 'ENTRYPOINT_FAILED'))]
fn test_unlock_lock_vesting_not_time_unlock() {
    let init_supply = 1_000_000_u256;
    let (
        caller, 
        other_caller, 
        erc20_token, 
        erc20_address, 
        locking, 
        locking_address
    ) = deploy_erc20(init_supply);

    let amount: u256 = init_supply;

    let current_time: u64 = get_block_timestamp();

    erc20_token.approve(locking_address, amount);

    lock_lock(
        locking_address: locking_address,
        owner: caller,
        token: erc20_address,
        amount: amount,
        tge: current_time + 10,
        is_vesting: true,
        tge_percent: 50_000,
        vesting_time: array![6000],
        vesting_percent: array![50_000],
    );
    
    assert(erc20_token.balanceOf(locking_address) == init_supply, 'Balance should eq init supply');

    set_block_timestamp(current_time + 10);

    locking.unlock(erc20_address, 0);
    assert(erc20_token.balanceOf(caller) == init_supply / 2, 'Balance should eq 1/2 init');

    locking.unlock(erc20_address, 0);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('UnlockedAllVesting', 'ENTRYPOINT_FAILED'))]
fn test_unlock_lock_vesting_unlock_over_vesting() {
    let init_supply = 1_000_000_u256;
    let (
        caller, 
        other_caller, 
        erc20_token, 
        erc20_address, 
        locking, 
        locking_address
    ) = deploy_erc20(init_supply);

    let amount: u256 = init_supply;

    let current_time: u64 = get_block_timestamp();

    erc20_token.approve(locking_address, amount);

    lock_lock(
        locking_address: locking_address,
        owner: caller,
        token: erc20_address,
        amount: amount,
        tge: current_time + 10,
        is_vesting: true,
        tge_percent: 50_000,
        vesting_time: array![6000],
        vesting_percent: array![50_000],
    );
    
    assert(erc20_token.balanceOf(locking_address) == init_supply, 'Balance should eq init supply');

    set_block_timestamp(current_time + 10);

    locking.unlock(erc20_address, 0);
    assert(erc20_token.balanceOf(caller) == init_supply / 2, 'Balance should eq 1/2 init');

    set_block_timestamp(current_time + 10 + 6000);

    locking.unlock(erc20_address, 0);
    assert(erc20_token.balanceOf(caller) == init_supply, 'Balance should eq init supply');

    locking.unlock(erc20_address, 0);
}

#[test]
#[available_gas(20000000)]
fn test_unlock_lock_vesting_success() {
    let init_supply = 1_000_000_u256;
    let (
        caller, 
        other_caller, 
        erc20_token, 
        erc20_address, 
        locking, 
        locking_address
    ) = deploy_erc20(init_supply);

    let amount: u256 = init_supply;

    let current_time: u64 = get_block_timestamp();

    erc20_token.approve(locking_address, amount);

    lock_lock(
        locking_address: locking_address,
        owner: caller,
        token: erc20_address,
        amount: amount,
        tge: current_time + 10,
        is_vesting: true,
        tge_percent: 50_000,
        vesting_time: array![6000],
        vesting_percent: array![50_000],
    );
    
    assert(erc20_token.balanceOf(locking_address) == init_supply, 'Balance should eq init supply');

    set_block_timestamp(current_time + 10);

    locking.unlock(erc20_address, 0);
    assert(erc20_token.balanceOf(caller) == init_supply / 2, 'Balance should eq 1/2 init');

    set_block_timestamp(current_time + 10 + 6000);

    locking.unlock(erc20_address, 0);
    assert(erc20_token.balanceOf(caller) == init_supply, 'Balance should eq init supply');
}