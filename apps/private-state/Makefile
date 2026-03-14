.PHONY: help anvil-start anvil-bootstrap anvil-stop test deploy-sepolia deploy-sepolia-verify deploy-mainnet deploy-mainnet-verify cli-list

APP_ENV_FILE ?= $(abspath ../.env)
DEPLOY_ENV_MKDIR := /tmp

help:
	@printf '%s\n' \
		'private-state commands:' \
		'  make anvil-start             Start the local anvil node' \
		'  make anvil-bootstrap         Deploy mock TON and private-state to anvil' \
		'  make anvil-stop              Stop the local anvil node' \
		'  make test                    Run the private-state Foundry test suite' \
		'  make deploy-sepolia          Deploy to Sepolia using apps/.env values' \
		'  make deploy-sepolia-verify   Deploy to Sepolia and verify on Etherscan' \
		'  make deploy-mainnet          Deploy to Ethereum mainnet using apps/.env values' \
		'  make deploy-mainnet-verify   Deploy to Ethereum mainnet and verify on Etherscan' \
		'  make cli-list                List available CLI function templates'

anvil-start:
	@APPS_ENV_FILE="$(APP_ENV_FILE)" bash script/anvil/start-anvil.sh

anvil-bootstrap:
	@APPS_ENV_FILE="$(APP_ENV_FILE)" bash script/anvil/bootstrap-private-state-anvil.sh

anvil-stop:
	@bash script/anvil/stop-anvil.sh

test:
	@cd ../.. && forge test --offline --match-contract PrivateStateControllerTest

deploy-sepolia:
	@tmp_env="$$(mktemp $(DEPLOY_ENV_MKDIR)/private-state.env.XXXXXX)"; \
	trap 'rm -f "$$tmp_env" "$$tmp_env.next"' EXIT; \
	cp "$(APP_ENV_FILE)" "$$tmp_env"; \
	awk 'BEGIN { replaced = 0 } /^APPS_NETWORK=/ { print "APPS_NETWORK=sepolia"; replaced = 1; next } { print } END { if (replaced == 0) print "APPS_NETWORK=sepolia" }' "$$tmp_env" > "$$tmp_env.next"; \
	mv "$$tmp_env.next" "$$tmp_env"; \
	APPS_ENV_FILE="$$tmp_env" bash script/deploy/deploy-private-state.sh

deploy-sepolia-verify:
	@tmp_env="$$(mktemp $(DEPLOY_ENV_MKDIR)/private-state.env.XXXXXX)"; \
	trap 'rm -f "$$tmp_env" "$$tmp_env.next"' EXIT; \
	cp "$(APP_ENV_FILE)" "$$tmp_env"; \
	awk 'BEGIN { replaced = 0 } /^APPS_NETWORK=/ { print "APPS_NETWORK=sepolia"; replaced = 1; next } { print } END { if (replaced == 0) print "APPS_NETWORK=sepolia" }' "$$tmp_env" > "$$tmp_env.next"; \
	mv "$$tmp_env.next" "$$tmp_env"; \
	APPS_ENV_FILE="$$tmp_env" bash script/deploy/deploy-private-state.sh --verify

deploy-mainnet:
	@tmp_env="$$(mktemp $(DEPLOY_ENV_MKDIR)/private-state.env.XXXXXX)"; \
	trap 'rm -f "$$tmp_env" "$$tmp_env.next"' EXIT; \
	cp "$(APP_ENV_FILE)" "$$tmp_env"; \
	awk 'BEGIN { replaced = 0 } /^APPS_NETWORK=/ { print "APPS_NETWORK=mainnet"; replaced = 1; next } { print } END { if (replaced == 0) print "APPS_NETWORK=mainnet" }' "$$tmp_env" > "$$tmp_env.next"; \
	mv "$$tmp_env.next" "$$tmp_env"; \
	APPS_ENV_FILE="$$tmp_env" bash script/deploy/deploy-private-state.sh

deploy-mainnet-verify:
	@tmp_env="$$(mktemp $(DEPLOY_ENV_MKDIR)/private-state.env.XXXXXX)"; \
	trap 'rm -f "$$tmp_env" "$$tmp_env.next"' EXIT; \
	cp "$(APP_ENV_FILE)" "$$tmp_env"; \
	awk 'BEGIN { replaced = 0 } /^APPS_NETWORK=/ { print "APPS_NETWORK=mainnet"; replaced = 1; next } { print } END { if (replaced == 0) print "APPS_NETWORK=mainnet" }' "$$tmp_env" > "$$tmp_env.next"; \
	mv "$$tmp_env.next" "$$tmp_env"; \
	APPS_ENV_FILE="$$tmp_env" bash script/deploy/deploy-private-state.sh --verify

cli-list:
	@node cli/private-state-cli.mjs list
