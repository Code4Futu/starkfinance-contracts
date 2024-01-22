use starknet::ContractAddress;

#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)] 
struct Lock {
    owner: ContractAddress,
    token: ContractAddress,
    amount: u256,
    tge: u64,
    is_vesting: bool,
    tge_percent: u256,
}

#[starknet::interface]
trait ISFLocking<T> {
    fn get_lock(self: @T, token: ContractAddress, lock_id: u256) -> (Lock, Array<u64>, Array<u256>);
    fn get_claimed_count(self: @T, token: ContractAddress, lock_id: u256, spender: ContractAddress) -> u32;
    fn lock(
        ref self: T,
        owner: ContractAddress,
        token: ContractAddress,
        amount: u256,
        tge: u64,
        is_vesting: bool,
        tge_percent: u256,
        vesting_time: Array<u64>,
        vesting_percent: Array<u256>,
    );
    fn unlock(ref self: T, token: ContractAddress, lock_id: u256);
}
