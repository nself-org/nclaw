# ɳClaw backend — convenience commands
# All operations run through the nSelf CLI.
# Never invoke docker-compose directly.

.PHONY: setup setup-required setup-optional build start stop status logs db-console check test-env help

help:
	@printf "nClaw backend commands\n"
	@printf "\n"
	@printf "  make setup           Install all nClaw bundle plugins (run once)\n"
	@printf "  make setup-required  Install only the 3 required plugins (ai, claw, mux)\n"
	@printf "  make setup-optional  Install optional bundle plugins\n"
	@printf "  make check           Validate .env for unknown/deprecated vars (run before build)\n"
	@printf "  make test-env        Run env-vars-check unit tests\n"
	@printf "  make build           Generate docker-compose from nself.yaml + .env\n"
	@printf "  make start           Start the full backend stack\n"
	@printf "  make stop            Stop the backend stack\n"
	@printf "  make status          Show status of all services\n"
	@printf "  make logs            Tail logs from all services\n"
	@printf "  make db-console      Open interactive database console\n"
	@printf "\n"
	@printf "First-time setup:\n"
	@printf "  1. cp .env.example .env\n"
	@printf "  2. Set NSELF_PLUGIN_LICENSE_KEY in .env (Pro tier, nself.org/pricing)\n"
	@printf "  3. Set AI_OPENAI_API_KEY or AI_ANTHROPIC_API_KEY in .env\n"
	@printf "  4. nself license set nself_pro_your_key_here\n"
	@printf "  5. make check && make setup && make build && make start\n"

check:
	node scripts/env-vars-check.js

test-env:
	node --test scripts/env-vars-check.test.js

setup:
	nself plugin install ai claw mux claw-web voice browser google notify cron

setup-required:
	nself plugin install ai claw mux

setup-optional:
	nself plugin install claw-web voice browser google notify cron

build:
	nself build

start:
	nself start

stop:
	nself stop

status:
	nself status

logs:
	nself logs

db-console:
	nself db console
