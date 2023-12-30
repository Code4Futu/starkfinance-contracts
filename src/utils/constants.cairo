
const DOMAIN_NAME: felt252 = 'StarkFinance';
const DOMAIN_VERSION: felt252 = '0.1.0';

// Starknet Signature Constants

const STARKNET_MESSAGE_PREFIX: felt252 = 'StarkNet Message';

const DOMAIN_TYPE_HASH: felt252 = selector!("StarkNetDomain(name:felt,version:felt,chainId:felt)");

// ERC165 Interface Ids
// For more information, refer to: https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-5.md
const ERC165_ACCOUNT_INTERFACE_ID: felt252 =
    0x2ceccef7f994940b3962a6c67e0ba4fcd37df7d131417c604f91e03caecc1cd; // SNIP-6 compliant account ID, functions are snake case