#!/usr/bin/env node

import { runPrivateStateCli } from "./commands/index.mjs";

runPrivateStateCli(process.argv.slice(2));
