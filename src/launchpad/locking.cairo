use starknet::ContractAddress;
// use starkfinance::utils::{Lock};

#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)] 
struct Lock {
    owner: ContractAddress,
    token: ContractAddress,
    amount: u256,
    start: u64,
    tge: u64,
    is_vesting: bool,
    tge_percent: u256,
}

#[derive(Drop, Serde)]
struct LockStats {
    total_claimed: u256,
    end: u64,
}

#[starknet::interface]
trait ILocking<T> {
    // fn get_total_lock(self: @T) -> u256;
    // fn get_lock(self: @T, lock_id: u256) -> Lock;
    fn create(
        ref self: T,
        owner: ContractAddress,
        token: ContractAddress,
        amount: u256,
        start: u64,
        tge: u64,
        is_vesting: bool,
        tge_percent: u256,
        vesting_time: Array<u64>,
        vesting_percent: Array<u256>,
    );
    // fn claim_lock(ref self: T, lock_id: u256);
}



#[starknet::contract]
mod Locking {
    use starknet::{get_caller_address, get_contract_address, get_block_timestamp};
    use starknet::ContractAddress;

    use super::{Lock, LockStats};
    use starkfinance::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starkfinance::utils::call_fallback::{call_contract_with_selector_fallback};

    #[storage]
    struct Storage {
        total_lock: LegacyMap::<ContractAddress, u256>, // token_address -> latest lock_id of token
        locks: LegacyMap::<(ContractAddress, u256), Lock>, // (token_address, lock_id) -> Lock
        total_vesting: LegacyMap::<(ContractAddress, u256), u32>, // (token_address, lock_id) -> (index, vesting_percent)
        vesting_time: LegacyMap::<(ContractAddress, u256), (u32, u64)>, // (token_address, lock_id) -> (index, vesting_time)
        vesting_percent: LegacyMap::<(ContractAddress, u256), (u32, u256)>, // (token_address, lock_id) -> (index, vesting_percent)
        claimed: LegacyMap::<(ContractAddress, u256), u256>, // token_address, lock_id) -> claimed amount
        claimed_count: LegacyMap::<(ContractAddress, u256), u256>, // (token_address, lock_id) -> claimed count
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Created: Created,
        Claimed: Claimed
    }

    #[derive(Drop, starknet::Event)]
    struct Created {
        token: ContractAddress,
        lock_id: u256,
        timestamp: u64
    }

    #[derive(Drop, starknet::Event)]
    struct Claimed {
        token: ContractAddress,
        lock_id: u256,
        timestamp: u64
    }


    #[external(v0)]
    impl ILockingImpl of super::ILocking<ContractState> {
        fn create(
            ref self: ContractState, 
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
            let mut lock_id = self.total_lock.read(token);

            // TODO first take fee;


            // transfer token lock
            let this_contract = get_contract_address();
            let caller = get_caller_address(); 
            InternalFunctions::_transfer_token_from(token, caller, this_contract, amount);

            lock_id += 1;

            self.locks.write((token, lock_id), Lock {
                owner,
                token,
                amount,
                start,
                tge,
                is_vesting,
                tge_percent,
            });
            if(is_vesting) {
                let total_vesting = vesting_time.len();
                assert(total_vesting == vesting_percent.len(), 'Invalid vesting');
                let mut i: u32 = 0_u32;
                loop {
                    if i>= total_vesting {
                        break;
                    };
                    self.vesting_time.write((token, lock_id),  (i, vesting_time.at(i).clone()));
                    self.vesting_percent.write((token, lock_id), (i, vesting_percent.at(i).clone()));
                    i += 1;
                };
                self.total_vesting.write((token, lock_id), total_vesting);
            }
            self.total_lock.write(token, lock_id);
            
            self.emit(Created { 
                token, 
                lock_id, 
                timestamp: get_block_timestamp() 
            });
        }

        // fn claim_lock(ref self: ContractState, lock_id: u256) {
        //     let this_contract = get_contract_address();
        //     let caller = get_caller_address();  
        //     let current_time: u64 = get_block_timestamp();
        //     let claimed: bool = self.lock_claimed.read(lock_id);

        //     // let lock: Lock = self.locks.read(lock_id);
        //     assert(!claimed, 'LockClaimed');
        //     // assert(lock.locker == caller, 'OnlyLockerCanClaim');
        //     // assert(lock.end <= current_time, 'LockNotEnd');

        //     self.lock_claimed.write(lock_id, true);

        //     // IERC20Dispatcher {contract_address: lock.token}.transfer(caller, lock.amount);

        //     self.emit(ClaimLock { 
        //         id: lock_id, 
        //         timestamp: get_block_timestamp() 
        //     });
        // }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        /// @notice try transferFrom & transfer_from
        fn _transfer_token_from(
            token: ContractAddress,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            let mut call_data = Default::default();
            Serde::serialize(@sender, ref call_data);
            Serde::serialize(@recipient, ref call_data);
            Serde::serialize(@amount, ref call_data);

            call_contract_with_selector_fallback(
                token, selector!("transferFrom"), selector!("transfer_from"), call_data.span()
            )
                .unwrap();
        }
    }
}