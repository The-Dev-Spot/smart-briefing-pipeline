#!/usr/bin/env bash
# Apply OpenSearch index templates for Smart Briefing.
#
# Reads OPENSEARCH_URL and OPENSEARCH_INITIAL_ADMIN_PASSWORD from the
# environment (typically sourced from .env).
#
# Idempotent — re-running replaces existing templates with the current
# repo version.

set -euo pipefail

# Source .env if it exists and env vars aren't set
if [[ -f .env && -z "${OPENSEARCH_URL:-}" ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
fi

: "${OPENSEARCH_URL:?OPENSEARCH_URL must be set (in .env or environment)}"
: "${OPENSEARCH_INITIAL_ADMIN_PASSWORD:?OPENSEARCH_INITIAL_ADMIN_PASSWORD must be set}"

TEMPLATE_DIR="$(dirname "$0")/../config/index-templates"

echo "Applying index templates to ${OPENSEARCH_URL}"
echo ""

failed=0
for template_file in "${TEMPLATE_DIR}"/*.template.json; do
    [[ -f "$template_file" ]] || continue

    filename=$(basename "$template_file" .template.json)
    template_name="$filename"

    echo "── ${template_name}"

    response=$(curl -ks -w "\n%{http_code}" \
        -u "admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}" \
        -X PUT "${OPENSEARCH_URL}/_index_template/${template_name}" \
        -H 'Content-Type: application/json' \
        -d @"${template_file}")

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" =~ ^2 ]]; then
        echo "   ✓ ${http_code} ${body}"
    else
        echo "   ✗ ${http_code} ${body}"
        failed=1
    fi
done

echo ""
if [[ $failed -eq 0 ]]; then
    echo "✓ All templates applied."
else
    echo "✗ One or more templates failed. Check output above."
    exit 1
fi
