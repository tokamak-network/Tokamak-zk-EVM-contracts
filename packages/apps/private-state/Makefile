.PHONY: help anvil-start anvil-bootstrap anvil-stop test deploy-sepolia deploy-sepolia-verify deploy-mainnet deploy-mainnet-verify cli-bridge-help e2e-bridge-cli

APP_ENV_FILE ?= $(abspath ../.env)
DEPLOY_ENV_MKDIR := /tmp

define DEPLOY_RULE
	@APPS_ENV_FILE="$(APP_ENV_FILE)" node scripts/deploy/deploy-private-state.mjs --network $(1) $(2)
endef

help:
	@printf '%s\n' \
		'private-state commands:' \
		'  make anvil-start             Start the local anvil node' \
		'  make anvil-bootstrap         Deploy mock TON and private-state to anvil' \
		'  make anvil-stop              Stop the local anvil node' \
		'  make test                    Run the private-state Foundry test suite' \
		'  make e2e-bridge-cli          Run the CLI-driven bridge/private-state end-to-end flow' \
		'  make deploy-sepolia          Deploy to Sepolia using packages/apps/.env values' \
		'  make deploy-sepolia-verify   Deploy to Sepolia and verify on Etherscan' \
		'  make deploy-mainnet          Deploy to Ethereum mainnet using packages/apps/.env values' \
		'  make deploy-mainnet-verify   Deploy to Ethereum mainnet and verify on Etherscan' \
		'  make cli-bridge-help         Show the bridge-coupled private-state CLI help'

anvil-start:
	@APPS_ENV_FILE="$(APP_ENV_FILE)" node scripts/anvil/start-anvil.mjs

anvil-bootstrap:
	@APPS_ENV_FILE="$(APP_ENV_FILE)" node scripts/anvil/bootstrap-private-state-anvil.mjs

anvil-stop:
	@node scripts/anvil/stop-anvil.mjs

test:
	@cd ../.. && forge test --offline --match-contract PrivateStateControllerTest

e2e-bridge-cli:
	@node scripts/e2e/run-bridge-private-state-cli-e2e.mjs

deploy-sepolia:
	$(call DEPLOY_RULE,sepolia,)

deploy-sepolia-verify:
	$(call DEPLOY_RULE,sepolia,--verify)

deploy-mainnet:
	$(call DEPLOY_RULE,mainnet,)

deploy-mainnet-verify:
	$(call DEPLOY_RULE,mainnet,--verify)

cli-bridge-help:
	@node cli/private-state-bridge-cli.mjs --help
