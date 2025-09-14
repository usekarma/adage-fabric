# Root Makefile for Fabric
# Usage:
#   make up           # start services
#   make down         # stop services
#   make restart      # restart stack
#   make bootstrap    # up → wait.clickhouse → sql.bootstrap
#   make clean        # stop + remove volumes (fresh state)

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

# ----------------------
# Container management
# ----------------------
.PHONY: up down restart logs clean

up:
	docker compose up -d
	@echo "✓ Stack up"

down:
	docker compose down

restart: down up

logs:
	docker compose logs -f

clean:
	docker compose down -v
	@echo "✓ Containers and volumes removed"

# ----------------------
# ClickHouse readiness
# ----------------------
# IMPORTANT: service name must match docker-compose.yml (usually 'clickhouse')
CH_SERVICE := clickhouse

.PHONY: wait.clickhouse
wait.clickhouse:
	@for i in {1..60}; do \
		docker compose exec -T $(CH_SERVICE) clickhouse-client -q "SELECT 1" >/dev/null 2>&1 && { echo "✓ ClickHouse ready"; exit 0; }; \
		echo "waiting for ClickHouse... $$i"; sleep 1; \
	done; \
	echo "ClickHouse did not become ready in time" >&2; exit 1

# ----------------------
# SQL bootstrap (delegates to sql/Makefile)
# ----------------------
.PHONY: sql.bootstrap
sql.bootstrap:
	$(MAKE) -C sql bootstrap

.PHONY: bootstrap
bootstrap: up wait.clickhouse sql.bootstrap
	@echo "✓ Fabric bootstrap complete. Open Grafana at http://localhost:3000 (admin/admin)"
