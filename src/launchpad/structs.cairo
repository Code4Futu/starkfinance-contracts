use starknet::ContractAddress;
use starknet::contract_address_const;
use array::ArrayTrait;
use core::result::ResultTrait;
use option::OptionTrait;
use starknet::class_hash::Felt252TryIntoClassHash;
use traits::TryInto;

#[derive(Copy, Drop, Serde, starknet::Store)] 
struct Lock {
    token: ContractAddress,
    locker: ContractAddress,
    amount: u256,
    end: u64,
}

impl LockDefault of Default<Lock> {
    fn default() -> Lock {
        Lock { 
            token: contract_address_const::<0>(), 
            locker: contract_address_const::<0>(), 
            amount: 0_u256, 
            end: 0_64 
        }
    }
}