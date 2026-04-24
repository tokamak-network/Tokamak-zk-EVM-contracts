#!/usr/bin/env node

import { main } from "../../../../groth16/prover/updateTree/generateProof.mjs";

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
