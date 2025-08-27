// SPDX-License-Identifier: MIT
pragma solidity >=0.8.8;

library Poseidon4Field {
    type Type is uint256;

    // BLS12-381 scalar Poseidon4Field
    uint256 constant PRIME = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant PRIME_DIV_2 = 0x39f6d3a994cea741999ce0405809a0d42a9da201ffff2dff7fffffff80000000;

    function checkField(Poseidon4Field.Type a) internal pure {
        require(Poseidon4Field.Type.unwrap(a) < PRIME, "Poseidon4Field: input is too large");
    }

    function toFieldUnchecked(uint256 a) internal pure returns (Poseidon4Field.Type b) {
        b = Poseidon4Field.Type.wrap(a);
    }

    function toField(uint256 a) internal pure returns (Poseidon4Field.Type b) {
        b = Poseidon4Field.Type.wrap(a);
        checkField(b);
    }

    function toFieldUnchecked(bytes32 a) internal pure returns (Poseidon4Field.Type b) {
        assembly {
            b := a
        }
    }

    function toField(bytes32 a) internal pure returns (Poseidon4Field.Type b) {
        assembly {
            b := a
        }
        checkField(b);
    }

    function toBytes32(Poseidon4Field.Type a) internal pure returns (bytes32 b) {
        assembly {
            b := a
        }
    }

    function toUint256(Poseidon4Field.Type a) internal pure returns (uint256 b) {
        assembly {
            b := a
        }
    }

    function toAddress(Poseidon4Field.Type a) internal pure returns (address b) {
        require(Poseidon4Field.Type.unwrap(a) < (1 << 160), "Poseidon4Field: input is too large");
        assembly {
            b := a
        }
    }

    function toArr(Poseidon4Field.Type a) internal pure returns (bytes32[] memory b) {
        b = new bytes32[](1);
        b[0] = toBytes32(a);
    }

    function toField(address a) internal pure returns (Poseidon4Field.Type b) {
        assembly {
            b := a
        }
    }

    function toField(int256 a) internal pure returns (Poseidon4Field.Type) {
        if (a < 0) {
            require(uint256(-a) < PRIME, "Poseidon4Field: input is too large");
            return Poseidon4Field.Type.wrap(PRIME - uint256(-a));
        } else {
            require(uint256(a) < PRIME, "Poseidon4Field: input is too large");
            return Poseidon4Field.Type.wrap(uint256(a));
        }
    }

    function into(Poseidon4Field.Type[] memory a) internal pure returns (bytes32[] memory b) {
        assembly {
            b := a
        }
    }

    function add(Poseidon4Field.Type a, Poseidon4Field.Type b) internal pure returns (Poseidon4Field.Type c) {
        assembly {
            c := addmod(a, b, PRIME)
        }
    }

    function mul(Poseidon4Field.Type a, Poseidon4Field.Type b) internal pure returns (Poseidon4Field.Type c) {
        assembly {
            c := mulmod(a, b, PRIME)
        }
    }

    function add(Poseidon4Field.Type a, uint256 b) internal pure returns (Poseidon4Field.Type c) {
        assembly {
            c := addmod(a, b, PRIME)
        }
    }

    function mul(Poseidon4Field.Type a, uint256 b) internal pure returns (Poseidon4Field.Type c) {
        assembly {
            c := mulmod(a, b, PRIME)
        }
    }

    function mulNoModulo(Poseidon4Field.Type a, Poseidon4Field.Type b) internal pure returns (Poseidon4Field.Type c) {
        // Multiply WITHOUT modulo to match TypeScript bug
        // WARNING: This can overflow and should only be used for compatibility
        assembly {
            c := mul(a, b)
        }
    }

    function mulNoModulo(Poseidon4Field.Type a, uint256 b) internal pure returns (Poseidon4Field.Type c) {
        // Multiply WITHOUT modulo to match TypeScript bug
        // WARNING: This can overflow and should only be used for compatibility
        assembly {
            c := mul(a, b)
        }
    }

    function pow(Poseidon4Field.Type a, uint256 exponential) internal pure returns (Poseidon4Field.Type c) {
        // Compute a^exponential mod PRIME
        assembly {
            c := 1
            let base := a
            let exponent := exponential

            for {} gt(exponent, 0) {} {
                if and(exponent, 1) { c := mulmod(c, base, PRIME) }
                base := mulmod(base, base, PRIME)
                exponent := shr(1, exponent)
            }
        }
    }

    function powNoModulo(Poseidon4Field.Type a, uint256 exponential) internal pure returns (Poseidon4Field.Type c) {
        // Compute a^exponential WITHOUT modulo to match TypeScript bug
        // WARNING: This can overflow and should only be used for compatibility
        assembly {
            c := 1
            let base := a
            let exponent := exponential

            for {} gt(exponent, 0) {} {
                if and(exponent, 1) { c := mul(c, base) }
                base := mul(base, base)
                exponent := shr(1, exponent)
            }
        }
    }

    function eq(Poseidon4Field.Type a, Poseidon4Field.Type b) internal pure returns (bool c) {
        assembly {
            c := eq(a, b)
        }
    }

    function isZero(Poseidon4Field.Type a) internal pure returns (bool c) {
        assembly {
            c := eq(a, 0)
        }
    }

    function signed(Poseidon4Field.Type a) internal pure returns (bool positive, uint256 scalar) {
        uint256 raw = Poseidon4Field.Type.unwrap(a);
        if (raw > PRIME_DIV_2) {
            return (false, PRIME - raw);
        } else {
            return (true, raw);
        }
    }
}
