#[starknet::contract]
mod SFLocking {
    use core::debug::PrintTrait;
use starknet::{
        get_caller_address, 
        get_contract_address, 
        get_block_timestamp,
        call_contract_syscall,
        ContractAddress
    };
    
    use array::ArrayTrait;


    // locals
    use starkfinance::interfaces::token::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starkfinance::utils::call_fallback::{call_contract_with_selector_fallback};
    use starkfinance::interfaces::launchpad::locking::{ISFLocking, Lock};


    const ONE_HUNDRED_PERCENT: u256 = 100_000_u256;

    #[storage]
    struct Storage {
        total_lock: LegacyMap::<ContractAddress, u256>, // token_address -> latest lock_id of token
        locks: LegacyMap::<(ContractAddress, u256), Lock>, // (token_address, lock_id) -> Lock
        total_vesting: LegacyMap::<(ContractAddress, u256), u32>, // (token_address, lock_id) -> total_vesting
        vesting_time: LegacyMap::<(ContractAddress, u256, u32), u64>, // (token_address, lock_id, index) -> vesting_time
        vesting_percent: LegacyMap::<(ContractAddress, u256, u32), u256>, // (token_address, lock_id, index) -> vesting_percent
        unlocked_count: LegacyMap::<(ContractAddress, u256, ContractAddress), u32>, // (token_address, lock_id, user_address) -> claimed count
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
    impl ISFLockingImpl of ISFLocking<ContractState> {
        fn get_lock(self: @ContractState, token: ContractAddress, lock_id: u256) -> (Lock, Array<u64>, Array<u256>) {
            assert(lock_id < self.total_lock.read(token), 'Invalid lock id');

            let lock: Lock = self.locks.read((token, lock_id));

            let mut vesting_time: Array<u64> = ArrayTrait::<u64>::new();
            let mut vesting_percent: Array<u256> = ArrayTrait::<u256>::new();
        
            let total_vesting = self.total_vesting.read((token, lock_id));
            let mut i: u32 = 0_u32;
            loop {
                if i>= total_vesting {
                    break;
                };
                vesting_time.append(
                    self.vesting_time.read((token, lock_id, i))
                );
                vesting_percent.append(
                    self.vesting_percent.read((token, lock_id, i))
                );
                i += 1;
            };
            
            (lock, vesting_time, vesting_percent)
        }

        fn get_unlocked_count(self: @ContractState, token: ContractAddress, lock_id: u256, spender: ContractAddress) -> u32 {
            self.unlocked_count.read((token, lock_id, spender))
        }

        fn lock(
            ref self: ContractState, 
            owner: ContractAddress,
            token: ContractAddress,
            amount: u256,
            vesting_time: Array<u64>,
            vesting_percent: Array<u256>,
        ) {
            let total_vesting = vesting_time.len();
            assert(total_vesting > 0 && total_vesting == vesting_percent.len(), 'InvalidVesting');

            let mut lock_id = self.total_lock.read(token);

            // TODO first take fee;

            // transfer token lock
            let this_contract = get_contract_address();
            let caller = get_caller_address(); 
            InternalFunctions::_transfer_token_from(token, caller, this_contract, amount);

            let mut total_percent: u256 = 0;
            let mut i: u32 = 0_u32;
            loop {
                if i>= total_vesting {
                    break;
                };
                self.vesting_time.write((token, lock_id, i),  vesting_time.at(i).clone());
                let percent = vesting_percent.at(i).clone();
                self.vesting_percent.write((token, lock_id, i), percent);
                total_percent += percent;
                i += 1;
            };
            self.total_vesting.write((token, lock_id), total_vesting);
            assert(total_percent == ONE_HUNDRED_PERCENT, 'MustEq100%');

            self.locks.write((token, lock_id), Lock {
                owner,
                token,
                amount,
            });

            self.emit(Created { 
                token, 
                lock_id, 
                timestamp: get_block_timestamp() 
            });

            lock_id += 1;
            self.total_lock.write(token, lock_id);
        }

        fn unlock(ref self: ContractState, token: ContractAddress, lock_id: u256) {
            let this_contract: ContractAddress = get_contract_address();
            let caller: ContractAddress = get_caller_address();  
            let current_time: u64 = get_block_timestamp();

            assert(lock_id < self.total_lock.read(token), 'InvalidLockId');
            
            let lock: Lock = self.locks.read((token, lock_id));

            assert(caller == lock.owner, 'Unauthorzied');

            let unlocked_count: u32 = self.unlocked_count.read((token, lock_id, caller));
            assert(unlocked_count < self.total_vesting.read((token, lock_id)), 'UnlockedAll');

            let mut amount: u256 = 0;

            assert(current_time >= self.vesting_time.read((token, lock_id, unlocked_count)), 'InvalidUnlockTime');
            amount = lock.amount * self.vesting_percent.read((token, lock_id, unlocked_count )) / ONE_HUNDRED_PERCENT;
            
            self.unlocked_count.write((token, lock_id, caller), unlocked_count + 1);

            if(amount > 0) {
                InternalFunctions::_transfer_token(token, this_contract, caller, amount);
            }
        }
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

        fn _transfer_token(
            token: ContractAddress,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            let mut call_data = Default::default();
            Serde::serialize(@recipient, ref call_data);
            Serde::serialize(@amount, ref call_data);

            call_contract_syscall(token, selector!("transfer"), call_data.span());
        }
    }
}