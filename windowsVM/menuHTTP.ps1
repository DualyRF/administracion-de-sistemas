# ============================================================
# Solo contiene el menu, este llama a las funciones del otro script
# ============================================================

# -------------------
# Verificar que se ejecuta como Administrador
# -------------------
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] Debes ejecutar este script como Administrador." -ForegroundColor Red
    exit 1
}

# -------------------
# Cargando las funciones
# -------------------
. ".\librerias\funcionesHTTP.ps1"

# -------------------
# Menú principal
# -------------------
function menuPrincipalHTTP {
    do {
        Clear-Host
        Write-Host ""
        Write-Host "────────────────────────────────────────" -ForegroundColor Blue
        Write-Host "       GESTIÓN DE SERVIDOR HTTP          " -ForegroundColor Blue
        Write-Host "────────────────────────────────────────" -ForegroundColor Blue
        Write-Host "  1. Instalar servidor HTTP"
        Write-Host "  2. Gestionar servicios activos"
        Write-Host "  3. Ver estado de puertos"
        Write-Host "  4. Salir"
        Write-Host "────────────────────────────────────────" -ForegroundColor Blue
        Write-Host ""

        $op = Read-Host "Opción"

        switch ($op) {
            "1" { 
                InstalarHTTP;              
                Read-Host "`nEnter para continuar" 
            }
            "2" { 
                Get-Service W3SVC,Apache24 -ErrorAction SilentlyContinue | Format-Table
                Read-Host "`nEnter para continuar" 
            }
            "3" { 
                netstat -ano | findstr "LISTENING"
                Read-Host "`nEnter para continuar" 
            }
            "4" { Write-Host "Saliendo..."; return }
            default { Write-Host "[!] Opción no válida." -ForegroundColor Yellow; Start-Sleep -Seconds 1 }
        }
    } while ($true)
}

# -------------------
# Punto de partida
# -------------------
menuPrincipalHTTP