$verde = "Green"
$amarillo = "Yellow"
$azul = "Cyan"
$rojo = "Red"
$nc = "White"
$rosa = "Magenta"

# ---------- Funciones ----------
function agregarRegistro {
    param(
        [string]$name,
        [string]$zoneName,
        [string]$ip
    )

    Add-DNSServerResourceRecordA -Name $name -ZoneName $zoneName  -AllowUpdateAny -IPv4Address $ip
}

function agregarZonaPrimaria {
    param(
        [string]$name,
        [string]$rs
    )

    Add-DnsServerPrimaryZone -Name $name -ReplicationScope $rs -PassThru
}

function agregarZonaSecundaria {
    param(
        [string]$name,
        [string]$zoneFile,
        [string]$ipMS
    )

    Add-DnsServerSecondaryZone -Name $name -ZoneFile $zoneFile -MasterServers $ipMS    
}

function actualizarRegistro{
    param(
        [string]$name,
        [string]$zoneName,
        [string]$ip
    )

    $registro = Get-DnsServerResourceRecord -Name $name -ZoneName $zoneName
    $registro.RecordData.IPv4Address = $ip
    Set-DnsServerResourceRecord -NewInputObject $registro -OldInputObject $registro -ZoneName $name   
}

function eliminarZona {
    param([string]$name)
    Remove-DnsServerZone -Name $name -Force 
}

function configuracionDNS {
    Write-Host " ------------------------ " -ForegroundColor $rosa
    Write-Host " Zonas existentes" -ForegroundColor $rosa
    Write-Host " ------------------------ " -ForegroundColor $rosa
    Get-DnsServerZone   
}

function instalacionDNS {
  Write-Host " ---------------------------- " -ForegroundColor $rosa
  Write-Host "Instalacion de DNS Server" -ForegroundColor $rosa
  Write-Host " ---------------------------- " -ForegroundColor $rosa
    
    # Verificar si ya está instalado
    $dnsEstado = Get-WindowsFeature -Name *DNS*
    
    if ($DNSEstado.InstallState -eq "Installed") {
        Write-Host "DNS server ya esta instalado" -ForegroundColor $azul
    }
    else {
        Write-Host "DNS server no esta instalado, iniciando instalacion..." -ForegroundColor $amarillo
        
        try {
            $job = Start-Job -ScriptBlock {
                Install-WindowsFeature -Name DNS -includeManagementTools
            }
            
            Write-Host -NoNewline "DNS se esta instalando"
            while ($job.State -eq "Running") {
                Write-Host -NoNewline "."
                Start-Sleep -Milliseconds 500
            }
            
            $result = Receive-Job -Job $job
            Remove-Job -Job $job
            
            if ($result.Success) {
                Write-Host "DNS server instalado correctamente" -ForegroundColor $verde
                Get-WindowsFeature -Name *DNS*
                Start-Sleep -Seconds 2
            }
            else {
                Write-Host "Error en la instalacion de DNS" -ForegroundColor $rojo
                return
            }
        }
        catch {
            Write-Host "Error durante la instalacion: $_" -ForegroundColor $rojo
            return
        }
    }
}

function verificarInstalacion {
    $DNSEstado = Get-WindowsFeature -Name *DNS*

    if ($DNSEstado.InstallState -eq "Installed") {
        Write-Host "DNS ya se encuentra instalado" -ForegroundColor $verde
    }
    else {
        Write-Host "DNS no se encuentra instalado" -ForegroundColor $rojo
        $opcc = Read-Host "`nDesea instalarlo? (S/N)"
        
        if ($opcc -match '^[Ss]$') {
            instalacionDNS
        }
        else {
            Write-Host "Entendido, regresando al menu..." -ForegroundColor $amarillo
            Start-Sleep -Seconds 2
        }
    }
}

function mostrarMenu {
    Clear-Host
    Write-Host "----------------------------------" -ForegroundColor $azul
    Write-Host "   Menu  " -ForegroundColor $azul
    Write-Host "----------------------------------" -ForegroundColor $azul
    Write-Host "1. Verificar Instalacion" 
    Write-Host "2. Instalar DNS" 
    Write-Host "3. Configurar zona y registros"
    Write-Host "4. Agregar Registro" 
    Write-Host "5. Salir" 
    Write-Host "----------------------------------" -ForegroundColor $azul
    
    $opcion = Read-Host "Selecciona una opcion"
    
    switch ($opcion) {
        "1" {
            verificarInstalacion
            Read-Host "`nPresiona Enter para continuar"
            mostrarMenu
        }
        "2" {
            instalacionDNS
            Read-Host "`nPresiona Enter para continuar"
            mostrarMenu
        }
        "3" {
            $DNSEstado = Get-WindowsFeature -Name *DNS*
            if ($DNSEstado.InstallState -eq "Installed") {
                configuracionDNS
            }
            else {
                Write-Host "DNS no esta instalado. Instálelo primero." -ForegroundColor $rojo
            }
            Read-Host "`nPresiona Enter para continuar"
            mostrarMenu
        }
        "4" {
            $DNSEstado = Get-WindowsFeature -Name *DNS*
            if ($DNSEstado.InstallState -eq "Installed") {
                $n = Read-Host "Dame el nombre del registro"
                $zn = Read-Host "Dame el nombre de la zona"
                $i = Read-Host "Dame la IP para la zona"
                agregarRegistro -name $n -zoneName $zn -ip $i
            }
            else {
                Write-Host "DNS no esta instalado. Instálelo primero." -ForegroundColor $rojo
            }
            Read-Host "`nPresiona Enter para continuar"
            mostrarMenu
        }
        "5" {
            Write-Host "`nSaliendo..." -ForegroundColor $rosa
            exit
        }
        default {
            Write-Host "Opcion no valida" -ForegroundColor $rojo
            Start-Sleep -Seconds 2
            mostrarMenu
        }
    }
}

# ---------- Main ----------
param(
    [switch]$v,
    [switch]$i,
    [switch]$c
)

if ($v) {
    verificar_Instalacion
}
elseif ($i) {
    instalacionDHCP
}
elseif ($c) {
    configuracionDHCP
}
else {
    mostrarMenu
}
