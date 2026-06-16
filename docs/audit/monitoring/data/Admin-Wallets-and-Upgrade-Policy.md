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
| bridgeCore | [0x992E2Ae206620d811832a8F697c526c4f95974b6](https://etherscan.io/address/0x992E2Ae206620d811832a8F697c526c4f95974b6) | [0xB1815dF9382449F48E2c26cAd75a07a51E3d72Fa](https://etherscan.io/address/0xB1815dF9382449F48E2c26cAd75a07a51E3d72Fa) |  | empty-admin-slot |
| dAppManager | [0x88Ab290a9dc0a169240EBC282Ec1F7C8524645aA](https://etherscan.io/address/0x88Ab290a9dc0a169240EBC282Ec1F7C8524645aA) | [0xB04F5137707aC1747aA3a92110B8cd084Db8f7F0](https://etherscan.io/address/0xB04F5137707aC1747aA3a92110B8cd084Db8f7F0) |  | empty-admin-slot |
| l1TokenVault | [0xf127Aef661c815ad46c5159146078f6F1E9f5F61](https://etherscan.io/address/0xf127Aef661c815ad46c5159146078f6F1E9f5F61) | [0xfF78b4395E4e37E4d107c4CCC98380A51bD0FebF](https://etherscan.io/address/0xfF78b4395E4e37E4d107c4CCC98380A51bD0FebF) |  | empty-admin-slot |

## Notes

- Current root bridge proxies use the UUPS proxy pattern.
- An empty EIP-1967 admin slot is expected for the current UUPS deployment.
- Existing channel policy snapshots are not rewritten by later DApp metadata or bridge verifier default changes.
