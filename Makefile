# ===========================
# adage-fabric / Makefile (root)
# ===========================
# Purpose: orchestrate containers and call into sql/Makefile as needed.

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

# ---------- Paths ----------
SQL_DIR := sql

# docker compose wrapper
DC := docker compose

# ===========================
# Container lifecycle
# ===========================
.PHONY: up down restart ps logs clean

up:
	$(DC) up -d
	@echo "✓ Stack up"

down:
	$(DC) down
	@echo "✓ Stack down"

restart: down up

ps:
	$(DC) ps

logs:
	$(DC) logs -f

clean:
	$(DC) down -v
	@git clean -fdx -e ".env" -e ".vscode" || true
	@echo "✓ Cleaned containers and untracked files"

# ===========================
# Schema orchestration
# ===========================
.PHONY: sql.bootstrap sql.lane sql.lanes bootstrap

# Call the SQL-only bootstrap (no docker compose inside)
sql.bootstrap:
	@$(MAKE) -C $(SQL_DIR) bootstrap

# Optional helpers that pass through to sql/Makefile
sql.lane:
	@$(MAKE) -C $(SQL_DIR) lane ORG=$(ORG) DOMAIN=$(DOMAIN) SOURCE=$(SOURCE) STREAM=$(STREAM) VERSION=$(VERSION)

sql.lanes:
	@$(MAKE) -C $(SQL_DIR) lanes

# Full bootstrap: bring up containers, then build tables/views
bootstrap: up sql.bootstrap
	@echo "✓ Fabric bootstrap complete. Open Grafana at http://localhost:3000 (admin/admin)"
