# Seed the default briefing-config document for Smart Briefing.
#
# POSTs config/examples/ai-security-news/briefing-config.json (or whatever
# CONFIG_FILE is set to) to briefing-config/_doc/default.
#
# Re-runnable — replaces the existing default config.

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

$envFile = Join-Path $RepoRoot '.env'
if (-not $env:OPENSEARCH_URL -and (Test-Path $envFile)) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^([A-Z_][A-Z0-9_]*)=(.*)$') {
            Set-Item -Path "env:$($matches[1])" -Value $matches[2]
        }
    }
}

if (-not $env:OPENSEARCH_URL) {
    Write-Error 'OPENSEARCH_URL must be set (in .env or environment)'
    exit 1
}
if (-not $env:OPENSEARCH_INITIAL_ADMIN_PASSWORD) {
    Write-Error 'OPENSEARCH_INITIAL_ADMIN_PASSWORD must be set (in .env or environment)'
    exit 1
}

$ConfigFile = if ($env:CONFIG_FILE) {
    $env:CONFIG_FILE
} else {
    Join-Path $RepoRoot 'config\examples\ai-security-news\briefing-config.json'
}

if (-not (Test-Path $ConfigFile)) {
    Write-Error "Config file not found: $ConfigFile"
    Write-Host 'Set CONFIG_FILE env var to point at a different config.'
    exit 1
}

# TLS cert skip handling
$skipCertParam = @{}
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $skipCertParam['SkipCertificateCheck'] = $true
} else {
    if (-not ('TrustAllCerts' -as [type])) {
        Add-Type @'
            using System.Net;
            using System.Security.Cryptography.X509Certificates;
            public class TrustAllCerts : ICertificatePolicy {
                public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) {
                    return true;
                }
            }
'@
    }
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCerts
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}

$authPlain = "admin:$($env:OPENSEARCH_INITIAL_ADMIN_PASSWORD)"
$authHeader = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($authPlain))
$headers = @{
    'Authorization' = $authHeader
    'Content-Type'  = 'application/json'
}

Write-Host 'Seeding briefing-config/_doc/default from:'
Write-Host "  $ConfigFile"
Write-Host "Target: $env:OPENSEARCH_URL"
Write-Host ''

try {
    $body = Get-Content -Path $ConfigFile -Raw
    $url = "$env:OPENSEARCH_URL/briefing-config/_doc/default"
    $response = Invoke-RestMethod -Uri $url -Method POST -Headers $headers -Body $body @skipCertParam
    Write-Host "OK $($response | ConvertTo-Json -Compress -Depth 5)"
    Write-Host ''
    Write-Host 'Config seeded. The n8n workflow will read it at the start of every run.'
} catch {
    Write-Host "FAIL $($_.Exception.Message)"
    if ($_.Exception.Response) {
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            Write-Host "Body: $($reader.ReadToEnd())"
        } catch {}
    }
    exit 1
}
