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

use starknet::{contract_address_try_from_felt252, get_block_timestamp, contract_address_const};
use starknet::contract_address::ContractAddress;
use starknet::testing::{set_contract_address, pop_log, set_block_timestamp, set_caller_address};
use starknet::syscalls::deploy_syscall;
use starknet::SyscallResultTrait;
use starknet::class_hash::{Felt252TryIntoClassHash, class_hash_to_felt252}; 
use rules_account::account::Account;
use rules_account::account::{ AccountABIDispatcher, AccountABIDispatcherTrait };

use starkfinance::interfaces::token::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use starkfinance::mocks::erc20::{ERC20};
use starkfinance::interfaces::launchpad::airdrop::{
    ISFAirdropDispatcher, ISFAirdropDispatcherTrait, SimpleStruct
};
use starkfinance::launchpad::airdrop::{Airdrop};


const NAME: felt252 = 'Test';
const SYMBOL: felt252 = 'TEST';
const DECIMALS: u8 = 18_u8;

const ONE_HUNDRED_PERCENT: u256 = 100_000_u256;

fn STATE() -> Account::ContractState {
    Account::unsafe_new_contract_state()
}

fn CLASS_HASH() -> felt252 {
    Account::TEST_CLASS_HASH
}
fn ACCOUNT_ADDRESS() -> ContractAddress {
    contract_address_const::<0x111111>()
}


fn setUp() -> (
        ContractAddress, 
        ContractAddress,
        IERC20Dispatcher, 
        ContractAddress
    ) {
    let caller = contract_address_try_from_felt252('admin').unwrap();
    set_contract_address(caller);

    let other_caller = contract_address_try_from_felt252('user2').unwrap();

    // deploy ERC20 
    let mut erc20_calldata = array![NAME, SYMBOL, DECIMALS.into()];
    let (erc20_address, _) = deploy_syscall(
        ERC20::TEST_CLASS_HASH.try_into().unwrap(), 0, erc20_calldata.span(), false
    )
        .unwrap();
    let mut erc20_token = IERC20Dispatcher { contract_address: erc20_address };

    (
        caller, 
        other_caller, 
        erc20_token, 
        erc20_address, 
    )
}

fn deploy_airdrop(
        token: ContractAddress,
        start: u64,
        total_airdrop: u256,
        total_airdrop_amount: u256,
        vesting_time: Array<u64>,
        vesting_percent: Array<u256>,
    ) -> (ISFAirdropDispatcher, ContractAddress) {
    let mut metadata = ArrayTrait::new();
    token.serialize(ref metadata);
    start.serialize(ref metadata);
    total_airdrop.serialize(ref metadata); 
    total_airdrop_amount.serialize(ref metadata);
    vesting_time.serialize(ref metadata); 
    vesting_percent.serialize(ref metadata); 
    
    let (airdrop_address, _) = deploy_syscall(
        Airdrop::TEST_CLASS_HASH.try_into().unwrap(), 0, metadata.span(), false
    )
        .unwrap();
    let mut airdrop = ISFAirdropDispatcher { contract_address: airdrop_address };

    (airdrop, airdrop_address)
}

#[test]
#[available_gas(20000000)]
fn test_signature() {

}


#[test]
#[available_gas(20000000)]
fn test_deploy_airdrop() {
    let (
        caller, 
        other_caller, 
        erc20_token, 
        erc20_address, 
    ) = setUp();

    let start = get_block_timestamp();
    let total_airdrop = 100;
    let total_airdrop_amount = 5000;  
    let vesting_time = array![0, 3600];
    let vesting_percent = array![50000,50000];

    let (airdrop, airdrop_address) = deploy_airdrop(
        erc20_address,
        start,
        total_airdrop,
        total_airdrop_amount,
        vesting_time,
        vesting_percent
    );

    // set_contract_address(caller);
    // erc20_token.mint(total_airdrop_amount);

    // erc20_token.approve(airdrop_address, total_airdrop_amount);
    // assert(erc20_token.allowance(caller, airdrop_address) == total_airdrop_amount, 'Approve should eq');

    // erc20_token.transfer(airdrop_address, total_airdrop_amount);
    // assert(erc20_token.balanceOf(airdrop_address) == total_airdrop_amount, 'No airdrop token in pool');

    set_contract_address(contract_address_const::<420>());
    let hash = airdrop.compute_message_hash(
        // contract_address_try_from_felt252(0x02300fC66a817547f90A96Bf45A6029033C67392F513BC8e7e05aDe0e92A36b8).unwrap()
        SimpleStruct {
            some_felt252: 712,
            some_u128: 42,
        }
    );

    hash.print();
}

// #[test]
// #[available_gas(20000000)]
// fn test_claim_airdrop() {
    // let (
    //     caller, 
    //     other_caller, 
    //     erc20_token, 
    //     erc20_address, 
    // ) = setUp();
    // let start = get_block_timestamp();
    // let total_airdrop = 100;
    // let total_airdrop_amount = 5000;  
    // let vesting_time = array![0, 3600];
    // let vesting_percent = array![50000,50000];

    // let (airdrop, airdrop_address) = deploy_airdrop(
    //     erc20_address,
    //     start,
    //     total_airdrop,
    //     total_airdrop_amount,
    //     vesting_time,
    //     vesting_percent
    // );

    // set_contract_address(caller);
    // erc20_token.mint(total_airdrop_amount);
    // erc20_token.approve(airdrop_address, total_airdrop_amount);
    // erc20_token.transfer(airdrop_address, total_airdrop_amount);

    // set_block_timestamp(start + 1);

    // set_contract_address(caller);

    // airdrop.compute_message_hash(
    //     caller,
    //     // other_caller
    // )
    //     .print();

    // // airdrop.claim();

    // let balance = erc20_token.balanceOf(caller);
    // // balance.print();
    // assert(balance == airdrop.get_user_stats(caller).at(2).clone(), 'InvalidAirdropAmount');
// }


// #[test]
// #[available_gas(20000000)]
// fn test_claim_airdrop_in_whitelist() {

//      let mut state = STATE();
//     let data = SIGNED_TX_DATA();
//     let hash = data.transaction_hash;

//     let mut good_signature = array![data.r, data.s];
//     let mut bad_signature = array![0x987, 0x564];

//     PublicKeyImpl::set_public_key(ref state, data.public_key);


//     let (
//         caller, 
//         other_caller, 
//         erc20_token, 
//         erc20_address, 
//     ) = setUp();

    
//     // let state = AccountComponent::component_state_for_testing();

// }