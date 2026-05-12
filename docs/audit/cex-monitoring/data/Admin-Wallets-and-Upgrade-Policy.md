# Admin Wallets and Upgrade Policy

This file records the current on-chain owner and proxy-slot state for the monitored mainnet bridge
deployment. The external policy model for upgrades and per-channel immutability is described in
`docs/whitepaper.md`.

## Owners

| Contract | Owner |
| --- | --- |
| bridgeCore | [0x850dD0721B93D455b55bdf1324595fA1BD2B3ce7](https://etherscan.io/address/0x850dD0721B93D455b55bdf1324595fA1BD2B3ce7) |
| dAppManager | [0x850dD0721B93D455b55bdf1324595fA1BD2B3ce7](https://etherscan.io/address/0x850dD0721B93D455b55bdf1324595fA1BD2B3ce7) |
| bridgeTokenVault | [0x850dD0721B93D455b55bdf1324595fA1BD2B3ce7](https://etherscan.io/address/0x850dD0721B93D455b55bdf1324595fA1BD2B3ce7) |

## Proxies

| Proxy | Address | Implementation | EIP-1967 admin slot | Admin slot status |
| --- | --- | --- | --- | --- |
| bridgeCore | [0x992E2Ae206620d811832a8F697c526c4f95974b6](https://etherscan.io/address/0x992E2Ae206620d811832a8F697c526c4f95974b6) | [0x1713171adc06BF82b4f05945d742FFd351a8d1bD](https://etherscan.io/address/0x1713171adc06BF82b4f05945d742FFd351a8d1bD) |  | empty-admin-slot |
| dAppManager | [0x88Ab290a9dc0a169240EBC282Ec1F7C8524645aA](https://etherscan.io/address/0x88Ab290a9dc0a169240EBC282Ec1F7C8524645aA) | [0x76f0e95c0E5c9bA26289062637c68aEc1199ddc5](https://etherscan.io/address/0x76f0e95c0E5c9bA26289062637c68aEc1199ddc5) |  | empty-admin-slot |
| l1TokenVault | [0xf127Aef661c815ad46c5159146078f6F1E9f5F61](https://etherscan.io/address/0xf127Aef661c815ad46c5159146078f6F1E9f5F61) | [0x4c6dDcf807309d49Ac9a1f6583B5A19ef6c6a710](https://etherscan.io/address/0x4c6dDcf807309d49Ac9a1f6583B5A19ef6c6a710) |  | empty-admin-slot |

## Notes

- Current root bridge proxies use the UUPS proxy pattern.
- An empty EIP-1967 admin slot is expected for the current UUPS deployment.
- Existing channel policy snapshots are not rewritten by later DApp metadata or bridge verifier default changes.
