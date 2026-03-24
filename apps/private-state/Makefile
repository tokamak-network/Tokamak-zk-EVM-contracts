.PHONY: help anvil-start anvil-bootstrap anvil-stop test deploy-sepolia deploy-sepolia-verify deploy-mainnet deploy-mainnet-verify cli-list cli-bridge-help e2e-bridge

APP_ENV_FILE ?= $(abspath ../.env)
DEPLOY_ENV_MKDIR := /tmp

define DEPLOY_RULE
	@tmp_env="$$(mktemp $(DEPLOY_ENV_MKDIR)/private-state.env.XXXXXX)"; \
	trap 'rm -f "$$tmp_env" "$$tmp_env.next"' EXIT; \
	cp "$(APP_ENV_FILE)" "$$tmp_env"; \
	awk 'BEGIN { replaced = 0 } /^APPS_NETWORK=/ { print "APPS_NETWORK=$(1)"; replaced = 1; next } { print } END { if (replaced == 0) print "APPS_NETWORK=$(1)" }' "$$tmp_env" > "$$tmp_env.next"; \
	mv "$$tmp_env.next" "$$tmp_env"; \
	APPS_ENV_FILE="$$tmp_env" bash script/deploy/deploy-private-state.sh $(2)
endef

help:
	@printf '%s\n' \
		'private-state commands:' \
		'  make anvil-start             Start the local anvil node' \
		'  make anvil-bootstrap         Deploy mock TON and private-state to anvil' \
		'  make anvil-stop              Stop the local anvil node' \
		'  make test                    Run the private-state Foundry test suite' \
		'  make e2e-bridge              Run the genesis-based bridge/private-state end-to-end flow' \
		'  make deploy-sepolia          Deploy to Sepolia using apps/.env values' \
		'  make deploy-sepolia-verify   Deploy to Sepolia and verify on Etherscan' \
		'  make deploy-mainnet          Deploy to Ethereum mainnet using apps/.env values' \
		'  make deploy-mainnet-verify   Deploy to Ethereum mainnet and verify on Etherscan' \
		'  make cli-list                List available bridge-coupled CLI function templates' \
		'  make cli-bridge-help         Show the bridge-coupled private-state CLI help'

anvil-start:
	@APPS_ENV_FILE="$(APP_ENV_FILE)" bash script/anvil/start-anvil.sh

anvil-bootstrap:
	@APPS_ENV_FILE="$(APP_ENV_FILE)" bash script/anvil/bootstrap-private-state-anvil.sh

anvil-stop:
	@bash script/anvil/stop-anvil.sh

test:
	@cd ../.. && forge test --offline --match-contract PrivateStateControllerTest

e2e-bridge:
	@node script/e2e/run-bridge-private-state-e2e.mjs

deploy-sepolia:
	$(call DEPLOY_RULE,sepolia,)

deploy-sepolia-verify:
	$(call DEPLOY_RULE,sepolia,--verify)

deploy-mainnet:
	$(call DEPLOY_RULE,mainnet,)

deploy-mainnet-verify:
	$(call DEPLOY_RULE,mainnet,--verify)

cli-list:
	@node cli/private-state-bridge-cli.mjs list-functions

cli-bridge-help:
	@node cli/private-state-bridge-cli.mjs --help
