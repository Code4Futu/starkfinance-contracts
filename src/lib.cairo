mod interfaces {
    mod erc20;
    mod erc721;
    mod account;
}
mod launchpad {
    mod structs;
    mod launchpad;
    mod airdrop;
    mod locking;
}
mod utils {
    mod constants;
    mod call_fallback;
}

mod mocks {
    mod erc20;
    mod erc721;
    mod signer;
}


#[cfg(test)]
mod tests {
    mod launchpad {
        // mod launchpad;
        // mod airdrop;
        mod locking;
    }
}