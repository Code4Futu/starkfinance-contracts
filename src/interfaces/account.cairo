#[starknet::interface]
trait IAccountABI<TContractState> {
    fn is_valid_signature(
            self: @TContractState, hash: felt252, signature: Array<felt252>
        ) -> felt252;
    fn isValidSignature(
            self: @TContractState, hash: felt252, signature: Array<felt252>
        ) -> felt252;
}

