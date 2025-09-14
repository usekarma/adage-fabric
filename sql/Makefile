# ===========================
# adage-fabric / sql/Makefile
# Schema-only (no docker compose)
# ===========================

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

# ---------- Paths ----------
RENDER         := ../scripts/render_lane_template.sh
LANE_SQL_DIR   := lanes
SHARED_TABLES  := shared/shared_tables.sql
SHARED_VIEWS   := shared/shared_views.sql

# Optional defaults for on-demand lane rendering
ORG     ?= adage
DOMAIN  ?= demo
SOURCE  ?= mongodb
STREAM  ?= cdc
VERSION ?= 1

# ---------- ClickHouse client inside container ----------
CH_NAME := $(shell docker ps --format '{{.Names}}' | grep -E 'clickhouse' | head -n1)
CHC     := docker exec -i $(CH_NAME) clickhouse-client -n     # stdin for multi-statement SQL
CHQ     := docker exec -i $(CH_NAME) clickhouse-client        # -q "SQL" one-liners

.PHONY: bootstrap shared.tables lane lanes shared.views

# Build DB objects only (assumes containers are already up)
bootstrap: shared.tables lanes shared.views
	@echo "✓ Fabric SQL bootstrap complete (tables/views only)"

# Create global/shared rollup tables (idempotent)
shared.tables:
	@echo "→ Creating shared global rollup tables"
	@cat $(SHARED_TABLES) | $(CHC)
	@echo "✓ Shared tables ready"

# Render & apply exactly one lane on demand
lane:
	@mkdir -p $(LANE_SQL_DIR)
	@[ -x $(RENDER) ] || (echo "Missing or non-executable $(RENDER) at '$(RENDER)'"; exit 1)
	@echo "→ Rendering $(ORG).$(DOMAIN).$(SOURCE).$(STREAM).v$(VERSION)"
	@ORG=$(ORG) DOMAIN=$(DOMAIN) SOURCE=$(SOURCE) STREAM=$(STREAM) VERSION=$(VERSION) \
		$(RENDER) > $(LANE_SQL_DIR)/$(SOURCE)_$(STREAM).sql
	@echo "→ Applying $(LANE_SQL_DIR)/$(SOURCE)_$(STREAM).sql"
	@cat $(LANE_SQL_DIR)/$(SOURCE)_$(STREAM).sql | $(CHC)
	@echo "✓ Rendered & applied $(LANE_SQL_DIR)/$(SOURCE)_$(STREAM).sql"

# Apply all already-rendered lanes (no rendering here)
lanes:
	@shopt -s nullglob; \
	files=($(LANE_SQL_DIR)/*.sql); \
	if [ $${#files[@]} -eq 0 ]; then \
		echo "… no lanes found in $(LANE_SQL_DIR). Render one with 'make lane'."; \
		exit 0; \
	fi; \
	for f in "$${files[@]}"; do \
		echo "→ Applying $$f"; \
		cat "$$f" | $(CHC); \
		echo "✓ Applied $$f"; \
	done

# Create cross-source shared views (only if a parsed table exists)
shared.views:
	@echo "→ Creating shared cross-source views"
	@if [ "$$($(CHQ) -q "EXISTS TABLE parsed_mongodb_cdc")" = "1" ]; then \
		cat $(SHARED_VIEWS) | $(CHC) ; \
	else \
		echo "… skipping parsed_all (parsed_mongodb_cdc not found yet)"; \
	fi
	@echo "✓ Shared cross-source views (conditional) done"
