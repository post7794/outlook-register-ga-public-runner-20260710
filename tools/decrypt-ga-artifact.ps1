param(
    [Parameter(Mandatory = $true)]
    [string]$Artifact,

    [string]$PrivateKey = "",

    [string]$PublicCert = "",

    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"

if (-not $PrivateKey) {
    $PrivateKey = Join-Path $PSScriptRoot "..\..\..\.local-secrets\ga-public-runner\results_private_key.pem"
}
if (-not $PublicCert) {
    $PublicCert = Join-Path $PSScriptRoot "..\keys\results_public_cert.pem"
}
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path (Get-Location) ((Split-Path $Artifact -LeafBase) + "-decrypted")
}

$opensslCandidates = @(
    "C:\Program Files\Git\usr\bin\openssl.exe",
    "C:\Program Files\Git\mingw64\bin\openssl.exe",
    "openssl"
)
$openssl = $null
foreach ($candidate in $opensslCandidates) {
    if ($candidate -eq "openssl") {
        if (Get-Command openssl -ErrorAction SilentlyContinue) {
            $openssl = "openssl"
            break
        }
    } elseif (Test-Path -LiteralPath $candidate) {
        $openssl = $candidate
        break
    }
}
if (-not $openssl) {
    throw "OpenSSL not found"
}

$artifactPath = (Resolve-Path -LiteralPath $Artifact).Path
$privateKeyPath = (Resolve-Path -LiteralPath $PrivateKey).Path
$publicCertPath = (Resolve-Path -LiteralPath $PublicCert).Path

$temp = Join-Path ([IO.Path]::GetTempPath()) ("ga-artifact-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    if ([IO.Path]::GetExtension($artifactPath) -ieq ".zip") {
        Expand-Archive -LiteralPath $artifactPath -DestinationPath $temp
        $cms = Get-ChildItem -LiteralPath $temp -Recurse -File -Filter *.cms | Select-Object -First 1
        if (-not $cms) { throw "No .cms evidence file found in artifact zip" }
        $cmsPath = $cms.FullName
    } else {
        $cmsPath = $artifactPath
    }

    $archive = Join-Path $temp "results.tar.gz"
    & $openssl cms -decrypt -binary -inform DER `
        -in $cmsPath `
        -recip $publicCertPath `
        -inkey $privateKeyPath `
        -out $archive
    if ($LASTEXITCODE -ne 0) { throw "OpenSSL decryption failed: exit $LASTEXITCODE" }

    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    tar -xzf $archive -C $OutputDirectory
    Write-Host "Decrypted evidence: $OutputDirectory"
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
