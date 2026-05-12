#!/usr/bin/env bash
# Seed the default briefing-config document for Smart Briefing.
#
# POSTs config/examples/ai-security-news/briefing-config.json (or whatever
# CONFIG_FILE is set to) to briefing-config/_doc/default.
#
# Re-runnable — replaces the existing default config.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -f "${REPO_ROOT}/.env" && -z "${OPENSEARCH_URL:-}" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/.env"
    set +a
fi

: "${OPENSEARCH_URL:?OPENSEARCH_URL must be set (in .env or environment)}"
: "${OPENSEARCH_INITIAL_ADMIN_PASSWORD:?OPENSEARCH_INITIAL_ADMIN_PASSWORD must be set}"

CONFIG_FILE="${CONFIG_FILE:-${REPO_ROOT}/config/examples/ai-security-news/briefing-config.json}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Config file not found: $CONFIG_FILE"
    echo "Set CONFIG_FILE env var to point at a different config."
    exit 1
fi

echo "Seeding briefing-config/_doc/default from:"
echo "  $CONFIG_FILE"
echo "Target: ${OPENSEARCH_URL}"
echo ""

response=$(curl -ks -w "\n%{http_code}" \
    -u "admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}" \
    -X POST "${OPENSEARCH_URL}/briefing-config/_doc/default" \
    -H 'Content-Type: application/json' \
    -d @"${CONFIG_FILE}")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [[ "$http_code" =~ ^2 ]]; then
    echo "OK ${http_code} ${body}"
    echo ""
    echo "Config seeded. The n8n workflow will read it at the start of every run."
else
    echo "FAIL ${http_code} ${body}"
    exit 1
fi
