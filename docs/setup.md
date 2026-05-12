# Setup — configuring n8n

After completing the [README quickstart](../README.md#quickstart) (docker compose up, templates applied, config seeded), the n8n side needs configuration that can't be scripted — credentials are entered through the n8n UI.

## 1. Import the workflow

Open the n8n UI at [http://localhost:5678](http://localhost:5678) and create the owner account on first visit. Any password works for a local instance.

n8n UI → **Workflows** → **Import from File** → select `n8n/workflows/smart-briefing.json`.

50 nodes load with red badges on 7 of them — those are the credentials you'll create next.

## 2. Create credentials

Four distinct credential types, seven credential references across the workflow:

| Credential name | Type | What to fill in |
|---|---|---|
| `Opensearch` | HTTP Basic Auth | `admin` / value of `OPENSEARCH_INITIAL_ADMIN_PASSWORD` from `.env` |
| `Groq` | Groq API | Your Groq API key |
| `Anthropic account` | Anthropic API | Your Anthropic API key |
| `SMTP account` | SMTP | Host, port, user, password from your SMTP provider |

The Opensearch credential is reused by 4 nodes; the other three are 1-each.

n8n UI → **Credentials** → **New** → pick the type → name it **exactly** as shown above → save. Repeat for all four.

Once saved, the red badges on the workflow nodes turn green.

## 3. Activate the workflow

In the n8n UI: open the imported workflow → toggle **Active** (top-right).

The workflow has a scheduled trigger (06:00 Mon–Sat by default — adjust in the `Schedule Trigger` node if you want a different time). To run immediately without waiting for the schedule, click **Execute Workflow** in the editor.

You should receive a briefing email within ~60 seconds. Stage 1 LLM calls take most of the time.

## 4. Verify end-to-end

After a run, check that the run doc landed cleanly.

**Linux / macOS:**
```bash
source .env
TODAY=$(date -u +%Y-%m-%d)
curl -ks -u "admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" \
    "$OPENSEARCH_URL/briefing-runs/_doc/$TODAY" | python3 -m json.tool
```

**Windows PowerShell:**
```powershell
Get-Content .env | ForEach-Object {
    if ($_ -match '^([A-Z_][A-Z0-9_]*)=(.*)$') {
        Set-Item -Path "env:$($matches[1])" -Value $matches[2]
    }
}
$today = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
curl.exe -ks -u "admin:$env:OPENSEARCH_INITIAL_ADMIN_PASSWORD" `
    "$env:OPENSEARCH_URL/briefing-runs/_doc/$today" | ConvertFrom-Json | ConvertTo-Json -Depth 10
```

Acceptance criteria on the returned document:
- `status: "completed"`
- `email_sent: true`
- `completed_at`, `email_sent_at`, `subject` all populated
- `counts.summarized` matches the number of articles in your email

If `status: "started"` and `email_sent: false`, check the n8n execution log — the `Persist & Close` node's HTTP response shows what failed (most commonly a credential or SMTP issue).

---

## Troubleshooting

### Reddit RSS feeds return 403

Reddit rate-limits and restricts RSS access aggressively, especially for traffic from new IPs.

The shipped workflow already mitigates this: all three Reddit feeds (`r/Artificial`, `r/MachineLearning`, `r/LocalLLaMA`) use `HTTP Request` nodes rather than `rssFeedRead`. The default n8n RSS reader uses a User-Agent string Reddit explicitly blocks; the generic HTTP Request UA passes through.

If you still see 403s on Reddit feeds:

1. **Wait 15–30 minutes and retry.** Even with HTTP Request nodes, Reddit can rate-limit aggressively from fresh IPs.
2. **Other sources still produce a useful briefing.** Krebs, BleepingComputer, Dark Reading, The Hacker News, Simon Willison, Dark Web Informer, and Intelligence X don't go through Reddit. If Reddit is persistently 403ing, disable just those three nodes in the n8n UI — the rest of the pipeline runs unaffected.
3. **Set an explicit User-Agent header.** Open any Reddit `HTTP Request` node → Options → Add Header → `User-Agent` → e.g., `smart-briefing/1.0 (your-email@example.com)`. Reddit's policy specifically asks for an identifying UA.

### Verify OpenSearch is healthy independent of Docker

If `docker compose ps` shows `(healthy)` but something downstream is still failing, hit OpenSearch directly to rule out the security plugin:

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
curl.exe -ks -u "admin:$env:OPENSEARCH_INITIAL_ADMIN_PASSWORD" `
    "$env:OPENSEARCH_URL/_cluster/health" | ConvertFrom-Json | ConvertTo-Json
```

Expected: `"status": "green"` (or `"yellow"`), `"number_of_nodes": 1`.

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

Expected — the security plugin generates self-signed certs on first run. The `-k` flag for curl and `-SkipCertificateCheck` for PowerShell 7+ (or the cert-policy trick used in `apply-templates.ps1` for PS 5.1) tell each tool to ignore them. The n8n HTTP nodes already have "Ignore SSL Issues" enabled.

### Email never arrives

Check spam first. If still missing, verify the SMTP credential's "from" address is one your provider allows — Gmail in particular rejects unauthenticated from-addresses. Most SMTP providers (SendGrid, Postmark, Resend, Mailgun) need a verified sender domain.

### `N8N_ENCRYPTION_KEY` generation

**Linux / macOS:** `openssl rand -hex 32`

**Windows PowerShell:** `-join ((1..32) | ForEach-Object { '{0:x2}' -f (Get-Random -Maximum 256) })`

Set this in `.env` **before** first launch. n8n auto-generates one if absent, which means credentials become unreadable on restart.