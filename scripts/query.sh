#!/usr/bin/env bash
set -euo pipefail
CHC="docker exec -i $(docker ps --format '{{.Names}}' | grep clickhouse) clickhouse-client -q"
$CHC "$@"
