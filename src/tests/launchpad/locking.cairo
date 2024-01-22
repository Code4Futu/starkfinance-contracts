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

use starkfinance::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use starkfinance::mocks::erc20::{ERC20};
use starkfinance::launchpad::locking::{Locking, ILockingDispatcher, ILockingDispatcherTrait};
// use starkfinance::Locker::Locker::{Event as LockerEvent, CreateLock};

const NAME: felt252 = 'Test';
const SYMBOL: felt252 = 'TET';
const DECIMALS: u8 = 18_u8;

#[derive(Clone, Drop, Serde)] 
struct Lock {
    
}

fn deploy_erc20() -> (
        ContractAddress, 
        ContractAddress, 
        IERC20Dispatcher, 
        ContractAddress, 
        ILockingDispatcher, 
        ContractAddress
    ) {
    let caller = contract_address_const::<1>();
    let other_caller = contract_address_const::<1>();
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
    let (locking_address, _) = deploy_syscall(
        Locking::TEST_CLASS_HASH.try_into().unwrap(), 0, ArrayTrait::new().span(), false
    )
        .unwrap();

    (
        caller, 
        other_caller, 
        erc20_token, 
        erc20_address,
        ILockingDispatcher { contract_address: locking_address }, 
        locking_address
    )
}


fn create_lock(
    locking_address: ContractAddress,
    owner: ContractAddress,
    token: ContractAddress,
    amount: u256,
    start: u64,
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
    start.serialize(ref calldata); 
    tge.serialize(ref calldata); 
    is_vesting.serialize(ref calldata); 
    tge_percent.serialize(ref calldata);
    vesting_time.serialize(ref calldata); 
    vesting_percent.serialize(ref calldata);
    
    let locking = ILockingDispatcher { contract_address: locking_address };
    locking.create(
        owner,
        token,
        amount,
        start,
        tge,
        is_vesting,
        tge_percent,
        vesting_time,
        vesting_percent,
    );
}

#[test]
#[available_gas(20000000)]
fn test_create_lock() {
    let (
        caller, 
        other_caller, 
        erc20_token, 
        erc20_address, 
        locking, 
        locking_address
    ) = deploy_erc20();
    let amount: u256 = 2000_u256;

    let current_time: u64 = get_block_timestamp();

    erc20_token.approve(locking_address, amount);

    create_lock(
        locking_address: locking_address,
        owner: caller,
        token: erc20_address,
        amount: amount,
        start: current_time,
        tge: current_time + 10,
        is_vesting: false,
        tge_percent: 100_000,
        vesting_time: array![],
        vesting_percent: array![],
    );

    // erc20_token.approve(locker_address, amount);
    // assert(erc20_token.allowance(caller, locker_address) == amount, 'Approve should eq 2000');

    // let end: u64 = current_time + 60;

    // locker.create_lock(erc20_address, amount, end);
    // assert(locker.get_total_lock() == 1_u256, 'Total lock should eq 1')

}

// #[test]
// #[available_gas(20000000)]
// fn test_claim_lock() {
//     let (caller, erc20_token, erc20_address, locker, locker_address) = setUp();
//     let amount: u256 = 2000_u256;

//     erc20_token.approve(locker_address, amount);

//     let current_time: u64 = get_block_timestamp();
//     let end: u64 = current_time;

//     locker.create_lock(erc20_address, amount, end);
//     locker.claim_lock(0_u256);
// }

// #[test]
// #[available_gas(20000000)]
// #[should_panic(expected: ('LockNotEnd', 'ENTRYPOINT_FAILED', ))]
// fn test_claim_lock_err_not_end() {
//     let (caller, erc20_token, erc20_address, locker, locker_address) = setUp();
//     let amount: u256 = 2000_u256;

//     erc20_token.approve(locker_address, amount);

//     let current_time: u64 = get_block_timestamp();
//     let end: u64 = current_time + 60;

//     locker.create_lock(erc20_address, amount, end);
//     locker.claim_lock(0_u256);
// }

// #[test]
// #[available_gas(20000000)]
// #[should_panic(expected: ('LockClaimed', 'ENTRYPOINT_FAILED', ))]
// fn test_claim_lock_err_claimed() {
//     let (caller, erc20_token, erc20_address, locker, locker_address) = setUp();
//     let amount: u256 = 2000_u256;

//     erc20_token.approve(locker_address, amount);

//     let current_time: u64 = get_block_timestamp();
//     let end: u64 = current_time;

//     locker.create_lock(erc20_address, amount, end);

//     locker.claim_lock(0_u256);
//     locker.claim_lock(0_u256);
// }
