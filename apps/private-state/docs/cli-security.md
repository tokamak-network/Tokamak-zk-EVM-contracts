# CLI Security Model

## 1. Security Boundaries

The private-state CLI manages three distinct secret domains:

- the user's Ethereum private key
- the channel-bound L2 private key
- the channel-scoped note-receive private key

The wallet password protects the local wallet file that stores the recoverable wallet material.

## 2. Wallet File Encryption

The CLI stores a channel wallet as an encrypted local file under the workspace.

The wallet password is used to decrypt:

- the wallet metadata needed for normal wallet-backed commands
- the stored L1 key copy
- the stored L2 key pair
- tracked note state

This means that the wallet password is a local-storage protection secret, not a bridge-side secret.

## 3. Channel-Bound L2 Identity

The channel-bound L2 identity is derived by asking the Ethereum signer to sign a deterministic message that includes:

- a fixed domain string
- the channel name
- the wallet password

From that signature the CLI derives:

- `l2PrivateKey`
- `l2PublicKey`
- `l2Address`

Implication:

- if the wallet password is lost, the same `l2PrivateKey` can no longer be re-derived
- without the `l2PrivateKey`, notes cannot be spent, transferred, or redeemed

Under the strict ownership definition used by the CLI assistant, losing the wallet password therefore means losing note ownership.

## 4. Note-Receive Auxiliary Keys

The note-receive key pair is different from the channel-bound L2 identity.

It is derived from a fixed EIP-712 typed-data signing flow over:

- protocol label
- chain id
- channel id
- channel name
- DApp label
- Ethereum account

The resulting note-receive public key is registered on-chain during channel registration.

## 5. Why Two Key Families Exist

The two key families have different roles:

- `l2PrivateKey`
  - proves note ownership in the strong sense
  - required for spending, transfer, and redemption flows
- `noteReceivePrivateKey`
  - decrypts encrypted note-delivery payloads from emitted events
  - supports recipient-side note discovery and reconstruction

This separation allows incoming note delivery to be recovered from Ethereum logs without using the note-spending key as the delivery key.

## 6. Mint and Transfer Recovery

The current implementation uses the note-receive key path for both:

- transferred note outputs
- self-minted note outputs

This means the event decryption path is now uniform across encrypted note delivery.

## 7. Recovery Model

### If the wallet file is lost

Recovery is still possible if the user retains:

- the Ethereum private key
- the correct channel context
- the wallet password

With those, the CLI can reconstruct:

- the channel-bound L2 identity
- the note-receive key material
- a recoverable wallet view from on-chain registration and bridge-propagated event logs

### If the wallet password is lost

The user loses the ability to derive the channel-bound `l2PrivateKey`.

Consequences:

- existing note ciphertexts may still be recognized or decrypted through the note-receive path
- but the notes can no longer be used
- therefore ownership, in the strict spendable sense, is lost and cannot be recovered

### If the wallet file and wallet password are both stolen

The attacker can decrypt the wallet and recover the stored key material.

That is sufficient to endanger channel funds.

## 8. Protocol Risks

The note-receive derivation model depends on deterministic reproduction of the same typed-data signature bytes for the same account and typed-data payload.

If that property fails for a wallet implementation:

- the same note-receive private key may not be recoverable later
- encrypted note delivery recovery can fail

The exact typed-data schema and signing method must therefore remain versioned and stable.

## 9. Operational Recommendations

- protect the wallet password as a long-term ownership secret
- back up the Ethereum private key separately from the local workspace
- treat the wallet file and password together as sufficient to compromise channel funds
- do not assume that being able to read a note implies being able to use it
