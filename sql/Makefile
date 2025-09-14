
# =======================
# Fabric SQL Makefile (Slim)
# =======================
# Everyday:
#   make up
#   make shared.tables
#   make lanes
#   make shared.views
#   make bootstrap          # up → shared.tables → lanes → shared.views
#
# Occasionally (on demand):
#   make lane SOURCE=jira STREAM=events ORG=adage DOMAIN=demo VERSION=1
#
# Notes: requires docker compose v2, CH container name contains 'clickhouse', Redpanda contains 'redpanda'

# -------- Variables (override on CLI) --------
ORG      ?= adage
DOMAIN   ?= demo
SOURCE   ?= mongodb
STREAM   ?= cdc
VERSION  ?= 1

# Kafka fixture defaults (used by 'feed')
FILE ?= ../fixtures/case_orders_happy.jsonl
TOPIC ?= $(ORG).$(DOMAIN).$(SOURCE).$(STREAM).v$(VERSION)

# -------- Paths --------
RENDER        = ../scripts/render_lane_template.sh
LANE_SQL_DIR  = lanes
SHARED_TABLES = shared/shared_tables.sql
SHARED_VIEWS  = shared/shared_views.sql

# -------- Container helpers --------
CHC = docker exec -i $(shell docker ps --format '{{.Names}}' | grep -E 'clickhouse' | head -n1) clickhouse-client -n
RPK = docker exec -i $(shell docker ps --format '{{.Names}}' | grep -E 'redpanda' | head -n1) rpk

# =======================
# Core lifecycle targets
# =======================
.PHONY: up down restart ps logs clean

up:
\tdocker compose up -d

down:
\tdocker compose down

restart: down up

ps:
\tdocker compose ps

logs:
\tdocker compose logs -f

clean:
\trm -f $(LANE_SQL_DIR)/*.sql || true

# =======================
# Lanes (on demand vs everyday)
# =======================
.PHONY: lane lanes

# On-demand: render & apply exactly one new lane; does NOT run during bootstrap
lane:
\t@mkdir -p $(LANE_SQL_DIR)
\t@[ -x $(RENDER) ] || (echo "Missing or non-executable $(RENDER)"; exit 1)
\t@echo "→ Rendering lane: $(SOURCE)_$(STREAM)"
\t@ORG=$(ORG) DOMAIN=$(DOMAIN) SOURCE=$(SOURCE) STREAM=$(STREAM) VERSION=$(VERSION) \
\t\t$(RENDER) > $(LANE_SQL_DIR)/$(SOURCE)_$(STREAM).sql
\t@echo "→ Applying lane to ClickHouse: $(LANE_SQL_DIR)/$(SOURCE)_$(STREAM).sql"
\t@cat $(LANE_SQL_DIR)/$(SOURCE)_$(STREAM).sql | $(CHC)
\t@echo "✓ Lane applied: $(SOURCE)_$(STREAM)"

# Everyday: apply whatever lanes are already rendered in sql/lanes
lanes:
\t@shopt -s nullglob; \
\tfiles=($(LANE_SQL_DIR)/*.sql); \
\tif [ $${#files[@]} -eq 0 ]; then \
\t\techo "No lanes found in $(LANE_SQL_DIR). Render one with 'make lane' (on demand)."; exit 0; \
\tfi; \
\tfor f in "$${files[@]}"; do \
\t\techo "→ Applying $$f"; \
\t\tcat "$$f" | $(CHC); \
\t\techo "✓ Applied $$f"; \
\tdone

# =======================
# Shared artifacts
# =======================
.PHONY: shared.tables shared.views bootstrap

shared.tables:
\t@[ -f $(SHARED_TABLES) ] || (echo "Missing $(SHARED_TABLES)"; exit 1)
\t@echo "→ Creating shared global rollup tables"
\t@cat $(SHARED_TABLES) | $(CHC)
\t@echo "✓ Shared tables ready"

shared.views:
\t@[ -f $(SHARED_VIEWS) ] || (echo "Missing $(SHARED_VIEWS)"; exit 1)
\t@echo "→ Creating shared cross-source views"
\t@cat $(SHARED_VIEWS) | $(CHC)
\t@echo "✓ Shared views ready"

# Bootstrap excludes 'lane' so you only render lanes on demand
bootstrap: up shared.tables lanes shared.views
\t@echo "✓ Fabric bootstrap complete. Open Grafana at http://localhost:3000 (admin/admin)"

# =======================
# Fixtures → Kafka
# =======================
.PHONY: feed topic.create

topic.create:
\t@$(RPK) topic create $(TOPIC) >/dev/null 2>&1 || true
\t@echo "✓ Ensured topic exists: $(TOPIC)"

feed: topic.create
\t@echo "→ Producing $(FILE) to $(TOPIC)"
\t@$(RPK) topic produce $(TOPIC) < $(FILE)
\t@echo "✓ Produced $(FILE)"
