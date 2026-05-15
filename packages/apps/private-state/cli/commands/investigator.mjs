import {
  assertInvestigatorArgs,
  handleInvestigator,
} from "../lib/runtime.mjs";

export const investigatorCommands = Object.freeze({
  investigator: async (args) => {
    assertInvestigatorArgs(args);
    handleInvestigator();
  },
});
