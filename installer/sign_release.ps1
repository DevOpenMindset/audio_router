# ─── AudioRouter — Self-Signed Code Signing Script ───────────────────────────
# Crée un certificat auto-signé et signe soundshift.exe + audio_backend.dll
# NOTE: Réduit l'alerte SmartScreen mais ne la supprime pas totalement.
# Pour supprimer SmartScreen complètement → EV Certificate (~300€/an) ou Windows Store.
#
# Usage: .\sign_release.ps1
# ─────────────────────────────────────────────────────────────────────────────

$AppName    = "AudioRouter"
$ReleasDir  = "..\build\windows\x64\runner\Release"
$CertPfx    = ".\AudioRouter_CodeSign.pfx"
$CertPass   = "AudioRouter2024!"   # Change si tu veux

Write-Host "=== AudioRouter Code Signing ===" -ForegroundColor Cyan

# ── 1. Crée le certificat auto-signé ────────────────────────────────────────
if (-not (Test-Path $CertPfx)) {
    Write-Host "Création du certificat auto-signé..." -ForegroundColor Yellow
    $cert = New-SelfSignedCertificate `
        -Type CodeSigningCert `
        -Subject "CN=$AppName, O=$AppName, C=FR" `
        -KeyUsage DigitalSignature `
        -FriendlyName "$AppName Code Signing" `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -HashAlgorithm SHA256 `
        -NotAfter (Get-Date).AddYears(5)

    $pwd = ConvertTo-SecureString -String $CertPass -Force -AsPlainText
    Export-PfxCertificate -Cert $cert -FilePath $CertPfx -Password $pwd | Out-Null
    Write-Host "Certificat créé : $CertPfx" -ForegroundColor Green
} else {
    Write-Host "Certificat existant trouvé : $CertPfx" -ForegroundColor Green
}

# ── 2. Signe les fichiers ────────────────────────────────────────────────────
$signtool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe"
if (-not (Test-Path $signtool)) {
    # Cherche signtool dans les chemins connus
    $signtool = Get-ChildItem "C:\Program Files (x86)\Windows Kits" -Recurse -Filter "signtool.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like "*x64*" } | Select-Object -First 1 -ExpandProperty FullName
}

if (-not $signtool) {
    Write-Host "ERREUR: signtool.exe introuvable. Installe Windows SDK." -ForegroundColor Red
    exit 1
}

Write-Host "Utilisation de signtool : $signtool" -ForegroundColor Gray

$filesToSign = @(
    "$ReleasDir\soundshift.exe",
    "$ReleasDir\audio_backend.dll"
)

foreach ($file in $filesToSign) {
    if (Test-Path $file) {
        Write-Host "Signature de $(Split-Path $file -Leaf)..." -ForegroundColor Yellow
        & $signtool sign /fd SHA256 /p7 . /a /f $CertPfx /p $CertPass /t "http://timestamp.digicert.com" $file
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  OK" -ForegroundColor Green
        } else {
            Write-Host "  ERREUR lors de la signature" -ForegroundColor Red
        }
    } else {
        Write-Host "Fichier introuvable (skipped): $file" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "=== Terminé ===" -ForegroundColor Cyan
Write-Host "Note: SmartScreen affichera toujours un avertissement avec un cert auto-signé."
Write-Host "Pour l'éliminer, utilise un EV Certificate ou publie sur le Windows Store (19$ unique)."
