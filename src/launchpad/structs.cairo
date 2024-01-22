use starknet::ContractAddress;
use starknet::contract_address_const;
use array::ArrayTrait;
use core::result::ResultTrait;
use option::OptionTrait;
use starknet::class_hash::Felt252TryIntoClassHash;
use traits::TryInto;

#[derive(Drop, Serde)] 
struct Lock {
    owner: ContractAddress,
    token: ContractAddress,
    amount: u256,
    start: u64,
    tge: u64,
    is_vesting: bool,
    tge_percent: u256,
    // vesting_time: Array<u64>,
    // vesting_percent: Array<u256>,
}

impl LockDefault of Default<Lock> {
    fn default() -> Lock {
        Lock { 
            owner: contract_address_const::<0>(), 
            token: contract_address_const::<0>(), 
            amount: 0_u256,
            start: 0_u64,
            tge: 0_u64,
            is_vesting: false,
            tge_percent: 0_u256,
            // vesting_time: array![],
            // vesting_percent: array![],
        }
    }
}