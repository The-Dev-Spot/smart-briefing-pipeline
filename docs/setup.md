# Setup — n8n side

After `docker compose up` and `apply-templates.sh`, the OpenSearch side is ready. The n8n side needs a few manual steps because credentials can't safely ship in a public repo.

## 1. Open the n8n UI

[http://localhost:5678](http://localhost:5678) — create the owner account on first visit. Any password works for a local instance; you can disable auth on a single-user setup by adding `N8N_USER_MANAGEMENT_DISABLED=true` to `compose/n8n.yml` if you don't want it.

## 2. Import the workflow

n8n UI → **Workflows** → **Import from File** → select `n8n/workflows/smart-briefing.json`.

You'll see 45 nodes load with red badges on 8 of them — that's correct, those are the credentials you'll create next.

## 3. Create credentials

Four distinct credential types, eight credential references across the workflow:

| Credential name | Type | What to fill in |
|---|---|---|
| `OpenSearch admin` | HTTP Basic Auth | `admin` / `${OPENSEARCH_INITIAL_ADMIN_PASSWORD}` |
| `Groq API` | HTTP Header Auth | Header: `Authorization`, value: `Bearer <your-groq-key>` |
| `Anthropic account` | Anthropic API | Your Anthropic API key |
| `SMTP account` | SMTP | Host, port, user, password from your SMTP provider |

The OpenSearch credential is reused by 5 nodes; the other three are 1-each.

n8n UI → **Credentials** → **New** → pick the type → name it **exactly** as shown above → save. Repeat for all four.

Once saved, the red badges on the workflow nodes turn green.

## 4. Seed the default config

```bash
# Source .env to get OPENSEARCH_URL and admin password into your shell
source .env

# POST the sample config — one doc at _id='default'
curl -k -X POST "$OPENSEARCH_URL/briefing-config/_doc/default" \
    -u "admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" \
    -H 'Content-Type: application/json' \
    -d @config/examples/ai-security-news/briefing-config.json
```

Expected response: `{"_index":"briefing-config","_id":"default","_version":1,"result":"created", ...}`

To update an already-seeded config, just re-POST — `result` flips to `"updated"`.

## 5. Activate the workflow

In the n8n UI: open the imported workflow → toggle **Active** (top-right).

The workflow has a scheduled trigger (06:00 Mon–Sat by default — adjust in the `Schedule Trigger` node if you want a different time). To run immediately without waiting for the schedule, click **Execute Workflow** in the editor.

You should receive a briefing email within ~60 seconds. Stage 1 LLM calls take most of the time.

## Verifying it worked

After a run, check OpenSearch:

```bash
# Today's run doc — should have status: completed, email_sent: true
curl -ks -u "admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" \
    "$OPENSEARCH_URL/briefing-runs/_doc/$(date -u +%Y-%m-%d)" | jq .

# Article count from today's run
curl -ks -u "admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" \
    "$OPENSEARCH_URL/briefing-articles/_count?q=first_seen_run_id:$(date -u +%Y-%m-%d)" | jq .
```

If `briefing-runs/_doc/<today>` shows `status: started` instead of `status: completed`, check the n8n execution log — the `Persist & Close` node's HTTP response shows what failed (most commonly a credential or SMTP issue).

## Common issues

**OpenSearch healthcheck never goes green.** Usually memory. Drop heap in `compose/opensearch.yml` from `-Xms1g -Xmx1g` to `-Xms512m -Xmx512m` and bounce. Docker Desktop on macOS/Windows defaults to 4GB total — fine for one of the two services, tight for both.

**`apply-templates.sh: command not found` on Windows.** Run via WSL or Git Bash: `bash scripts/apply-templates.sh`. PowerShell can't execute `.sh` files directly.

**n8n expressions show empty `$env.OPENSEARCH_URL`.** Confirm `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` is set in `compose/n8n.yml`. It is by default in this repo, but worth checking after any compose edit.

**Cert errors when curling OpenSearch.** Expected — the security plugin generates self-signed certs on first run. The `-k` flag tells curl to ignore them. The n8n HTTP nodes already have "Ignore SSL Issues" enabled.

**Email never arrives.** Check spam first. If still missing, verify the SMTP credential's "from" address is one your provider allows — Gmail in particular rejects unauthenticated from-addresses. Most SMTP providers (SendGrid, Postmark, Resend, Mailgun) need a verified sender domain.

**N8N_ENCRYPTION_KEY generation.** On macOS/Linux: `openssl rand -hex 32`. On Windows PowerShell: `-join ((1..32) | ForEach-Object { '{0:x2}' -f (Get-Random -Maximum 256) })`. Set this in `.env` **before** first launch — n8n auto-generates one if absent, which means credentials become unreadable on restart.