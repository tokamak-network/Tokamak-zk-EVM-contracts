// SPDX-License-Identifier: LGPLv3
pragma solidity ^0.8.29;

/// @title FROST(secp256k1, SHA-256) On-chain Verifier (ecrecover trick)
/// @notice Verifies Schnorr signatures produced by FROST (Zcash Foundation style).
/// @dev Uses the ecrecover-based mul–mul–add trick:
///      checks that address(-z*G + e*P) == address(-R), with
///      e = H2( Serialize(R) || Serialize(P) || msg ),
///      H2 = hash_to_field via ExpandMessageXMD(SHA-256) as per RFC 9591 §6.5.
contract ZecFrost {
    // secp256k1 base field prime and scalar field order
    uint256 private constant _P = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f;
    uint256 private constant _N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141;

    // ------------------------------- internal utils -------------------------------

    // address(-z*G + e*P) using ecrecover trick (ethresear.ch/2384)
    function _ecmulmuladd(uint256 z, uint256 x, uint256 y, uint256 e) private view returns (address result) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            // v = 27 + (y mod 2)
            mstore(ptr, mulmod(z, x, _N)) // r = z*x  (mod n)
            mstore(add(ptr, 0x20), add(and(y, 1), 27)) // v
            mstore(add(ptr, 0x40), x) // s = x
            mstore(add(ptr, 0x60), mulmod(e, x, _N)) // hash = e*x (mod n)
            result := mul(mload(0x00), staticcall(gas(), 0x01, ptr, 0x80, 0x00, 0x20))
        }
    }

    // Ethereum address of a point (truncated keccak of (x||y))
    function _address(uint256 x, uint256 y) private pure returns (address result) {
        assembly ("memory-safe") {
            mstore(0x00, x)
            mstore(0x20, y)
            result := and(keccak256(0x00, 0x40), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }

    // y^2 == x^3 + 7  (and coordinates in range)
    function _isOnCurve(uint256 x, uint256 y) private pure returns (bool result) {
        assembly ("memory-safe") {
            result :=
                and(eq(mulmod(y, y, _P), addmod(mulmod(x, mulmod(x, x, _P), _P), 7, _P)), and(lt(x, _P), lt(y, _P)))
        }
    }

    // 0 < a < n
    function _isScalar(uint256 a) private pure returns (bool result) {
        assembly ("memory-safe") {
            result := and(gt(a, 0), lt(a, _N))
        }
    }

    // ------------------------------- RFC 9591 H2 preimage -------------------------------

    /// @dev SEC1-compressed R || SEC1-compressed P || msg (msg is bytes32 here)
    function _preimage(uint256 rx, uint256 ry, uint256 px, uint256 py, bytes32 message)
        private
        pure
        returns (bytes memory preimage)
    {
        // 33 + 33 + 32 = 98 bytes
        preimage = new bytes(98);
        assembly ("memory-safe") {
            // SEC1(R)
            mstore8(add(preimage, 0x20), add(2, and(ry, 1))) // 0x02 if even(ry), 0x03 if odd
            mstore(add(preimage, 0x21), rx) // x
            // SEC1(P)
            mstore8(add(preimage, 0x41), add(2, and(py, 1)))
            mstore(add(preimage, 0x42), px)
            // msg (bytes32)
            mstore(add(preimage, 0x62), message)
        }
    }

    // ------------------------------- ExpandMessageXMD & hash_to_field -------------------------------

    /// @dev ExpandMessageXMD(SHA-256) producing `len` bytes (RFC 9380 §5.4.1)
    function _expandMessageXmd(bytes memory message, string memory dst, uint256 len)
        private
        view
        returns (bytes memory uniform)
    {
        // This is your safe, gas-optimized XMD from the working version
        assembly ("memory-safe") {
            uniform := mload(0x40)
            mstore(0x40, add(uniform, and(add(0x3f, len), 0xffe0)))
            mstore(uniform, len)

            let prime := mload(0x40)
            let ptr := prime

            // Z_pad = 64 zero bytes (SHA-256 block size)
            mstore(ptr, 0)
            ptr := add(ptr, 0x20)
            mstore(ptr, 0)
            ptr := add(ptr, 0x20)

            // msg || I2OSP(len, 2) || I2OSP(0,1) || DST' (where DST' = DST || I2OSP(len(DST),1))
            mcopy(ptr, add(message, 0x20), mload(message))
            ptr := add(ptr, mload(message))
            mstore(ptr, shl(240, len))
            ptr := add(ptr, 3)

            let bPtr := sub(ptr, 0x21)
            let iPtr := sub(ptr, 0x01)

            mcopy(ptr, add(dst, 0x20), mload(dst))
            ptr := add(ptr, mload(dst))
            mstore8(ptr, mload(dst))
            ptr := add(ptr, 0x01)

            let bLen := sub(ptr, bPtr)

            // b0 = H( Z_pad || msg || l_i_b_str || I2OSP(0,1) || DST' )
            if iszero(staticcall(gas(), 0x2, prime, sub(ptr, prime), bPtr, 0x20)) { revert(0x00, 0x00) }
            let b0 := mload(bPtr)

            // b1 = H( b0 || I2OSP(1,1) || DST' )
            mstore8(iPtr, 1)
            if iszero(staticcall(gas(), 0x2, bPtr, bLen, add(uniform, 0x20), 0x20)) { revert(0x00, 0x00) }

            // fill remaining blocks: bi = H( (b_{i-1} xor b0) || I2OSP(i,1) || DST' )
            for { let i := 2 } gt(len, 0x20) {
                i := add(i, 1)
                len := sub(len, 32)
            } {
                let uPtr := add(uniform, shl(5, i))
                mstore(bPtr, xor(b0, mload(sub(uPtr, 0x20))))
                mstore8(iPtr, i)
                if iszero(staticcall(gas(), 0x2, bPtr, bLen, uPtr, 0x20)) { revert(0x00, 0x00) }
            }
        }
    }

    /// @dev hash_to_field into secp256k1 scalar field (order n), L=48 (RFC 9591 §6.5)
    function _hashToField(bytes memory msgBytes, string memory dst) private view returns (uint256 e) {
        bytes memory okm = _expandMessageXmd(msgBytes, dst, 48);
        // take 48 bytes, big-endian, mod n
        assembly ("memory-safe") {
            e := mulmod(mload(add(okm, 0x20)), 0x100000000000000000000000000000000, _N)
            e := addmod(e, shr(128, mload(add(okm, 0x40))), _N)
        }
    }

    /// @dev H2 for FROST(secp256k1, SHA-256): DST = "FROST-secp256k1-SHA256-v1chal"
    function _challenge(uint256 rx, uint256 ry, uint256 px, uint256 py, bytes32 message)
        private
        view
        returns (uint256 e)
    {
        return _hashToField(_preimage(rx, ry, px, py, message), "FROST-secp256k1-SHA256-v1chal");
    }

    // ------------------------------- Public API -------------------------------

    /// @notice Verify a FROST(secp256k1, SHA-256) Schnorr signature (bytes32 message).
    /// @dev This verifier reduces the public key's x-coordinate modulo n when using the
    /// ecrecover trick. The only unusable edge case is when x ≡ 0 (mod n), because then
    /// s = 0 and the precompile rejects the signature. So we require:
    ///   • P is on secp256k1 and coordinates are < p, and
    ///   • x mod n != 0.
    /// Also note: in Schnorr, the scalar `z` is part of the signature and cannot be
    /// recovered from (R, P, msg); it must be supplied.
    /// @param message 32-byte message (if you have arbitrary bytes, use verifyBytes).
    /// @param px,py   Public key affine coordinates.
    /// @param rx,ry   Signature R point affine coordinates.
    /// @param z       Schnorr signature scalar.
    /// @return signer The address corresponding to P if valid; address(0) otherwise.
    function verify(bytes32 message, uint256 px, uint256 py, uint256 rx, uint256 ry, uint256 z)
        public
        view
        returns (address signer)
    {
        // Basic validation: P on-curve with x<n; R on-curve; z in (0,n)
        {
            bool pOk = isValidPublicKey(px, py);
            bool rOk = _isOnCurve(rx, ry);
            bool zOk = _isScalar(z);
            bool ok;
            assembly ("memory-safe") {
                ok := and(pOk, and(rOk, zOk))
            }
            if (!ok) return address(0);
        }

        uint256 e = _challenge(rx, ry, px, py, message);

        unchecked {
            // Compare address(-z*G + e*P) with address(-R)
            address minusR = _address(rx, _P - ry);
            address combo = _ecmulmuladd(z, px, py, e);
            signer = _address(px, py);
            assembly ("memory-safe") {
                signer := mul(signer, eq(minusR, combo))
            }
        }
    }

    /// @notice Verify with an arbitrary-length message; we pre-hash to bytes32 via keccak256.
    /// @dev Ensure your signer also used `keccak256(message)` as the `msg` when producing (R, z).
    function verifyBytes(bytes calldata message, uint256 px, uint256 py, uint256 rx, uint256 ry, uint256 z)
        public
        view
        returns (address signer)
    {
        return verify(keccak256(message), px, py, rx, ry, z);
    }

    /// @notice Check P is usable with this verifier (on-curve, coordinates < p, and x mod n != 0).
    function isValidPublicKey(uint256 x, uint256 y) public pure returns (bool result) {
        assembly ("memory-safe") {
            // On-curve check, coordinates within field, and x mod n != 0 (so ecrecover's s != 0)
            // let oncurve := eq(mulmod(y, y, _P), addmod(mulmod(x, mulmod(x, x, _P), _P), 7, _P))
            // let infield := and(lt(x, _P), lt(y, _P))
            // let xmodn := mod(x, _N)
            result :=
                and(
                    eq(mulmod(y, y, _P), addmod(mulmod(x, mulmod(x, x, _P), _P), 7, _P)),
                    and(and(lt(x, _P), lt(y, _P)), gt(mod(x, _N), 0))
                )
        }
    }

    /// @notice Gas sampling helper (unchanged).
    function measureVerify(bytes32 message, uint256 px, uint256 py, uint256 rx, uint256 ry, uint256 z)
        external
        view
        returns (uint256 cold, uint256 warm)
    {
        uint256 g0 = gasleft();
        verify(message, px, py, rx, ry, z);
        uint256 g1 = gasleft();
        verify(message, px, py, rx, ry, z);
        uint256 g2 = gasleft();
        unchecked {
            cold = g0 - g1;
            warm = g1 - g2;
        }
    }
}
