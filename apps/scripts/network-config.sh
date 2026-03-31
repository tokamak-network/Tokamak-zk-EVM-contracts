#!/usr/bin/env bash

resolve_app_network() {
    case "$1" in
        sepolia)
            APPS_CHAIN_ID=11155111
            APPS_ALCHEMY_NETWORK="eth-sepolia"
            ;;
        mainnet)
            APPS_CHAIN_ID=1
            APPS_ALCHEMY_NETWORK="eth-mainnet"
            ;;
        base-sepolia)
            APPS_CHAIN_ID=84532
            APPS_ALCHEMY_NETWORK="base-sepolia"
            ;;
        base-mainnet)
            APPS_CHAIN_ID=8453
            APPS_ALCHEMY_NETWORK="base-mainnet"
            ;;
        arb-sepolia)
            APPS_CHAIN_ID=421614
            APPS_ALCHEMY_NETWORK="arb-sepolia"
            ;;
        arb-mainnet)
            APPS_CHAIN_ID=42161
            APPS_ALCHEMY_NETWORK="arb-mainnet"
            ;;
        op-mainnet)
            APPS_CHAIN_ID=10
            APPS_ALCHEMY_NETWORK="opt-mainnet"
            ;;
        op-sepolia)
            APPS_CHAIN_ID=11155420
            APPS_ALCHEMY_NETWORK="opt-sepolia"
            ;;
        anvil)
            APPS_CHAIN_ID=31337
            APPS_ALCHEMY_NETWORK=""
            ;;
        *)
            echo "Unsupported APPS_NETWORK: $1" >&2
            return 1
            ;;
    esac
}
