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

## Multisig And Timelock

The root bridge proxy owner is the Safe multisig
[0xBE637160D21975EF1e0270D32Bfc547c2EA8DcC3](https://etherscan.io/address/0xBE637160D21975EF1e0270D32Bfc547c2EA8DcC3)
with a 2-of-3 threshold and no timelock.

Ownership was transferred from the deployment EOA
[0x850dD0721B93D455b55bdf1324595fA1BD2B3ce7](https://etherscan.io/address/0x850dD0721B93D455b55bdf1324595fA1BD2B3ce7)
through the following transactions:

| Contract | Ownership transfer transaction |
| --- | --- |
| bridgeCore | [0xbf02088103cc8082136d3832daa46ac668ad1beee27e353ef8a8102f39690691](https://etherscan.io/tx/0xbf02088103cc8082136d3832daa46ac668ad1beee27e353ef8a8102f39690691) |
| dAppManager | [0x921c168547b2fc284bf9aa9bf981cf79c1dca4e1ac0cfdb4cc40144e6631aef3](https://etherscan.io/tx/0x921c168547b2fc284bf9aa9bf981cf79c1dca4e1ac0cfdb4cc40144e6631aef3) |
| bridgeTokenVault | [0xaabe73295adcfc3f5380c66ce46df36dd0adcd47c94fe41757c32ef81ba1044e](https://etherscan.io/tx/0xaabe73295adcfc3f5380c66ce46df36dd0adcd47c94fe41757c32ef81ba1044e) |

## Proxies

| Proxy | Address | Implementation | EIP-1967 admin slot | Admin slot status |
| --- | --- | --- | --- | --- |
| bridgeCore | [0x992E2Ae206620d811832a8F697c526c4f95974b6](https://etherscan.io/address/0x992E2Ae206620d811832a8F697c526c4f95974b6) | [0x1713171adc06BF82b4f05945d742FFd351a8d1bD](https://etherscan.io/address/0x1713171adc06BF82b4f05945d742FFd351a8d1bD) |  | empty-admin-slot |
| dAppManager | [0x88Ab290a9dc0a169240EBC282Ec1F7C8524645aA](https://etherscan.io/address/0x88Ab290a9dc0a169240EBC282Ec1F7C8524645aA) | [0x76f0e95c0E5c9bA26289062637c68aEc1199ddc5](https://etherscan.io/address/0x76f0e95c0E5c9bA26289062637c68aEc1199ddc5) |  | empty-admin-slot |
| l1TokenVault | [0xf127Aef661c815ad46c5159146078f6F1E9f5F61](https://etherscan.io/address/0xf127Aef661c815ad46c5159146078f6F1E9f5F61) | [0x4c6dDcf807309d49Ac9a1f6583B5A19ef6c6a710](https://etherscan.io/address/0x4c6dDcf807309d49Ac9a1f6583B5A19ef6c6a710) |  | empty-admin-slot |

## Notes

- Current root bridge proxies use the UUPS proxy pattern.
- An empty EIP-1967 admin slot is expected for the current UUPS deployment.
- The Safe multisig can authorize UUPS upgrades and root bridge owner-only administration actions.
- No timelock delay is currently configured.
- Existing channel policy snapshots are not rewritten by later DApp metadata or bridge verifier default changes.
