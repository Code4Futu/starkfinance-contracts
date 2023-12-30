use starknet::ContractAddress;

#[starknet::interface]
trait IERC721<TContractState> {
    fn mint(
        ref self: TContractState, to: ContractAddress, token_id: u256
    );
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn tokenUri(self: @TContractState, token_id: u256) -> felt252;
    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256;
    fn isApprovedForAll(
        self: @TContractState, owner: ContractAddress, operator: ContractAddress
    ) -> bool;

    fn ownerOf(self: @TContractState, token_id: u256) -> ContractAddress;
    fn getApproved(self: @TContractState, token_id: u256) -> ContractAddress;

    fn set_approval_for_all(
        ref self: TContractState, operator: ContractAddress, approved: bool
    );
    fn approve(ref self: TContractState, to: ContractAddress, token_id: u256);
    fn transferFrom(
        ref self: TContractState, from: ContractAddress, to: ContractAddress, token_id: u256
    );
}