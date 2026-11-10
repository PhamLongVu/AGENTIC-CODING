# =============================================================================
# Cloud Coding Platform — developer entrypoints
# =============================================================================
SHELL := /bin/bash

.DEFAULT_GOAL := help

.PHONY: help up down restart logs ps bootstrap build-workspace \
        test test-unit test-integration test-security test-infra \
        terraform-validate gen-secrets dev-hosts-setup validate \
        deploy-dev destroy-dev backup restore destroy-data

help: ## show available targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# --- environment -----------------------------------------------------------

gen-secrets: ## fill CHANGE_ME placeholders in .env with random secrets
	@scripts/gen-secrets.sh

dev-hosts-setup: ## add host.docker.internal -> 127.0.0.1 to /etc/hosts (sudo)
	@scripts/dev-hosts-setup.sh

# --- platform stack (local) --------------------------------------------------

up: ## start postgres + litellm + coder (local mode; requires .env)
	@scripts/env-ensure.sh
	@docker compose up -d
	@echo ""
	@echo "stack starting. health:  make ps"
	@echo "next:                   make bootstrap"

down: ## stop the platform stack (all volumes kept)
	@docker compose down

restart: down up ## restart the stack

logs: ## follow platform logs (service optional: make logs s=coder)
	@docker compose logs -f $(s)

ps: ## service status incl. health
	@docker compose ps

bootstrap: ## admin user + workspace template + demo virtual key (idempotent)
	@scripts/bootstrap.sh

destroy-data: ## WARNING: rm platform volumes (postgres, coder home)
	@scripts/destroy-dev.sh data

# --- workspace image ----------------------------------------------------------

build-workspace: ## build the pinned workspace image (code-server + opencode)
	@docker build -t cloudcoding-workspace:dev -f workspace/images/development/Dockerfile workspace/

# --- tests ----------------------------------------------------------------------

test-unit: ## static checks (compose, env contract, pins, bash -n)
	@tests/unit/run.sh

test-integration: ## local integration suite (mock AI; stack must be up)
	@tests/integration/run.sh

test-security: ## local security suite (auth, hardening, isolation)
	@tests/security/run.sh

test-infra: ## terraform fmt+validate in a pinned container (no creds)
	@tests/infrastructure/run.sh

test: test-unit test-infra test-integration test-security ## everything local (mock mode)

validate: ## CI-shaped validation (unit + infra, no running stack needed)
	@scripts/validate.sh

terraform-validate: test-infra ## alias

# --- local lifecycle helpers ----------------------------------------------------

deploy-dev: ## full local bring-up: env -> up -> bootstrap
	@scripts/deploy-dev.sh

backup: ## dump DBs + workspace volumes to ./backups/<stamp>/
	@scripts/backup.sh

# restore: scripts/restore.sh <stamp>   (interactive confirm)

destroy-dev: ## teardown local env [stack|data|workspaces]
	@scripts/destroy-dev.sh $(L)

# --- AWS (prepare only — apply is owner-gated; see TASKS.md 3.5) ----------------

aws-plan: ## terraform plan for the POC env (needs credentials locally)
	cd infra/terraform/environments/dev && terraform init -backend=false && terraform plan -out poc.tfplan

aws-bootstrap: ## ON THE INSTANCE ONLY: docs/operations/deployment.md
	@echo "run deploy/scripts/bootstrap-host.sh ON the EC2 instance, after approval. See docs/operations/deployment.md"
	@exit 1
