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

    try {
        # -ErrorAction Stop es para que el 'catch' funcione
         Add-DNSServerResourceRecordA -Name $name -ZoneName $zoneName  -AllowUpdateAny -IPv4Address $ip  -ErrorAction Stop
        Write-Host "El registro '$name' se ha creado correctamente." -ForegroundColor $verde
    }
    catch {
        Write-Host "No se pudo crear el registro. Detalles: $($_.Exception.Message)" -ForegroundColor $rojo
    }
}

function agregarZonaPrimaria {
    param([string]$name)

    Add-DnsServerPrimaryZone -Name $name -ReplicationScope "Forest" -PassThru
}

function agregarZonaPrimaria2 {
    param([string]$name, [string]$zoneFile)

    try {
        # -ErrorAction Stop es para que el 'catch' funcione
        Add-DnsServerPrimaryZone -Name $name -ZoneFile $zoneFile -ErrorAction Stop
        Write-Host "La zona '$name' se ha creado correctamente." -ForegroundColor $verde
    }
    catch {
        Write-Host "No se pudo crear la zona. Detalles: $($_.Exception.Message)" -ForegroundColor $rojo
    }
}


function agregarZonaSecundaria {
    param(
        [string]$name,
        [string]$zoneFile,
        [string]$ipMS
    )

    try {
        Add-DnsServerSecondaryZone -Name $name -ZoneFile $zoneFile -MasterServers $ipMS -ErrorAction Stop
        Write-Host "La zona '$name' se ha creado correctamente." -ForegroundColor $verde
    }
    catch {
        Write-Host "No se pudo crear la zona. Detalles: $($_.Exception.Message)" -ForegroundColor $rojo
    }
}

function actualizarRegistro{
    param(
        [string]$name,
        [string]$zoneName,
        [string]$ip
    )
    try {
        $registro = Get-DnsServerResourceRecord -Name $name -ZoneName $zoneName
        $registro.RecordData.IPv4Address = $ip
        Set-DnsServerResourceRecord -NewInputObject $registro -OldInputObject $registro -ZoneName $name  -ErrorAction Stop

        Write-Host "El registro '$name' se ha actualizado correctamente." -ForegroundColor $verde
    }
    catch {
        Write-Host "No se pudo actualizar el registro. Detalles: $($_.Exception.Message)" -ForegroundColor $rojo
    }
}

function eliminarZona {
    param([string]$name)

    try {
        Remove-DnsServerZone -Name $name -Force -ErrorAction Stop
        Write-Host "La zona '$name' se ha eliminado correctamente." -ForegroundColor $verde
    }
    catch {
        Write-Host "No se pudo eliminar la zona. Detalles: $($_.Exception.Message)" -ForegroundColor $rojo
    }
}

function eliminarRegistro {
    param(
        [string]$name,
        [string]$zoneName
    )

    try {
        Remove-DnsServerResourceRecord -ZoneName $zoneName -RRType A -Name $name -Force  -ErrorAction Stop
        Write-Host "El registro '$name' se ha eliminado correctamente." -ForegroundColor $verde
    }
    catch {
        Write-Host "No se pudo eliminar el registro. Detalles: $($_.Exception.Message)" -ForegroundColor $rojo
    }

      
}

function modificarRegistro{
    param(
        [string]$zn,
        [string]$nomViejo,
        [string]$nomNuevo,
        [string]$nvIP
    )

    try {
        # 1. Obtener el registro actual
        $oldObj = Get-DnsServerResourceRecord -Name $nomViejo -ZoneName $zn -RRType "A" -ErrorAction Stop
        
        # 2. Crear una copia con los datos nuevos
        $newObj = $oldObj.Clone()
        $newObj.HostName = $nomNuevo
        $newObj.RecordData.IPv4Address = [System.Net.IPAddress]::Parse($nvIP)
        
        # 3. Reemplazar el viejo por el nuevo
        Set-DnsServerResourceRecord -OldInputObject $oldObj -NewInputObject $newObj -ZoneName $zn -ErrorAction Stop
        
        Write-Host "Registro actualizado con éxito." -ForegroundColor Green
    }
    catch {
        Write-Host "Error al intentar editar: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function configuracionDNS{
    Get-DnsServer
}

function verRegistroPorZonas{
    param([string]$name)

    try {
        Write-Host " ------------------------ " -BackgroundColor $rosa -ForegroundColor White
        Write-Host " Registros existentes" -BackgroundColor $rosa -ForegroundColor White
        Write-Host " ------------------------ " -BackgroundColor $rosa -ForegroundColor White
        Get-DnsServerResourceRecord -ZoneName $name -RRType "A"  -ErrorAction Stop | Format-Table -AutoSize
    }
    catch {
        Write-Host "La zona '$name' no tiene registros." -ForegroundColor $rojo
    }
}

function verZonas {
    Write-Host " ------------------------ " -BackgroundColor White -ForegroundColor $rosa 
    Write-Host " Zonas existentes" -BackgroundColor White -ForegroundColor $rosa
    Write-Host " ------------------------ " -BackgroundColor White -ForegroundColor $rosa
    Get-DnsServerZone   
}

function configuracionZona {
    Clear-Host
    Write-Host "----------------------------------" -ForegroundColor $amarillo
    Write-Host "   Menu configuracion de zona " -ForegroundColor $amarillo
    Write-Host "----------------------------------" -ForegroundColor $amarillo
    Write-Host "1. Ver zonas existentes" 
    Write-Host "2. Ver registros por zona" 
    Write-Host "3. Agregar zona" 
    Write-Host "4. Agregar registro" 
    Write-Host "5. Modificar registro" 
    Write-Host "6. Eliminar registro"
    Write-Host "7. Volver al menu principal" 
    Write-Host "----------------------------------" -ForegroundColor $amarillo
    
    $opc = Read-Host "Selecciona una opcion"
    switch ($opc) {
        "1" {
            verZonas
            Read-Host "`nPresiona Enter para continuar"
            configuracionZona
        }

        "2" {
            $zn = Read-Host "Dame el nombre de la zona"
            verRegistroPorZonas -name $zn
            Read-Host "`nPresiona Enter para continuar"
            configuracionZona
        }

        "3" {
            $opc = Read-Host "Desea agregar una zona? (y/n)"
            if ($opc -eq "y") { 
                $n = Read-Host "Dame el nombre de la zona"
                # Esto toma el nombre y le pega ".dns" al final automáticamente
                $zf = "$n.dns"

                agregarZonaPrimaria2 -name $n -zoneFile $zf
            }
            else {
                Write-Host "Entendido, regresando..." -ForegroundColor $rosa
                configuracionZona
            }
        }

        "4" {
            $DNSEstado = Get-WindowsFeature -Name *DNS*
            if ($DNSEstado.InstallState -eq "Installed") {
                $n = Read-Host "Dame el nombre del registro"
                $zn = Read-Host "Dame el nombre de la zona"
                $i = Read-Host "Dame la IP para el registro"
                agregarRegistro -name $n -zoneName $zn -ip $i
            }
            else {
                Write-Host "DNS no esta instalado. Instalelo primero." -ForegroundColor $rojo
            }
            Read-Host "`nPresiona Enter para continuar"
            configuracionZona
        }

        "5"{
            $n = Read-Host "Dame el nombre actual del registro"
            $zn = Read-Host "Dame el nombre de la zona"
            
            $nn = Read-Host "Dame el nuevo nombre para el registro"
            $nip = Read-Host "Dame la nueva IP para el registro"

            modificarRegistro -zn $zn -nomViejo $n -nomNuevo $nn -nvIP $nip
        }

        "6"{
            $n = Read-Host "Dame el nombre del registro a eliminar"
            $z = Read-Host "Dame el nombre de la zona del registro a eliminar"
            eliminarRegistro -name $n -zoneName $z
        }

        "7"{
            Write-Host "`nSaliendo..." -ForegroundColor $rosa
            return
        }
        
        default {
            Write-Host "Opcion no valida" -ForegroundColor $rojo
            Start-Sleep -Seconds 1
            configuracionZona
        }
    }

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
    Write-Host "3. Configuracion de zonas y registros"
    Write-Host "4. Salir" 
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
                configuracionZona
            }
            else {
                Write-Host "DNS no esta instalado. Instalelo primero." -ForegroundColor $rojo
            }
            Read-Host "`nPresiona Enter para continuar"
            mostrarMenu
        }
        "4" {
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
mostrarMenu
