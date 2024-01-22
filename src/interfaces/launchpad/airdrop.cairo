use starknet::{ContractAddress};
use core::serde::Serde;


#[derive(Drop, Copy, Hash)]
struct AirdropStruct {
    address: felt252,
}

#[derive(Drop, Copy, Hash, Serde)]
struct SimpleStruct {
    some_felt252: felt252,
    some_u128: u128,
}

#[derive(Drop, Serde)]
struct AirdropStats {
    total_claimed: u256,
    end: u64,
}

#[starknet::interface]
trait ISFAirdrop<T> {
    fn get_stats(self: @T) -> AirdropStats;
    fn get_user_stats(self: @T, spender: ContractAddress) -> Array<u256>;
    fn claim(ref self: T, signature: Array<felt252>);
    fn compute_message_hash(self: @T, simple: SimpleStruct) -> felt252;
    // fn verify_signature(self: @T, account: ContractAddress,  signature: Array<felt252>) -> bool;
}
