#!/usr/bin/env node

import { runPrivateStateCli } from "./commands/index.mjs";

await runPrivateStateCli(process.argv.slice(2));
