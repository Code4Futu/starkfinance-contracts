use starknet::ContractAddress;
// use starkfinance::utils::{Lock};

#[starknet::interface]
trait ILocker<T> {
    fn get_total_lock(self: @T) -> u256;
    // fn get_lock(self: @T, lock_id: u256) -> Lock;
    fn create_lock(ref self: T, token: ContractAddress, amount: u256, end: u64);
    fn claim_lock(ref self: T, lock_id: u256);
}

#[starknet::contract]
mod Locker {
    use starknet::{get_caller_address, get_contract_address, get_block_timestamp};
    use starknet::ContractAddress;

    // use super::{Lock};
    use starkfinance::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    struct Storage {
        token_lock: LegacyMap::<u256, u256>,
        total_lock: u256,

        locks: LegacyMap::<u256, Lock>,
        lock_claimed: LegacyMap::<u256, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        CreateLock: CreateLock,
        ClaimLock: ClaimLock
    }

    #[derive(Drop, starknet::Event)]
    struct CreateLock {
        id: u256,
        token: ContractAddress,
        locker: ContractAddress,
        amount: u256,
        end: u64,
        timestamp: u64
    }

    #[derive(Drop, starknet::Event)]
    struct ClaimLock {
        id: u256,
        timestamp: u64
    }


    #[external(v0)]
    impl ILockerImpl of super::ILocker<ContractState> {
        fn get_total_lock(self: @ContractState) -> u256 {
            self.total_lock.read()
        }

        // fn get_lock(self: @ContractState, lock_id: u256) -> Lock {
        //     self.locks.read(lock_id)
        // }

        fn create_lock(ref self: ContractState, token: ContractAddress, amount: u256, end: u64) {
            let this_contract = get_contract_address();
            let caller = get_caller_address(); 

            IERC20Dispatcher {contract_address: token}.transferFrom(caller, this_contract, amount);
            
            let current_total_lock: u256 = self.total_lock.read();
            self.total_lock.write(current_total_lock + 1);
            // self.locks.write(current_total_lock, Lock {
            //     token,
            //     locker: caller,
            //     amount,
            //     end,
            // });
            self.lock_claimed.write(current_total_lock, false);

            self.emit(CreateLock { 
                id: current_total_lock, 
                token, 
                locker: caller, 
                amount, 
                end, 
                timestamp: get_block_timestamp() 
            });
        }

        fn claim_lock(ref self: ContractState, lock_id: u256) {
            let this_contract = get_contract_address();
            let caller = get_caller_address();  
            let current_time: u64 = get_block_timestamp();
            let claimed: bool = self.lock_claimed.read(lock_id);

            // let lock: Lock = self.locks.read(lock_id);
            assert(!claimed, 'LockClaimed');
            // assert(lock.locker == caller, 'OnlyLockerCanClaim');
            // assert(lock.end <= current_time, 'LockNotEnd');

            self.lock_claimed.write(lock_id, true);

            // IERC20Dispatcher {contract_address: lock.token}.transfer(caller, lock.amount);

            self.emit(ClaimLock { 
                id: lock_id, 
                timestamp: get_block_timestamp() 
            });
        }
    }
}