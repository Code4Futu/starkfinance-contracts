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
    use pedersen::PedersenTrait;
    use hash::{HashStateTrait, HashStateExTrait};
    use box::BoxTrait;

    use starkfinance::interfaces::token::erc20::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait};
    use starkfinance::utils::constants::{
        STARKNET_MESSAGE_PREFIX,
        DOMAIN_NAME,
        DOMAIN_VERSION, 
        DOMAIN_TYPE_HASH, 
        ERC165_ACCOUNT_INTERFACE_ID
    };
    use starkfinance::interfaces::launchpad::airdrop::{ISFAirdrop, AirdropStats, AirdropStruct, SimpleStruct};

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

        
            // assert(
            //     signature.at(0).clone() == SIGNATURE_R 
            //     && signature.at(1).clone() == SIGNATURE_S,
            //     'InvalidSignature'
            // );

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

        fn compute_message_hash(self: @ContractState, simple: SimpleStruct) -> felt252 {
            simple.some_felt252.print();
            simple.some_u128.print();
            simple.get_message_hash().print();
            simple.get_message_hash()
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

    const SIMPLE_STRUCT_TYPE_HASH: felt252 =
        selector!("SimpleStruct(some_felt252:felt,some_u128:u128)");

    #[derive(Drop, Copy, Hash)]
    struct StarknetDomain {
        name: felt252,
        version: felt252,
        chain_id: felt252,
    }

    trait IStructHash<T> {
        fn hash_struct(self: @T) -> felt252;
    }

    trait IOffchainMessageHash<T> {
        fn get_message_hash(self: @T) -> felt252;
    }

    impl OffchainMessageHashSimpleStruct of IOffchainMessageHash<SimpleStruct> {
        fn get_message_hash(self: @SimpleStruct) -> felt252 {
            let domain = StarknetDomain {
                name: 'dappName', version: 1, chain_id: get_tx_info().unbox().chain_id
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

    impl StructHashSimpleStruct of IStructHash<SimpleStruct> {
        fn hash_struct(self: @SimpleStruct) -> felt252 {
            let mut state = PedersenTrait::new(0);
            state = state.update_with(SIMPLE_STRUCT_TYPE_HASH);
            state = state.update_with(*self);
            state = state.update_with(3);
            state.finalize()
        }
    }

}

// use box::BoxTrait;
// use starknet::{
//     contract_address_const, get_tx_info, get_caller_address, testing::set_caller_address
// };
// use pedersen::PedersenTrait;
// use hash::{HashStateTrait, HashStateExTrait};

// use starkfinance::interfaces::launchpad::airdrop::{SimpleStruct};

// #[test]
// #[available_gas(2000000)]
// fn test_valid_hash() {
//     // This value was computed using StarknetJS
//     let message_hash = 0x1e739b39f83b38f182edaed69f730f18eff802d3ef44be91c3733cdcab6de2f;
//     let simple_struct = SimpleStruct { some_felt252: 712, some_u128: 42 };
//     set_caller_address(contract_address_const::<420>());
//     assert(simple_struct.get_message_hash() == message_hash, 'Hash should be valid');
// }
