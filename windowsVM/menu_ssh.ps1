# Importar las funciones de archivos externos
. ".\funcionesSSH.ps1"
. ".\tarea3.ps1"
. ".\tarea2dhcp.ps1"

Clear-Host
verNiveldeAcceso

# Validar que sea administrador
if (-not (admin)) {
    Write-Error "Este script debe ejecutarse como Administrador."
    exit
}

do {
    Clear-Host
    Write-Host "===============================================" -ForegroundColor Yellow
    Write-Host "   MENÚ DE ADMINISTRACIÓN REMOTA (WINDOWS)     " -ForegroundColor Yellow
    Write-Host "===============================================" -ForegroundColor Yellow
    Write-Host "1. Instalar y Asegurar SSH (Acceso Remoto)"
    Write-Host "2. Configurar Servicio DHCP (Refactorizado)"
    Write-Host "3. Configurar Servicio DNS (Refactorizado)"
    Write-Host "4. Salir"
    Write-Host "-----------------------------------------------"
    
    $opcion = Read-Host "Seleccione una opción"

    switch ($opcion) {
        "1" { 
            instalarSSH 
            Pause
        }
        "2" { 
            Write-Host "Ejecutando configuración DHCP..."
            mostrarMenuDHCP
            Pause
        }
        "3" { 
            Write-Host "Ejecutando configuración DNS..."
            mostrarMenuDNS
            Pause
        }
        "4" { 
            Write-Host "Saliendo..." -ForegroundColor Magenta
            break 
        }
        Default { 
            Write-Host "Opción no válida." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
} while ($opcion -ne "4")