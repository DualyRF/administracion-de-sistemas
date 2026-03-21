Import-Module FileServerResourceManager

# Recrear plantillas desde cero
Remove-FsrmQuotaTemplate -Name "Cuota-Cuates"   -Confirm:$false -ErrorAction SilentlyContinue
Remove-FsrmQuotaTemplate -Name "Cuota-NoCuates" -Confirm:$false -ErrorAction SilentlyContinue

New-FsrmQuotaTemplate -Name "Cuota-Cuates"   -Size (10MB) -SoftLimit $false
New-FsrmQuotaTemplate -Name "Cuota-NoCuates" -Size (5MB)  -SoftLimit $false

# Aplicar cuotas a cada carpeta
$cuates   = @("notlizy","netobrdf","amora","lvega","dulcevrz")
$nocuates = @("sdiaz","cpena","dualyrf","dulceosu","hosuna")

foreach ($u in $cuates) {
    Remove-FsrmQuota -Path "C:\Perfiles\$u" -Confirm:$false -ErrorAction SilentlyContinue
    New-FsrmQuota -Path "C:\Perfiles\$u" -Template "Cuota-Cuates"
    Write-Host "[OK] Cuota 10MB -> $u" -ForegroundColor Green
}

foreach ($u in $nocuates) {
    Remove-FsrmQuota -Path "C:\Perfiles\$u" -Confirm:$false -ErrorAction SilentlyContinue
    New-FsrmQuota -Path "C:\Perfiles\$u" -Template "Cuota-NoCuates"
    Write-Host "[OK] Cuota 5MB -> $u" -ForegroundColor Green
}