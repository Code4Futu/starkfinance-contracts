#[starknet::contract]
mod SFLaunchpad {
    use core::debug::PrintTrait;
    use core::array::ArrayTrait;
    use core::serde::Serde;
    use starknet::{
        ContractAddress, 
        get_block_timestamp,
        get_contract_address,
        get_caller_address,
    };
    use traits::{Into, TryInto};
    use option::OptionTrait;
    use integer::u256_from_felt252;
    use array::Array;
    use clone::Clone;

    // locals
    use starkfinance::interfaces::launchpad::launchpad::{ISFLaunchpad, LaunchpadStats, UserStats};
    use starkfinance::interfaces::token::erc20::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait};
    use starkfinance::interfaces::token::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};

    #[storage]
    struct Storage {
        admin: ContractAddress,
        nft: ContractAddress,
        owner: ContractAddress,
        percent_fee: u256,
        token_sale: ContractAddress,
        token_raise: ContractAddress,
        total_sale: u256,
        total_raise: u256,
        start: u64,
        end: u64,
        total_vesting: u32,
        vesting_time: LegacyMap::<u32, u64>,
        vesting_percent: LegacyMap::<u32, u256>,
        min_commit: u256,
        max_commit: u256,
        total_participial: u256,
        total_committed: u256,
        total_committed_boosted: u256,
        user_committed: LegacyMap::<ContractAddress, u256>,
        user_claimed: LegacyMap::<ContractAddress, u256>,
        user_claim_count: LegacyMap::<ContractAddress, u32>,
        staked_nft: LegacyMap::<ContractAddress, (u256, bool, bool)>, // address -> (nft_id, is_staked, is_claimed)
        is_claimed_token_raise: bool,
        user_claimed_remaining: LegacyMap::<ContractAddress, u256>,
        last_committed_time: LegacyMap::<ContractAddress, u64>,
        is_canceled: bool
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Commit: Commit,
        ClaimCommit: ClaimCommit,
        StakedNft: StakedNft,
        ClaimRaise: ClaimRaise
    }

    #[derive(Drop, starknet::Event)]
    struct StakedNft {
        staker: ContractAddress,
        nft_id: u256,
        timestamp: u64
    }

    #[derive(Drop, starknet::Event)]
    struct Commit {
        committer: ContractAddress,
        amount: u256,
        timestamp: u64
    }

    #[derive(Drop, starknet::Event)]
    struct ClaimCommit {
        claimer: ContractAddress,
        amount: u256,
        timestamp: u64
    }

    #[derive(Drop, starknet::Event)]
    struct ClaimRaise {
        amount: u256,
        timestamp: u64
    }

    const TEN_PERCENT: u256 = 10_000_u256;
    const ONE_HUNDRED_PERCENT: u256 = 100_000_u256;
    const MIN_CLAIM: u256 = 1_000_000_000_000_000_u256;

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        nft: ContractAddress,
        owner: ContractAddress,
        percent_fee: u256,
        token_sale: ContractAddress,
        token_raise: ContractAddress,
        total_sale: u256,
        total_raise: u256,
        start: u64,
        end: u64,
        min_commit: u256,
        max_commit: u256,
        vesting_time: Array<u64>,
        vesting_percent: Array<u256>,
    ) {
        self.admin.write(admin);
        self.nft.write(nft);
        self.owner.write(owner);
        self.percent_fee.write(percent_fee);
        self.token_sale.write(token_sale);
        self.token_raise.write(token_raise);
        self.total_sale.write(total_sale);
        self.total_raise.write(total_raise);
        self.start.write(start);
        self.end.write(end);
        self.min_commit.write(min_commit);
        self.max_commit.write(max_commit);

        let total_vesting = vesting_time.len();
        assert(total_vesting == vesting_percent.len(), 'Invalid vesting');
        let mut i: u32 = 0_u32;
        loop {
            if i>= total_vesting {
                break;
            };
            self.vesting_time.write((i), vesting_time.at(i).clone());
            self.vesting_percent.write((i), vesting_percent.at(i).clone());
            i += 1;
        };
        self.total_vesting.write(total_vesting);
    }

    #[external(v0)]
    impl ISFLaunchpadImp of ISFLaunchpad<ContractState> {
        fn get_stats(self: @ContractState) -> LaunchpadStats {
            LaunchpadStats {
                total_participial: self.total_participial.read(),
                total_committed: self.total_committed.read(),
                total_committed_boosted: self.total_committed_boosted.read(),
                is_canceled: self.is_canceled.read()
            }
        }

        fn get_user_stats(self: @ContractState, spender: ContractAddress) -> UserStats {
            UserStats {
                committed: self._get_user_committed(spender),
                allocation:  self._get_allocation(spender),
                deducted: self._get_deducted(spender),
                remaining: self._get_remaining(spender),
                claimed: self.user_claimed.read(spender),
                claimed_count:  self.user_claim_count.read(spender),
                last_committed_time: self.last_committed_time.read(spender),
                claimable: self._get_claimable(spender)
            }
        }

        fn stake_nft(ref self: ContractState, nft_id: u256) {
            let caller = get_caller_address(); 
            let this_contract = get_contract_address();
            let (_ ,is_staked, _) = self.staked_nft.read(caller);
            assert(!is_staked, 'Only can stake 1 NFT in 1 pool');
            IERC721Dispatcher {contract_address: self.nft.read()}
                .transferFrom(caller, this_contract, nft_id);
            self.staked_nft.write(caller, (nft_id, true, false));

            self.total_committed_boosted.write(
                    self.user_committed.read(caller) * TEN_PERCENT / ONE_HUNDRED_PERCENT 
                        + self.total_committed_boosted.read()
                );

            self.emit(StakedNft {
                staker: caller,
                nft_id: nft_id,
                timestamp: get_block_timestamp()
            })
        }

        fn commit(ref self: ContractState, commit_token_raise: u256) {
            assert(!self.is_canceled.read(), 'Canceled');
            let timestamp = get_block_timestamp();
            assert(timestamp >= self.start.read(), 'NotStart');

            let end: u64 = self.end.read();
            assert(timestamp <= end, 'Ended');

            assert(commit_token_raise >= self.min_commit.read() , 'MinCommit');

            let caller = get_caller_address(); 
            let current_commit = self.user_committed.read(caller);

            assert(current_commit + commit_token_raise <= self.max_commit.read(), 'MaxCommit');

            if (current_commit == 0) {
                self.total_participial
                    .write(self.total_participial.read() + 1);
            }

            let this_contract = get_contract_address();

            IERC20Dispatcher {contract_address: self.token_raise.read()}
                .transferFrom(caller, this_contract, commit_token_raise);
            
            self.user_committed
                .write(caller, current_commit + commit_token_raise);
            self.total_committed
                .write(commit_token_raise + self.total_committed.read());

            let (_ ,is_staked, _) = self.staked_nft.read(caller);
            if (is_staked) {
                self.total_committed_boosted.write(
                    commit_token_raise * TEN_PERCENT / ONE_HUNDRED_PERCENT 
                        + self.total_committed_boosted.read());
            } else {
                self.total_committed_boosted
                    .write(commit_token_raise + self.total_committed_boosted.read());
            }

            self.last_committed_time.write(caller, timestamp);

            self.emit(Commit { 
                committer: caller, 
                amount: commit_token_raise, 
                timestamp 
            });
        }

        fn claim(ref self: ContractState) {
            let timestamp = get_block_timestamp();
            let end: u64 = self.end.read();
            assert(timestamp > end,  'NotEnd');

            let total_round = self.total_vesting.read();
            let caller = get_caller_address(); 
            let user_claim_count = self.user_claim_count.read(caller);
            assert(user_claim_count < total_round, 'InvalidVestingRound');
            assert(timestamp >= self.last_committed_time.read(caller) 
                + self.vesting_time.read(user_claim_count), 'VestingRoundNotStart'
            );

            let allocation: u256 = self._get_allocation(caller) * 
                self.vesting_percent.read(user_claim_count) 
                / ONE_HUNDRED_PERCENT;

            assert(allocation > 0_u256, 'NothingToClaim');

            let (nft_id ,is_staked, is_claimed) = self.staked_nft.read(caller); 
            if (is_staked && !is_claimed) {
                self.staked_nft
                    .write(caller, (nft_id, true, true));
                IERC721Dispatcher {contract_address: self.nft.read()}
                    .transferFrom(get_contract_address(), caller, nft_id);
            }

            self.user_claim_count
                .write(caller, user_claim_count + 1);

            self.user_claimed
                .write(caller, self.user_claimed.read(caller) + allocation);

            IERC20Dispatcher {contract_address: self.token_sale.read()}
                .transfer(caller, allocation);

            self.emit(ClaimCommit { 
                claimer: caller, 
                amount: allocation, 
                timestamp 
            });
        }

        fn claim_token_raise(ref self: ContractState) {
            let caller = get_caller_address();
            let timestamp = get_block_timestamp();
            assert(caller == self.owner.read(), 'NotOwner');
            assert(timestamp > self.end.read(),  'NotEnd');

            self.is_claimed_token_raise.write(true);

            let mut claimable_raise = self.total_committed.read();
            let total_raise = self.total_raise.read();
            if (claimable_raise > total_raise) {
                claimable_raise = total_raise;
            }
            IERC20Dispatcher {contract_address: self.token_raise.read()}
                .transfer(caller, claimable_raise);

            self.emit(ClaimRaise { 
                amount: claimable_raise, 
                timestamp 
            });
        }

        fn claim_remaining(ref self: ContractState) {
            assert(get_block_timestamp() > self.end.read(),  'NotEnd');

            let caller = get_caller_address();

            let remaining = self._get_remaining(caller);
            assert(remaining > 0, 'NothingToClaim');
            
            self.user_claimed_remaining
                .write(caller, self.user_claimed_remaining.read(caller) + remaining);

            IERC20Dispatcher {contract_address: self.token_raise.read()}
                .transfer(caller, remaining);
        }

        fn cancel(ref self: ContractState) {
            let caller = get_caller_address();

            assert(get_block_timestamp() < self.end.read(),  'Ended');
            assert(get_caller_address() == self.admin.read(), 'Unauthorized');

            self.is_canceled.write(true);
        }
    }

    #[generate_trait]
    impl StorageImpl of StorageTrait {
        fn _get_user_committed(self: @ContractState, spender: ContractAddress) -> u256 {
            let mut user_committed: u256 = self.user_committed.read(spender);
            let (_ ,is_staked, _) = self.staked_nft.read(spender); 
            let is_boost: bool = self.total_committed.read() > self.total_raise.read();
            if (is_staked && is_boost) {
                user_committed = user_committed 
                    + user_committed * TEN_PERCENT 
                    / ONE_HUNDRED_PERCENT;
            }
            return user_committed;
        }

        fn _get_allocation(self: @ContractState, spender: ContractAddress) -> u256 {
            if (self.is_canceled.read()) {
                return 0;
            }
            let is_boost: bool = self.total_committed.read() > self.total_raise.read();
            let user_committed: u256 = self._get_user_committed(spender);
            let mut raise_tmp: u256 = self.total_raise.read();
            if (is_boost) {
                raise_tmp = self.total_committed_boosted.read();
            }
            return user_committed * self.total_sale.read() / raise_tmp;
        }

        fn _get_claimable(self: @ContractState, spender: ContractAddress) -> u256 {
            let user_claim_count = self.user_claim_count.read(spender);
            let claimable = self._get_allocation(spender) 
                * self.vesting_percent.read(user_claim_count) 
                / ONE_HUNDRED_PERCENT;
            if (claimable < MIN_CLAIM) {
                return 0;
            }
            return claimable;
        }

        fn _get_deducted(self: @ContractState, spender: ContractAddress) -> u256 {
            if (self.is_canceled.read()) {
                return 0;
            }
            return self._get_allocation(spender) * self.total_raise.read() / self.total_sale.read();
        }

        fn _get_remaining(self: @ContractState, spender: ContractAddress) -> u256 {
            let remain = self.user_committed.read(spender) 
                - self._get_deducted(spender) 
                - self.user_claimed_remaining.read(spender);
            if (remain < MIN_CLAIM) {
                return 0;
            }
            return remain;
        }
    }
}
