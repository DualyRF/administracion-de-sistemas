#Tarea 2 - Automatizacion y gestion del servidor DHCP

# ---------- Variables globales ----------
$verde = "Green"
$amarillo = "Yellow"
$azul = "Cyan"
$rojo = "Red"
$nc = "White"

# ---------- Funciones ----------
function validar_IP {
    
}

function validarMascara {
    
}

function calcularRango {
    
}

function validarIPMascara {
   
}

function calcularBits {
    
}

function configuracionDHCP {
  Write-Host " ------------------------ " -ForegroundColor $amarillo
  Write-Host " Configuracion de DNS " -ForegroundColor $amarillo
  Write-Host " ------------------------ " -ForegroundColor $amarillo
    
    # Variables locales
    $ipValida = $false
    $usoMas = $false
    $comp = $false

    Write-Host "`nConfiguracion Dinamica`n" -ForegroundColor $azul

    # Nombre del scope
    $scope = Read-Host "Nombre descriptivo del Ambito"

    # Máscara
    $mascValida = $false
    do {
        $mascara = Read-Host "Mascara (En blanco para asignar automaticamente)"
        if ($mascara -ne "") {
            if (validarMascara -masc $mascara) {
                $usoMas = $true
                $mascValida = $true
            }
        }
        else {
            $mascValida = $true
        }
    } while (-not $mascValida)

    # IP Inicial
    $ipValida = $false
    do {
        $ipInicial = Read-Host "Rango inicial de la IP"
        
        if (validar_IP -ip $ipInicial) {
            $ipValida = $true
        }
        
        if (-not $ipValida) {
            Write-Host "Intentando nuevamente..." -ForegroundColor $amarillo
        }
    } while (-not $ipValida)

    # IP Final
    $ipValida = $false
    do {
        $ipFinal = Read-Host "Rango final de la IP"
        
        if (validar_IP -ip $ipFinal) {
            $rango = calcularRango -ip1 $ipInicial -ip2 $ipFinal
            
            if ($rango -gt 2) {
                if ($usoMas) {
                    if (validarIPMascara -ipIni $ipInicial -ipFin $ipFinal -masc $mascara) {
                        $ipValida = $true
                    }
                }
                else {
                    $mascara = calcularMascara -ipIni $ipInicial -ipFin $ipFinal
                    Write-Host "Mascara calculada automaticamente: $mascara" -ForegroundColor $verde
                    $ipValida = $true
                }
            }
            else {
                Write-Host "El rango debe ser mayor a 2 IPs" -ForegroundColor $rojo
            }
        }
        
        if (-not $ipValida) {
            Write-Host "Intentando nuevamente..." -ForegroundColor $amarillo
        }
    } while (-not $ipValida)

    # Tiempo de sesión
    do {
        $leaseTime = Read-Host "Tiempo de la sesion (segundos)"
        $leaseTimeNum = $leaseTime -as [int]
        
        if ($null -eq $leaseTimeNum -or $leaseTimeNum -le 0) {
            Write-Host "Debe ingresar un numero positivo" -ForegroundColor $rojo
            $leaseTimeValido = $false
        }
        else {
            $leaseTimeValido = $true
        }
    } while (-not $leaseTimeValido)

    # Gateway - Calcular automáticamente
    $octetos = $ipInicial -split '\.'
    $ultimoOcteto = [int]$octetos[3]
    
    if ($ultimoOcteto -eq 1) {
        $gatewaySugerido = "$($octetos[0]).$($octetos[1]).$($octetos[2]).254"
    }
    else {
        $gatewaySugerido = "$($octetos[0]).$($octetos[1]).$($octetos[2]).1"
    }
    
    $comp = $false
    do {
        Write-Host "Gateway sugerido: " -NoNewline -ForegroundColor $amarillo
        Write-Host $gatewaySugerido -ForegroundColor $verde
        $gateway = Read-Host "Gateway (Enter para usar sugerido, vacio para omitir)"
        
        if ($gateway -eq "") {
            $usarSugerido = Read-Host "Usar gateway sugerido? (s/N)"
            if ($usarSugerido -match '^[Ss]$') {
                $gateway = $gatewaySugerido
            }
            else {
                $gateway = ""
                Write-Host "Sin gateway - red aislada" -ForegroundColor $amarillo
            }
            $comp = $true
        }
        elseif (validar_IP -ip $gateway) {
            $comp = $true
        }
        
        if (-not $comp) {
            Write-Host "Intentando nuevamente..." -ForegroundColor $amarillo
        }
    } while (-not $comp)

    # DNS Principal
    $comp = $false
    do {
        $dns = Read-Host "DNS principal (puede quedar vacio)"
        
        if ($dns -eq "") {
            $comp = $true
            $dnsAlt = ""
        }
        elseif (validar_IP -ip $dns) {
            $comp = $true
        }
        
        if (-not $comp) {
            Write-Host "Intentando nuevamente..." -ForegroundColor $amarillo
        }
    } while (-not $comp)

    # DNS Alternativo - solo si hay DNS principal
    if ($dns -ne "") {
        $comp = $false
        do {
            $dnsAlt = Read-Host "DNS alternativo (puede quedar vacio)"
            
            if ($dnsAlt -eq "") {
                $comp = $true
            }
            elseif (validar_IP -ip $dnsAlt) {
                $comp = $true
            }
            
            if (-not $comp) {
                Write-Host "Intentando nuevamente..." -ForegroundColor $amarillo
            }
        } while (-not $comp)
    }
    else {
        $dnsAlt = ""
    }

    # Mostrar interfaces de red disponibles
    Write-Host "`nInterfaces de red disponibles:" -ForegroundColor $amarillo
    Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object Name, InterfaceDescription | Format-Table -AutoSize
    $interfaz = Read-Host "Ingrese el nombre de la interfaz de red a usar"

    # Resumen de configuración
    Write-Host "`nLa configuracion final es:" -ForegroundColor $azul
    Write-Host "Nombre del ambito: " -NoNewline; Write-Host $scope -ForegroundColor $verde
    Write-Host "Mascara: " -NoNewline; Write-Host $mascara -ForegroundColor $verde
    Write-Host "IP inicial: " -NoNewline; Write-Host $ipInicial -ForegroundColor $verde
    Write-Host "IP final: " -NoNewline; Write-Host $ipFinal -ForegroundColor $verde
    Write-Host "Tiempo de consesion: " -NoNewline; Write-Host "$leaseTime segundos" -ForegroundColor $verde
    Write-Host "Gateway: " -NoNewline; Write-Host $(if($gateway -eq ""){"(sin gateway)"}else{$gateway}) -ForegroundColor $verde
    Write-Host "DNS primario: " -NoNewline; Write-Host $(if($dns -eq ""){"(vacio)"}else{$dns}) -ForegroundColor $verde
    Write-Host "DNS alternativo: " -NoNewline; Write-Host $(if($dnsAlt -eq ""){"(vacio)"}else{$dnsAlt}) -ForegroundColor $verde
    Write-Host "Interfaz: " -NoNewline; Write-Host "$interfaz`n" -ForegroundColor $verde

    $opc = Read-Host "Acepta esta configuracion? (y/n)"
    
    if ($opc -eq "y") {
        try {
            # Calcular la dirección de red correctamente
            $octetosIP = $ipInicial -split '\.'
            $octetosMasc = $mascara -split '\.'
            
            # AND bit a bit entre IP y máscara para obtener la red
            $red = @()
            for ($i = 0; $i -lt 4; $i++) {
                $red += [int]$octetosIP[$i] -band [int]$octetosMasc[$i]
            }
            $redStr = $red -join '.'
            
            # Calcular broadcast
            $broadcast = @()
            for ($i = 0; $i -lt 4; $i++) {
                $broadcast += [int]$octetosIP[$i] -bor (255 - [int]$octetosMasc[$i])
            }
            $broadcastStr = $broadcast -join '.'
            
            Write-Host "`nRed calculada: $redStr" -ForegroundColor $amarillo
            Write-Host "Broadcast calculado: $broadcastStr" -ForegroundColor $amarillo
            
            # Crear el scope
            Write-Host "`nCreando scope DHCP..." -ForegroundColor $amarillo
            Add-DhcpServerv4Scope `
                -Name $scope `
                -StartRange $ipInicial `
                -EndRange $ipFinal `
                -SubnetMask $mascara `
                -State Active
            
            Write-Host "Scope creado exitosamente" -ForegroundColor $verde
            
            # Configurar Gateway (Opción 3) - solo si existe
            if ($gateway -ne "") {
                Write-Host "Configurando Gateway..." -ForegroundColor $amarillo
                Set-DhcpServerv4OptionValue -ScopeId $redStr -OptionId 3 -Value $gateway
            }
            
            # Configurar DNS (Opción 6)
            if ($dns -ne "" -and $dnsAlt -ne "") {
                Write-Host "Configurando DNS principal y alternativo..." -ForegroundColor $amarillo
                Set-DhcpServerv4OptionValue -ScopeId $redStr -OptionId 6 -Value @($dns, $dnsAlt)
            }
            elseif ($dns -ne "") {
                Write-Host "Configurando DNS principal..." -ForegroundColor $amarillo
                Set-DhcpServerv4OptionValue -ScopeId $redStr -OptionId 6 -Value $dns
            }
            
            # Configurar tiempo de concesión
            Write-Host "Configurando tiempo de concesion..." -ForegroundColor $amarillo
            $duracion = New-TimeSpan -Seconds $leaseTime
            Set-DhcpServerv4Scope -ScopeId $redStr -LeaseDuration $duracion
            
            # Reiniciar servicio DHCP
            Write-Host "`nReiniciando servicio DHCP..." -ForegroundColor $amarillo
            Restart-Service DHCPServer
            
            # Verificar estado del servicio
            Start-Sleep -Seconds 2
            $servicioEstado = Get-Service DHCPServer
            
            if ($servicioEstado.Status -eq "Running") {
                Write-Host "`n¡Servidor DHCP configurado y funcionando correctamente!" -ForegroundColor $verde
                Write-Host "`nDetalles del Scope:" -ForegroundColor $azul
                Get-DhcpServerv4Scope -ScopeId $redStr | Format-List
            }
            else {
                Write-Host "`nError al iniciar el servicio DHCP" -ForegroundColor $rojo
                Write-Host "Estado del servicio:" -ForegroundColor $amarillo
                Get-Service DHCPServer | Format-List
            }
        }
        catch {
            Write-Host "`nError durante la configuracion: $_" -ForegroundColor $rojo
            Write-Host "Detalles: $($_.Exception.Message)" -ForegroundColor $amarillo
        }
    }
    else {
        Write-Host "`nConfiguracion cancelada" -ForegroundColor $amarillo
        Write-Host "Volviendo al menu..." -ForegroundColor $amarillo
        Start-Sleep -Seconds 2
    }
}

function configuracionDHCP_Predeterminada {
    Write-Host "`nAplicando configuracion predeterminada de DHCP..." -ForegroundColor $verde
    
    try {
        # Parámetros predeterminados
        $scope = "Red Predeterminada"
        $ipInicial = "192.168.1.100"
        $ipFinal = "192.168.1.200"
        $mascara = "255.255.255.0"
        $gateway = "192.168.1.1"
        $dns = "8.8.8.8"
        $dnsAlt = "8.8.4.4"
        $leaseTime = 600
        $redStr = "192.168.1.0"
        
        Write-Host "Red: 192.168.1.0/24" -ForegroundColor $azul
        Write-Host "Rango DHCP: 192.168.1.100 - 192.168.1.200" -ForegroundColor $azul
        Write-Host "Gateway: 192.168.1.1" -ForegroundColor $azul
        Write-Host "DNS: 8.8.8.8, 8.8.4.4`n" -ForegroundColor $azul
        
        # Crear scope
        Add-DhcpServerv4Scope `
            -Name $scope `
            -StartRange $ipInicial `
            -EndRange $ipFinal `
            -SubnetMask $mascara `
            -State Active
        
        # Configurar opciones
        Set-DhcpServerv4OptionValue -ScopeId $redStr -OptionId 3 -Value $gateway
        Set-DhcpServerv4OptionValue -ScopeId $redStr -OptionId 6 -Value @($dns, $dnsAlt)
        
        $duracion = New-TimeSpan -Seconds $leaseTime
        Set-DhcpServerv4Scope -ScopeId $redStr -LeaseDuration $duracion
        
        # Reiniciar servicio
        Restart-Service DHCPServer
        Start-Sleep -Seconds 2
        
        Write-Host "Configuracion predeterminada aplicada exitosamente" -ForegroundColor $verde
        Get-DhcpServerv4Scope -ScopeId $redStr | Format-List
    }
    catch {
        Write-Host "Error al aplicar configuracion predeterminada: $_" -ForegroundColor $rojo
    }
}

function instalacionDNS {
  Write-Host " ------------------------ " -ForegroundColor $amarillo
  Write-Host "Instalacion de DNS Server" -ForegroundColor $amarillo
  Write-Host " ------------------------ " -ForegroundColor $amarillo

    
    # Verificar si ya está instalado
    $dnsEstado = Get-WindowsFeature -Name DNS
    
    if ($dhcpEstado.InstallState -eq "Installed") {
        Write-Host "DNS server ya esta instalado" -ForegroundColor $azul
    }
    else {
        Write-Host "DNS server no esta instalado, iniciando instalacion..." -ForegroundColor $amarillo
        
        try {
            # Instalar en segundo plano con animación
            $job = Start-Job -ScriptBlock {
                Install-WindowsFeature -Name DNS -IncludeManagementTools
            }
            
            Write-Host -NoNewline "DHCP se esta instalando"
            while ($job.State -eq "Running") {
                Write-Host -NoNewline "."
                Start-Sleep -Milliseconds 500
            }
            Write-Host ""
            
            $result = Receive-Job -Job $job
            Remove-Job -Job $job
            
            if ($result.Success) {
                Write-Host "DNS server instalado correctamente" -ForegroundColor $verde
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
    
    Write-Host ""
    
    # Verificar si existe configuración previa
    $scopesExistentes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
    
    if ($scopesExistentes) {
        Write-Host "Se detectó una configuracion previa de DHCP" -ForegroundColor $amarillo
        Write-Host "Scopes existentes:" -ForegroundColor $amarillo
        $scopesExistentes | Format-Table -AutoSize
        
        $sobreescribir = Read-Host "`nDeseas sobreescribir la configuracion existente? (s/N)"
        
        if ($sobreescribir -notmatch '^[Ss]$') {
            Write-Host "Manteniendo configuracion existente" -ForegroundColor $azul
            return
        }
        
        Write-Host "`nEliminando configuracion anterior..." -ForegroundColor $amarillo
        foreach ($scope in $scopesExistentes) {
            Remove-DhcpServerv4Scope -ScopeId $scope.ScopeId -Force
        }
    }
    
    Write-Host ""
    
    # Preguntar tipo de configuración
    Write-Host "Deseas configurar DHCP manualmente o usar configuracion predeterminada?" -ForegroundColor $amarillo
    Write-Host "1) Configurar manualmente"
    Write-Host "2) Usar configuracion predeterminada"
    Write-Host ""
    
    $opcion = Read-Host "Selecciona una opcion [1-2]"
    
    switch ($opcion) {
        "1" {
            Write-Host "`nIniciando configuracion manual de DHCP..." -ForegroundColor $verde
            configuracionDHCP
        }
        "2" {
            configuracionDHCP_Predeterminada
        }
        default {
            Write-Host "Opcion no valida, usando configuracion predeterminada" -ForegroundColor $rojo
            configuracionDHCP_Predeterminada
        }
    }
    
    Write-Host "`n=== Configuracion de DHCP completada ===" -ForegroundColor $verde
}

function verificar_Instalacion {
    $dhcpEstado = Get-WindowsFeature -Name DHCP

    if ($dhcpEstado.InstallState -eq "Installed") {
        Write-Host "DHCP ya se encuentra instalado" -ForegroundColor $verde
        
        # Mostrar scopes existentes
        $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
        if ($scopes) {
            Write-Host "`nScopes configurados:" -ForegroundColor $azul
            $scopes | Format-Table -AutoSize
        }
        
        # Mostrar estado del servicio
        $servicio = Get-Service DHCPServer
        Write-Host "`nEstado del servicio:" -ForegroundColor $azul
        Write-Host "Estado: " -NoNewline
        if ($servicio.Status -eq "Running") {
            Write-Host "Funcionando" -ForegroundColor $verde
        }
        else {
            Write-Host "Detenido" -ForegroundColor $rojo
        }
    }
    else {
        Write-Host "DHCP no se encuentra instalado" -ForegroundColor $rojo
        $opcc = Read-Host "`nDesea instalarlo? (S/N)"
        
        if ($opcc -match '^[Ss]$') {
            instalacionDHCP
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
    Write-Host ""
    Write-Host "1. Verificar Instalacion" 
    Write-Host "2. Instalar y Configurar DHCP" 
    Write-Host "3. Configurar DHCP"
    Write-Host "4. Ver Scopes Activos" 
    Write-Host "5. Salir" 
    Write-Host "----------------------------------" -ForegroundColor $azul
    
    $opcion = Read-Host "Selecciona una opcion"
    
    switch ($opcion) {
        "1" {
            verificar_Instalacion
            Read-Host "`nPresiona Enter para continuar"
            mostrarMenu
        }
        "2" {
            instalacionDHCP
            Read-Host "`nPresiona Enter para continuar"
            mostrarMenu
        }
        "3" {
            $dhcpEstado = Get-WindowsFeature -Name DHCP
            if ($dhcpEstado.InstallState -eq "Installed") {
                configuracionDHCP
            }
            else {
                Write-Host "DHCP no esta instalado. Instálelo primero." -ForegroundColor $rojo
            }
            Read-Host "`nPresiona Enter para continuar"
            mostrarMenu
        }
        "4" {
            $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
            if ($scopes) {
                $scopes | Format-Table -AutoSize
            }
            else {
                Write-Host "No hay scopes configurados" -ForegroundColor $amarillo
            }
            Read-Host "`nPresiona Enter para continuar"
            mostrarMenu
        }
        "5" {
            Write-Host "`nSaliendo..." -ForegroundColor $verde
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
