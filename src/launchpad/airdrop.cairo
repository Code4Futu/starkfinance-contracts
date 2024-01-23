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

    use ecdsa::check_ecdsa_signature;
    use pedersen::PedersenTrait;
    use hash::{HashStateTrait, HashStateExTrait};
    use box::BoxTrait;
    
    use starkfinance::interfaces::account::{IAccountABIDispatcher, IAccountABIDispatcherTrait};
    use starkfinance::interfaces::token::erc20::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait};
    use starkfinance::utils::constants::{
        STARKNET_MESSAGE_PREFIX,
        DOMAIN_NAME,
        DOMAIN_VERSION, 
        DOMAIN_TYPE_HASH, 
        ERC165_ACCOUNT_INTERFACE_ID
    };
    use starkfinance::interfaces::launchpad::airdrop::{ISFAirdrop, AirdropStats};
    

    const ONE_HUNDRED_PERCENT: u256 = 100_000_u256;

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

    #[constructor]
    fn constructor(
        ref self: ContractState,
        verifier: ContractAddress,
        token: ContractAddress,
        start: u64,
        total_airdrop: u256,
        total_airdrop_amount: u256,
        vesting_time: Array<u64>,
        vesting_percent: Array<u256>,
    ) {
        self.verifier.write(verifier);
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

            let caller = get_caller_address(); 
        
            let hash = AirdropStruct { spender: contract_address_to_felt252(caller), amount: self._get_allocation() }
                        .get_message_hash();
            // assert(
            //     ValidateSignature::is_valid_signature(
            //         self.verifier.read(), hash, signature
            //     ) == 'VALID','InvalidSignature'
            // );

            let total_round = self.total_vesting.read();
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
    }

    #[generate_trait]
    impl StorageImpl of StorageTrait {
        fn _get_allocation(self: @ContractState) -> u256 {
            return self.total_airdrop_amount.read() / self.total_airdrop.read();
        }
    }

    const STARKNET_DOMAIN_TYPE_HASH: felt252 =
    selector!("StarkNetDomain(name:felt,version:felt,chainId:felt)");

    const STRUCT_WITH_U256_TYPE_HASH: felt252 =
        selector!("AirdropStruct(spender:felt,amount:u256)u256(low:felt,high:felt)");

    const U256_TYPE_HASH: felt252 = selector!("u256(low:felt,high:felt)");

    #[derive(Drop, Copy, Hash)]
    struct AirdropStruct {
        spender: felt252,
        amount: u256,
    }

    #[derive(Drop, Copy, Hash)]
    struct StarknetDomain {
        name: felt252,
        version: felt252,
        chain_id: felt252,
    }

    trait IStructHash<T> {
        fn hash_struct(self: @T) -> felt252;
    }

    trait IValidateSignature<T> {
        fn is_valid_signature(
            signer: ContractAddress, hash: felt252, signature: Array<felt252>
        ) -> felt252;
        fn get_message_hash(self: @T) -> felt252;
    }

    impl ValidateSignature of IValidateSignature<AirdropStruct> {
        fn is_valid_signature(
            signer: ContractAddress, hash: felt252, signature: Array<felt252>
        ) -> felt252 {
            let account: IAccountABIDispatcher = IAccountABIDispatcher { contract_address: signer };
            account.is_valid_signature(hash, signature)
        }

        fn get_message_hash(self: @AirdropStruct) -> felt252 {
            let domain = StarknetDomain {
                name: 'StarkFinance', version: 1, chain_id: get_tx_info().unbox().chain_id
            };
            let mut state = PedersenTrait::new(0);
            state = state.update_with('StarkNet Message');
            state = state.update_with(domain.hash_struct());
            // This can be a field within the struct, it doesn't have to be get_caller_address().
            state = state.update_with(get_caller_address());
            state = state.update_with(self.hash_struct());
            // Hashing with the amount of elements being hashed 
            state = state.update_with(4);
            state.finalize()
        }
    }

    impl StructHashStarknetDomain of IStructHash<StarknetDomain> {
        fn hash_struct(self: @StarknetDomain) -> felt252 {
            let mut state = PedersenTrait::new(0);
            state = state.update_with(STARKNET_DOMAIN_TYPE_HASH);
            state = state.update_with(*self);
            state = state.update_with(4);
            state.finalize()
        }
    }

    impl StructHashAirdropStruct of IStructHash<AirdropStruct> {
        fn hash_struct(self: @AirdropStruct) -> felt252 {
            let mut state = PedersenTrait::new(0);
            state = state.update_with(STRUCT_WITH_U256_TYPE_HASH);
            state = state.update_with(*self.spender);
            state = state.update_with(self.amount.hash_struct());
            state = state.update_with(3);
            state.finalize()
        }
    }

    impl StructHashU256 of IStructHash<u256> {
        fn hash_struct(self: @u256) -> felt252 {
            let mut state = PedersenTrait::new(0);
            state = state.update_with(U256_TYPE_HASH);
            state = state.update_with(*self);
            state = state.update_with(3);
            state.finalize()
        }
    }    
}
