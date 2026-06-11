# Admin Wallets and Upgrade Policy

This file records the current on-chain owner and proxy-slot state for the monitored mainnet bridge
deployment. The external policy model for upgrades and per-channel immutability is described in
`docs/whitepaper.md`.

## Owners

| Contract | Owner |
| --- | --- |
| bridgeCore | [0xBE637160D21975EF1e0270D32Bfc547c2EA8DcC3](https://etherscan.io/address/0xBE637160D21975EF1e0270D32Bfc547c2EA8DcC3) |
| dAppManager | [0xBE637160D21975EF1e0270D32Bfc547c2EA8DcC3](https://etherscan.io/address/0xBE637160D21975EF1e0270D32Bfc547c2EA8DcC3) |
| bridgeTokenVault | [0xBE637160D21975EF1e0270D32Bfc547c2EA8DcC3](https://etherscan.io/address/0xBE637160D21975EF1e0270D32Bfc547c2EA8DcC3) |

## Proxies

| Proxy | Address | Implementation | EIP-1967 admin slot | Admin slot status |
| --- | --- | --- | --- | --- |
| bridgeCore | [0x992E2Ae206620d811832a8F697c526c4f95974b6](https://etherscan.io/address/0x992E2Ae206620d811832a8F697c526c4f95974b6) | [0xCd96A6205207470E293E0dd770EA74d736b7F5bf](https://etherscan.io/address/0xCd96A6205207470E293E0dd770EA74d736b7F5bf) |  | empty-admin-slot |
| dAppManager | [0x88Ab290a9dc0a169240EBC282Ec1F7C8524645aA](https://etherscan.io/address/0x88Ab290a9dc0a169240EBC282Ec1F7C8524645aA) | [0xd1894e950EaA7bc4D1b164F3dD164965Db136860](https://etherscan.io/address/0xd1894e950EaA7bc4D1b164F3dD164965Db136860) |  | empty-admin-slot |
| l1TokenVault | [0xf127Aef661c815ad46c5159146078f6F1E9f5F61](https://etherscan.io/address/0xf127Aef661c815ad46c5159146078f6F1E9f5F61) | [0x66bF7E0dC10129b5108719f2744DF58B8BC54647](https://etherscan.io/address/0x66bF7E0dC10129b5108719f2744DF58B8BC54647) |  | empty-admin-slot |

## Notes

- Current root bridge proxies use the UUPS proxy pattern.
- An empty EIP-1967 admin slot is expected for the current UUPS deployment.
- Existing channel policy snapshots are not rewritten by later DApp metadata or bridge verifier default changes.
