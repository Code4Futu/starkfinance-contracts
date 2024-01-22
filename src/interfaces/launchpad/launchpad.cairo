use core::serde::Serde;
use starknet::{ContractAddress};

#[derive(Drop, Serde)]
struct LaunchpadStats {
    total_participial: u256,
    total_committed: u256,
    total_committed_boosted: u256,
    is_canceled: bool
}

#[derive(Drop, Serde)]
struct UserStats {
    committed: u256,
    allocation: u256,
    deducted: u256,
    remaining: u256,
    claimed: u256,
    claimed_count: u32,
    last_committed_time: u64,
    claimable: u256
}

#[starknet::interface]
trait ISFLaunchpad<T> {
    fn get_stats(self: @T) -> LaunchpadStats;
    fn get_user_stats(self: @T, spender: ContractAddress) -> UserStats;
    fn stake_nft(ref self: T, nft_id: u256);
    fn commit(ref self: T, commit_token_raise: u256);
    fn claim(ref self: T);
    fn claim_token_raise(ref self: T);
    fn claim_remaining(ref self: T);
    fn cancel(ref self: T);
}