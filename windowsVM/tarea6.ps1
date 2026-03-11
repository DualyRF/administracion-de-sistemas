# Servidores a usar: IIS, Apache, simple-http-server
function instalarHTTP{
    Clear-Host
    Write-Host "Servidores disponibles:"  -ForegroundColor Magenta
    Write-Host "  1. IIS (Internet Information Services)"
    Write-Host "  2. Apache HTTP Server"
    Write-Host "  3. simple-http-server"
    Write-Host ""
    Write-Host "  4. Volver al menú principal"  
    $s = Read-Host "Que servidor desea usar?"
    $p = Read-Host "Que puerto desea usar?"
    
    switch ($s) {
        "1" {
            instalarIIS -puerto $p
        }
        "2"{
            instalarApache -puerto $p
        }
        "3"{
            instalarSHS -puerto $p
        }
        "4" { 
            Write-Host "Saliendo..."; return 
        }
        default { Print-Warn "Opcion no valida." ; Start-Sleep -Seconds 1 }
    }
}

function instalarIIS {
    Write-Host "Versiones de IIS disponibles:"  -ForegroundColor Magenta
    Write-Host "  1- VERSION MAS RECIENTE"
    Write-Host "  2- VERSION ANTERIOR A LA MAS RECIENTE"
    Write-Host ""
    Write-Host "  4. Volver al menú principal"  
    $s = Read-Host "Que version desea usar?"


    Install-WindowsFeature -name Web-Server -IncludeManagementTools   
    Write-Host "Verificando instalación del servidor..." -ForegroundColor Cyan
    Get-Service W3SVC   
}

function instalarApache {

}

function instalarSHS {

}

# --------------------------
# MENU PRINCIPAL
# --------------------------
function menuPrincipal {
    do {
        Start-Sleep -Seconds 1
        Clear-Host
        Write-Host ""
        Write-Host "------------------------------------------------" -ForegroundColor Blue
        Write-Host "            GESTION SERVIDOR HTTPS              " -ForegroundColor Blue
        Write-Host "------------------------------------------------" -ForegroundColor Blue
        Write-Host "  1. Instalacion personalizada del servidor HTTP         "
        Write-Host "  2. Gestionar usuarios                                  "
        Write-Host "  3. "
        Write-Host "  4. "
        Write-Host "  5. "
        Write-Host "  6. "
        Write-Host "  7. "
        Write-Host "  8. Salir                                      "
        Write-Host "------------------------------------------------" -ForegroundColor Blue
        Write-Host ""

        $opcion = Read-Host "Selecciona una opcion"

        switch ($opcion) {
            "1" {
                Instalar-HTTP
                Read-Host "`nPresiona Enter para continuar"
            }
            "2" {

                Read-Host "`nPresiona Enter para continuar"
            }
            "3" {
                
                Read-Host "`nPresiona Enter para continuar"
            }
            "4" {
                
                Read-Host "`nPresiona Enter para continuar"
            }
            "5" {
                
                Read-Host "`nPresiona Enter para continuar"
            }
            "6" {
                
                Read-Host "`nPresiona Enter para continuar"
            }
            "7"{
                
                Read-Host "`nPresiona Enter para continuar"
            }
            "8" { Write-Host "Saliendo..."; return }
            default { Print-Warn "Opcion no valida." ; Start-Sleep -Seconds 1 }
        }
    } while ($true)
}

# --------------------------
# ENTRY POINT
# --------------------------
menuPrincipal