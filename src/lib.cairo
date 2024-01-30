mod interfaces {
    mod token {
        mod erc20;
        mod erc721;
    }
    mod account;
    mod launchpad {
        mod launchpad;
        mod airdrop;
        mod locking;
    }
}

mod launchpad {
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
}


#[cfg(test)]
mod tests {
    mod launchpad {
        // mod launchpad;
        // mod airdrop;
        mod locking;
    }
}