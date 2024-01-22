#[starknet::contract]
mod Airdrop {
    use core::debug::PrintTrait;
    
    use array::ArrayTrait;
    use option::OptionTrait;
    use traits::{Into, TryInto};
    use starknet::{
        ContractAddress, 
        contract_address_const, 
        get_block_timestamp,
        get_contract_address,
        get_caller_address,
        contract_address_try_from_felt252,
        contract_address_to_felt252,
        get_tx_info
    };
    use rules_account::account::Account;
    use rules_account::account::Account::InternalTrait as AccountInternalTrait;
    use ecdsa::check_ecdsa_signature;

    use starkfinance::interfaces::token::erc20::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait};
    use starkfinance::utils::constants::{
        STARKNET_MESSAGE_PREFIX,
        DOMAIN_NAME,
        DOMAIN_VERSION, 
        DOMAIN_TYPE_HASH, 
        ERC165_ACCOUNT_INTERFACE_ID
    };
    use starkfinance::interfaces::launchpad::airdrop::{ISFAirdrop, AirdropStats, AirdropStruct};

    #[storage]
    struct Storage {
        verifier: ContractAddress,
        token: ContractAddress,
        start: u64,
        end: u64,
        total_airdrop: u256,
        total_airdrop_amount: u256,
        total_vesting: u32,
        vesting_time: LegacyMap::<u32, u64>,
        vesting_percent: LegacyMap::<u32, u256>,
        user_claim_count: LegacyMap::<ContractAddress, u32>,
        user_claimed: LegacyMap::<ContractAddress, u256>,
        total_claimed: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ClaimAirdrop: ClaimAirdrop,
    }

    #[derive(Drop, starknet::Event)]
    struct ClaimAirdrop {
        claimer: ContractAddress,
        amount: u256,
        timestamp: u64
    }

    const ONE_HUNDRED_PERCENT: u256 = 100_000_u256;
    const AIRDROP_TYPE_HASH: felt252 = selector!("AirdropStruct(address:felt252)");

    const SIGNATURE_R: felt252 = '0x436369c6d3049b';
    const SIGNATURE_S: felt252 = '0x64e17515627d9f';

    #[constructor]
    fn constructor(
        ref self: ContractState,
        token: ContractAddress,
        start: u64,
        total_airdrop: u256,
        total_airdrop_amount: u256,
        vesting_time: Array<u64>,
        vesting_percent: Array<u256>,
    ) {
        self.token.write(token);
        self.start.write(start);
        self.total_airdrop.write(total_airdrop);
        self.total_airdrop_amount.write(total_airdrop_amount);

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
    impl ISFAirdropImp of ISFAirdrop<ContractState> {
        fn get_stats(self: @ContractState) -> AirdropStats {
            AirdropStats {
                total_claimed: self.total_claimed.read(),
                end: self.end.read()
            }
        }

        fn get_user_stats(self: @ContractState, spender: ContractAddress) -> Array<u256> {
            return array![
                self._get_allocation(),
                self.user_claim_count.read(spender).into(),
                self.user_claimed.read(spender),
            ];
        }

        fn claim(
            ref self: ContractState,
            signature: Array<felt252>,
        ) {
            let timestamp = get_block_timestamp();

            let total_claimed: u256 = self.total_claimed.read();
            let total_airdrop_amount = self.total_airdrop_amount.read();
            assert(total_claimed < total_airdrop_amount, 'Ended');

        
            assert(
                signature.at(0).clone() == SIGNATURE_R 
                && signature.at(1).clone() == SIGNATURE_S,
                'InvalidSignature'
            );

            let total_round = self.total_vesting.read();
            let caller = get_caller_address(); 
            let user_claim_count = self.user_claim_count.read(caller);
            assert(user_claim_count < total_round, 'InvalidVestingRound');
            assert(timestamp >= self.start.read() + self.vesting_time.read(user_claim_count), 'VestingRoundNotStart');

            let allocation: u256 = self._get_allocation() * self.vesting_percent.read(user_claim_count) / ONE_HUNDRED_PERCENT;

            assert(allocation > 0_u256, 'NothingToClaim');

            IERC20Dispatcher {contract_address: self.token.read()}.transfer(caller, allocation);

            self.user_claim_count.write(caller, user_claim_count + 1);
            self.user_claimed.write(caller, self.user_claimed.read(caller) + allocation);
            self.total_claimed.write(total_claimed + allocation);

            if(total_claimed + allocation == total_airdrop_amount) {
                self.end.write(timestamp);
            }

            self.emit(ClaimAirdrop { 
                claimer: caller, 
                amount: allocation, 
                timestamp 
            });
        }

        fn compute_message_hash (
            self: @ContractState, account: ContractAddress
        ) -> felt252 {
            return self._compute_hash(account, self.verifier.read());
        }

        fn verify_signature(
            self: @ContractState, account: ContractAddress, signature: Array<felt252>
        ) -> bool {
            let hash: felt252 = self.compute_message_hash(account);
            self._is_valid_signature(hash, signature.span())
        }
    }

    #[generate_trait]
    impl StorageImpl of StorageTrait {
        fn _get_allocation(self: @ContractState) -> u256 {
            return self.total_airdrop_amount.read() / self.total_airdrop.read();
        }

        fn _get_domain_hash(self: @ContractState) -> felt252 {
            let mut hash = pedersen::pedersen(0, DOMAIN_TYPE_HASH);
            hash = pedersen::pedersen(hash, DOMAIN_NAME);
            hash = pedersen::pedersen(hash, get_tx_info().unbox().chain_id);
            hash = pedersen::pedersen(hash, DOMAIN_VERSION);
            hash = pedersen::pedersen(hash, contract_address_to_felt252(get_contract_address()));
            pedersen::pedersen(hash, 5)
        }

        fn _typed_data_hash(self: @ContractState, account: ContractAddress) -> felt252 {
            let mut hash = pedersen::pedersen(0, AIRDROP_TYPE_HASH);
            hash = pedersen::pedersen(hash, account.into());
            pedersen::pedersen(hash, 2)
        }
        
        fn _compute_hash(
            self: @ContractState, account: ContractAddress, signer: ContractAddress
        ) -> felt252 {
            let mut hash = pedersen::pedersen(0, STARKNET_MESSAGE_PREFIX);
            hash = pedersen::pedersen(hash, self._get_domain_hash());
            hash = pedersen::pedersen(hash, signer.into());
            hash = pedersen::pedersen(hash, self._typed_data_hash(account));
            pedersen::pedersen(hash, 4)
        }

        fn _is_valid_signature(
            self: @ContractState, hash: felt252, signature: Span<felt252>
        ) -> bool {
            let valid_length = signature.len() == 2_u32;
            if valid_length {
                check_ecdsa_signature(
                    hash, self.verifier.read().into(), *signature.at(0_u32), *signature.at(1_u32)
                )
            } else {
                false
            }
        }

        fn _verify_signature(
            self: @ContractState, 
            hash: felt252, 
            signature: Array<felt252>, 
            account: ContractAddress
        ) {
            assert(
                self._is_valid_signature(hash, signature.span()),
                'Invalid  signature'
            );
        }

        
    }
}
