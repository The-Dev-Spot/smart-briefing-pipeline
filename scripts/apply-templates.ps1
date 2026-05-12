# Apply OpenSearch index templates for Smart Briefing.
#
# Native PowerShell equivalent of apply-templates.sh. Works in Windows
# PowerShell 5.1 and PowerShell 7+.
#
# Reads OPENSEARCH_URL and OPENSEARCH_INITIAL_ADMIN_PASSWORD from the
# environment, or loads them from .env in the repo root.
#
# Idempotent. Re-running replaces existing templates with the current
# repo version.

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

# Resolve repo root from this script's location
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

# Load .env from repo root if env vars not already set in the session
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

# Self-signed cert handling. PowerShell 7+ has -SkipCertificateCheck;
# Windows PowerShell 5.1 needs the cert policy dance.
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

# Compute Basic Auth header once
$authPlain = "admin:$($env:OPENSEARCH_INITIAL_ADMIN_PASSWORD)"
$authHeader = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($authPlain))
$headers = @{
    'Authorization' = $authHeader
    'Content-Type'  = 'application/json'
}

$TemplateDir = Join-Path $RepoRoot 'config\index-templates'

Write-Host "Applying index templates to $env:OPENSEARCH_URL"
Write-Host ''

$failed = 0
$templates = Get-ChildItem -Path $TemplateDir -Filter '*.template.json' -ErrorAction Stop

foreach ($file in $templates) {
    $templateName = $file.BaseName -replace '\.template$', ''
    $url = "$env:OPENSEARCH_URL/_index_template/$templateName"

    Write-Host "-- $templateName"

    try {
        $body = Get-Content -Path $file.FullName -Raw
        $response = Invoke-RestMethod -Uri $url -Method PUT -Headers $headers -Body $body @skipCertParam
        $responseJson = $response | ConvertTo-Json -Compress -Depth 5
        Write-Host "   OK $responseJson"
    } catch {
        Write-Host "   FAIL $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                Write-Host "   Body: $($reader.ReadToEnd())"
            } catch {}
        }
        $failed = 1
    }
}

Write-Host ''
if ($failed -eq 0) {
    Write-Host 'All templates applied.'
} else {
    Write-Host 'One or more templates failed. Check output above.'
    exit 1
}
