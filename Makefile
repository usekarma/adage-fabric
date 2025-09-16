# Root Makefile for Fabric
# Usage:
#   make up             # start core services (no optional add-ons)
#   make up.all         # start core + optional profiled services (e.g., kafka-ui)
#   make down           # stop services
#   make restart        # restart stack
#   make bootstrap      # up → wait.clickhouse → sql.bootstrap
#   make clean          # stop + remove volumes (fresh state)
#   make kafka-ui       # start Kafka UI (optional; profiled)
#   make test.orders    # run the happy-path orders test
#   make feed FILE=... TOPIC=...   # produce a JSONL file to a Kafka topic
#
# Notes:
# - Keep optional/diagnostic services behind Compose profiles so they don't
#   auto-start during bootstrap. We've profiled kafka-ui under profile 'ui'.
#
# -----------------------------------------------------------------------------
# Hygiene & shell
# -----------------------------------------------------------------------------

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.ONESHELL:
.DEFAULT_GOAL := help

# Prefer an overridable compose command (supports podman-compose, etc.)
COMPOSE ?= docker compose

# -----------------------------------------------------------------------------
# Service names (must match docker-compose.yml)
# -----------------------------------------------------------------------------

CH_SERVICE ?= clickhouse
RP_SERVICE ?= redpanda
GRAFANA_SERVICE ?= grafana

# Core services that should come up by default (no profiles)
CORE_SERVICES := $(RP_SERVICE) $(CH_SERVICE) $(GRAFANA_SERVICE)

# -----------------------------------------------------------------------------
# Meta helpers
# -----------------------------------------------------------------------------

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nFabric Make Targets:\n\n"} /^[a-zA-Z0-9_.-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^## / { printf "\n%s\n", substr($$0,4) } ' $(MAKEFILE_LIST)
	@echo ""

# -----------------------------------------------------------------------------
# Container management
# -----------------------------------------------------------------------------

.PHONY: up
up: ## Start core services (Redpanda, ClickHouse, Grafana)
	$(COMPOSE) up -d $(CORE_SERVICES)
	@echo "✓ Stack up (core: $(CORE_SERVICES))"

.PHONY: up.all
up.all: ## Start core + profiled add-ons (currently: kafka-ui)
	$(COMPOSE) --profile ui up -d $(CORE_SERVICES) kafka-ui
	@echo "✓ Stack up (core + ui)"

.PHONY: down
down: ## Stop all services
	$(COMPOSE) down

.PHONY: restart
restart: down up ## Restart core services

.PHONY: logs
logs: ## Tail logs for all running services
	$(COMPOSE) logs -f

.PHONY: clean
clean: ## Stop and remove containers + volumes (fresh state)
	$(COMPOSE) down -v
	@echo "✓ Containers and volumes removed"

# -----------------------------------------------------------------------------
# ClickHouse readiness
# -----------------------------------------------------------------------------

.PHONY: wait.clickhouse
wait.clickhouse: ## Block until ClickHouse is ready to accept queries
	@for i in $$(seq 1 60); do \
		$(COMPOSE) exec -T $(CH_SERVICE) clickhouse-client -q "SELECT 1" >/dev/null 2>&1 && { echo "✓ ClickHouse ready"; exit 0; }; \
		echo "waiting for ClickHouse... $$i"; sleep 1; \
	done; \
	echo "ClickHouse did not become ready in time" >&2; exit 1

# -----------------------------------------------------------------------------
# SQL bootstrap (delegates to sql/Makefile)
# -----------------------------------------------------------------------------

.PHONY: sql.bootstrap
sql.bootstrap: ## Run SQL bootstrap (tables, views, facts)
	$(MAKE) -C sql bootstrap

.PHONY: bootstrap
bootstrap: up wait.clickhouse sql.bootstrap ## Bring up core + bootstrap SQL
	@echo "✓ Fabric bootstrap complete. Open Grafana at http://localhost:3000 (admin/admin)"

# -----------------------------------------------------------------------------
# Kafka / Redpanda helpers
# -----------------------------------------------------------------------------

.PHONY: feed
feed: topic.ensure ## Produce a JSONL file to a Kafka topic. Usage: make feed FILE=fixtures/case.jsonl TOPIC=topic.name
	@[ -n "$(FILE)" ] || (echo "FILE=<path to .jsonl> is required" >&2; exit 1)
	@[ -n "$(TOPIC)" ] || (echo "TOPIC=<kafka topic> is required" >&2; exit 1)
	@echo "→ Producing $(FILE) to $(TOPIC)"
	$(COMPOSE) exec -T $(RP_SERVICE) rpk topic produce "$(TOPIC)" < "$(FILE)"
	@echo "✓ Produced $(FILE) to $(TOPIC)"

.PHONY: topic.ensure
topic.ensure: ## Ensure a Kafka topic exists (idempotent). Requires TOPIC=...
	@[ -n "$(TOPIC)" ] || (echo "TOPIC=<kafka topic> is required" >&2; exit 1)
	@echo "→ Ensuring topic $(TOPIC) exists"
	$(COMPOSE) exec -T $(RP_SERVICE) bash -lc 'rpk topic list | awk "NR>1{print $$1}" | grep -xq "$(TOPIC)" || rpk topic create "$(TOPIC)" -p 1 -r 1 >/dev/null 2>&1 || true'

.PHONY: topic.create
topic.create: ## Explicitly create + describe a topic. Requires TOPIC=...
	@[ -n "$(TOPIC)" ] || (echo "TOPIC=<kafka topic> is required" >&2; exit 1)
	$(COMPOSE) exec -T $(RP_SERVICE) bash -lc 'rpk topic list | awk "NR>1{print $$1}" | grep -xq "$(TOPIC)" || rpk topic create "$(TOPIC)" -p 1 -r 1; rpk topic describe "$(TOPIC)" || true'

# -----------------------------------------------------------------------------
# Optional services (profiles)
# -----------------------------------------------------------------------------

.PHONY: kafka-ui
kafka-ui: ## Start Kafka UI (profile: ui)
	$(COMPOSE) --profile ui up -d kafka-ui
	@echo "✓ Kafka UI at http://localhost:8080"

# -----------------------------------------------------------------------------
# Tests
# -----------------------------------------------------------------------------

.PHONY: test.orders
test.orders: ## Run the happy-path orders test
	./scripts/run_case.sh case_orders_happy


# -----------------------------------------------------------------------------
# Test matrix
# -----------------------------------------------------------------------------

MATRIX ?= tests/test_matrix.txt

.PHONY: test.all
test.all: bootstrap ## Run all tests listed in $(MATRIX) (skips blank lines and # comments)
	@[ -f "$(MATRIX)" ] || (echo "Matrix file '$(MATRIX)' not found" >&2; exit 1)
	@echo "→ Running tests from $(MATRIX)"
	@fail=0; total=0; \
	while IFS= read -r c || [ -n "$$c" ]; do \
		# skip blanks and comments
		[ -z "$$c" ] && continue; \
		case "$$c" in \#*) continue;; esac; \
		total=$$((total+1)); \
		echo ""; echo "=== $$c ==="; \
		./scripts/run_case.sh "$$c" || { echo "✗ $$c"; fail=$$((fail+1)); }; \
	done < "$(MATRIX)"; \
	echo ""; \
	if [ "$$fail" -eq 0 ]; then echo "✓ All $$total tests passed"; else echo "✗ $$fail of $$total tests failed"; exit 1; fi


# -----------------------------------------------------------------------------
# Snapshots (expected CSVs)
# -----------------------------------------------------------------------------

EXPECTED_DIR ?= expected

.PHONY: snap.parsed
snap.parsed: ## Snapshot parsed table -> expected/$(CASE).parsed.csv (requires CASE=...)
	@[ -n "$(CASE)" ] || (echo "CASE=<name> is required, e.g., CASE=case_orders_happy" >&2; exit 1)
	@mkdir -p $(EXPECTED_DIR)
	@echo "→ Snapshot parsed_mongodb_cdc -> $(EXPECTED_DIR)/$(CASE).parsed.csv"
	@$(COMPOSE) exec -T $(CH_SERVICE) clickhouse-client -q "SELECT ts_event, source, event_type, ns, event_id, severity, op, status FROM parsed_mongodb_cdc ORDER BY ts_event, event_id FORMAT CSV" > "$(EXPECTED_DIR)/$(CASE).parsed.csv"
	@echo "✓ Wrote $(EXPECTED_DIR)/$(CASE).parsed.csv"

.PHONY: snap.facts
# FACT_TABLE defaults to fact_events_minute_all; override with FACT_TABLE=... and FACT_COLUMNS=...
FACT_TABLE ?= fact_events_minute_all
FACT_COLUMNS ?= t_min, c
snap.facts: ## Snapshot a fact table -> expected/$(CASE).$(FACT_TABLE).csv (requires CASE=...)
	@[ -n "$(CASE)" ] || (echo "CASE=<name> is required, e.g., CASE=case_orders_happy" >&2; exit 1)
	@mkdir -p $(EXPECTED_DIR)
	@echo "→ Snapshot $(FACT_TABLE) -> $(EXPECTED_DIR)/$(CASE).$(FACT_TABLE).csv"
	@$(COMPOSE) exec -T $(CH_SERVICE) clickhouse-client -q "SELECT $(FACT_COLUMNS) FROM $(FACT_TABLE) ORDER BY 1 FORMAT CSV" > "$(EXPECTED_DIR)/$(CASE).$(FACT_TABLE).csv"
	@echo "✓ Wrote $(EXPECTED_DIR)/$(CASE).$(FACT_TABLE).csv"

.PHONY: snap.custom
# NAME becomes the suffix in expected/CASE.NAME.csv
# SQL must be a full SELECT ending with FORMAT CSV (added if missing)
NAME ?= custom
SQL ?=
snap.custom: ## Snapshot with a custom SQL -> expected/$(CASE).$(NAME).csv (requires CASE=..., SQL='SELECT ... FORMAT CSV')
	@[ -n "$(CASE)" ] || (echo "CASE=<name> is required" >&2; exit 1)
	@[ -n "$(SQL)" ] || (echo "SQL='SELECT ... FORMAT CSV' is required" >&2; exit 1)
	@mkdir -p $(EXPECTED_DIR)
	@echo "→ Snapshot custom SQL -> $(EXPECTED_DIR)/$(CASE).$(NAME).csv"
	@$(COMPOSE) exec -T $(CH_SERVICE) clickhouse-client -q "$(SQL)" > "$(EXPECTED_DIR)/$(CASE).$(NAME).csv"
	@echo "✓ Wrote $(EXPECTED_DIR)/$(CASE).$(NAME).csv"

.PHONY: snap.all
snap.all: ## Snapshot common tables for CASE (parsed + default fact table)
snap.all: snap.parsed snap.facts
