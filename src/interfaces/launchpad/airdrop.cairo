use starknet::{ContractAddress};
use core::serde::Serde;

#[derive(Drop, Serde)]
struct AirdropStats {
    total_airdrop: u256,
    total_airdrop_amount: u256,
    total_claimed: u256,
}

#[starknet::interface]
trait ISFAirdrop<T> {
    fn get_stats(self: @T) -> AirdropStats;
    fn get_user_stats(self: @T, spender: ContractAddress) -> Array<u256>;
    fn claim(ref self: T, signature: Array<felt252>);
}
