#!/usr/bin/env node

import { PRIVATE_STATE_SYNTH_COMPAT_FUNCTIONS, runPrivateStateSynthesizerCompatTest } from './common.ts';

const argv = process.argv.slice(2);

for (let index = 0; index < PRIVATE_STATE_SYNTH_COMPAT_FUNCTIONS.length; index += 1) {
  const functionName = PRIVATE_STATE_SYNTH_COMPAT_FUNCTIONS[index];
  const effectiveArgs = index === 0 ? argv : ['--skip-bootstrap', ...argv.filter((arg) => arg !== '--skip-bootstrap')];
  await runPrivateStateSynthesizerCompatTest(functionName, effectiveArgs);
}
