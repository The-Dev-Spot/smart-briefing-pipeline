# Setup

After `docker compose up -d`, this guide walks through everything needed to receive your first briefing email. Run the steps in order — each one has a verification check at the end before you move on.

## 1. Verify the stack came up healthy

Before doing anything else, confirm all three services are running and healthy:

```bash
docker compose ps
```

You should see three containers, all `Up` and (for opensearch + postgres) showing `healthy`:

```
NAME            STATUS                      PORTS
opensearch      Up X minutes (healthy)      0.0.0.0:9200->9200/tcp
n8n-postgres    Up X minutes (healthy)
n8n             Up X minutes                0.0.0.0:5678->5678/tcp
```

**Important — OpenSearch takes 60–90 seconds to reach `healthy` on first start** while it generates self-signed certs and runs the security plugin's bootstrap. If you see `Up X seconds (health: starting)`, wait. Re-run `docker compose ps` until you see `(healthy)`.

If OpenSearch flips to `Restarting` or never goes healthy, see [Common issues](#common-issues) below — most commonly a weak password being rejected.

### Direct healthcheck

Independent of the docker healthcheck, you can hit OpenSearch directly from your host:

**Linux / macOS:**
```bash
source .env
curl -ks -u "admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" \
    "$OPENSEARCH_URL/_cluster/health" | python3 -m json.tool
```

**Windows PowerShell:**
```powershell
Get-Content .env | ForEach-Object {
    if ($_ -match '^([A-Z_][A-Z0-9_]*)=(.*)$') {
        Set-Item -Path "env:$($matches[1])" -Value $matches[2]
    }
}
$auth = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("admin:$env:OPENSEARCH_INITIAL_ADMIN_PASSWORD"))
Invoke-RestMethod -Uri "$env:OPENSEARCH_URL/_cluster/health" `
    -Headers @{'Authorization'=$auth} -SkipCertificateCheck | ConvertTo-Json
```

Expected: a JSON response with `"status": "green"` or `"status": "yellow"`, `"number_of_nodes": 1`. Any non-200 here, or no response at all, means OpenSearch isn't actually ready — don't proceed until this works.

## 2. Apply OpenSearch index templates

This creates the schemas for `briefing-articles`, `briefing-runs`, and `briefing-config`. Idempotent — re-runnable anytime.

**Linux / macOS:**
```bash
./scripts/apply-templates.sh
```

**Windows PowerShell:**
```powershell
.\scripts\apply-templates.ps1
```

Expected output: three `OK` lines (one per template), each returning `{"acknowledged":true}`.

## 3. Seed the default config

POSTs the AI-security-news sample config to `briefing-config/_doc/default`. The workflow reads this at the start of every run.

**Linux / macOS:**
```bash
./scripts/seed-config.sh
```

**Windows PowerShell:**
```powershell
.\scripts\seed-config.ps1
```

Expected output: `OK {"_index":"briefing-config","_id":"default","_version":1,"result":"created",...}`. Re-running flips `result` to `"updated"`.

To use a different config, set `CONFIG_FILE` before running:
```bash
CONFIG_FILE=config/examples/my-topic/briefing-config.json ./scripts/seed-config.sh
```

## 4. Configure n8n

Open the n8n UI at [http://localhost:5678](http://localhost:5678) and create the owner account on first visit. Any password works for a local instance.

### Import the workflow

n8n UI → **Workflows** → **Import from File** → select `n8n/workflows/smart-briefing.json`.

You'll see 45 nodes load with red badges on 8 of them — that's correct, those are the credentials you'll create next.

### Create credentials

Four distinct credential types, eight credential references across the workflow:

| Credential name | Type | What to fill in |
|---|---|---|
| `OpenSearch admin` | HTTP Basic Auth | `admin` / value of `OPENSEARCH_INITIAL_ADMIN_PASSWORD` from `.env` |
| `Groq API` | HTTP Header Auth | Header: `Authorization`, value: `Bearer <your-groq-key>` |
| `Anthropic account` | Anthropic API | Your Anthropic API key |
| `SMTP account` | SMTP | Host, port, user, password from your SMTP provider |

The OpenSearch credential is reused by 5 nodes; the other three are 1-each.

n8n UI → **Credentials** → **New** → pick the type → name it **exactly** as shown above → save. Repeat for all four.

Once saved, the red badges on the workflow nodes turn green.

### Activate the workflow

In the n8n UI: open the imported workflow → toggle **Active** (top-right).

The workflow has a scheduled trigger (06:00 Mon–Sat by default — adjust in the `Schedule Trigger` node if you want a different time). To run immediately without waiting for the schedule, click **Execute Workflow** in the editor.

You should receive a briefing email within ~60 seconds. Stage 1 LLM calls take most of the time.

## 5. Verify end-to-end

After a run, check the run doc landed cleanly:

**Linux / macOS:**
```bash
source .env
TODAY=$(date -u +%Y-%m-%d)
curl -ks -u "admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" \
    "$OPENSEARCH_URL/briefing-runs/_doc/$TODAY" | python3 -m json.tool
```

**Windows PowerShell:**
```powershell
$today = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
$auth = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("admin:$env:OPENSEARCH_INITIAL_ADMIN_PASSWORD"))
Invoke-RestMethod -Uri "$env:OPENSEARCH_URL/briefing-runs/_doc/$today" `
    -Headers @{'Authorization'=$auth} -SkipCertificateCheck | ConvertTo-Json -Depth 10
```

Acceptance criteria on the returned document:
- `status: "completed"`
- `email_sent: true`
- `completed_at`, `email_sent_at`, `subject` all populated
- `counts.summarized` matches the number of articles in your email

If `status: "started"` and `email_sent: false`, check the n8n execution log — the `Persist & Close` node's HTTP response shows what failed (most commonly a credential or SMTP issue).

## Common issues

### OpenSearch never goes healthy

**Most likely cause: weak password.** OpenSearch 2.12+ rejects passwords without uppercase + lowercase + digit + special character + min 8 chars. Edit `.env`, set a stronger `OPENSEARCH_INITIAL_ADMIN_PASSWORD`, then:
```bash
docker compose down -v   # -v wipes the data volume too, since the password is baked in
docker compose up -d
```

**Other causes:**
- **Memory.** Default heap is 1GB. If Docker Desktop is restricted to < 4GB total, drop heap to 512MB in `docker-compose.yml`: change both `-Xms1g -Xmx1g` to `-Xms512m -Xmx512m` and bounce.
- **Port conflict.** Something else on port 9200. `docker compose down`, free the port, retry.

### `scripts/apply-templates.sh: command not found` on Windows

Use the PowerShell version instead: `.\scripts\apply-templates.ps1`. The repo ships both — you do not need WSL or Git Bash.

### Scripts can't resolve `'opensearch'`

The hostname `opensearch` only resolves inside the docker network. Host-side scripts use `OPENSEARCH_URL` from `.env`, which should be `https://localhost:9200`. If you changed it, change it back.

### n8n expressions show empty `$env.OPENSEARCH_URL`

Check `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` is in `docker-compose.yml` for the n8n service. It is by default in this repo, but worth checking after any compose edit.

### Cert errors when curling OpenSearch

Expected — the security plugin generates self-signed certs on first run. The `-k` flag for curl and `-SkipCertificateCheck` for PowerShell tell each tool to ignore them. The n8n HTTP nodes already have "Ignore SSL Issues" enabled.

### Email never arrives

Check spam first. If still missing, verify the SMTP credential's "from" address is one your provider allows — Gmail in particular rejects unauthenticated from-addresses. Most SMTP providers (SendGrid, Postmark, Resend, Mailgun) need a verified sender domain.

### `N8N_ENCRYPTION_KEY` generation

**Linux / macOS:** `openssl rand -hex 32`

**Windows PowerShell:** `-join ((1..32) | ForEach-Object { '{0:x2}' -f (Get-Random -Maximum 256) })`

Set this in `.env` **before** first launch. n8n auto-generates one if absent, which means credentials become unreadable on restart.
