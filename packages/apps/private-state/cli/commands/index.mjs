import {
  assertHelpCommandsArgs,
  assertVersionArgs,
  cliOutput,
  configureOutput,
  parseArgs,
  printHelp,
  printVersion,
} from "../lib/runtime.mjs";
import { accountCommands } from "./account.mjs";
import { channelCommands } from "./channel.mjs";
import { investigatorCommands } from "./investigator.mjs";
import { notesCommands } from "./notes.mjs";
import { systemCommands } from "./system.mjs";
import { walletCommands } from "./wallet.mjs";

const COMMANDS = Object.freeze({
  ...systemCommands,
  ...investigatorCommands,
  ...accountCommands,
  ...channelCommands,
  ...walletCommands,
  ...notesCommands,
});

export async function runPrivateStateCli(argv) {
  let args = {};
  try {
    args = parseArgs(argv);
    configureOutput(args);

    if (args.version !== undefined) {
      assertVersionArgs(args);
      printVersion();
      return;
    }

    if (args.help || !args.command) {
      printHelp();
      return;
    }

    if (args.command === "help-commands") {
      assertHelpCommandsArgs(args);
      printHelp();
      return;
    }

    const command = COMMANDS[args.command];
    if (!command) {
      throw new Error(`Unsupported command: ${args.command}`);
    }
    await command(args);
  } catch (error) {
    cliOutput.error(error, args);
    process.exitCode = 1;
  }
}
