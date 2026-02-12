Function validarIP{
	param ([string] $ip)

## validacion para checar si la ip tiene formato x.x.x.x

	if ($ipEntrada -match "^[0-9]+\.+[0-9]+\.[0-9]+\.[0-9]+$"){
		write-host "Formato válido"
	}
	else {
		Write-Host "Ip invalida" -ForegroundColor Yellow
		Start-Sleep -Seconds 3
		return
	}

	
## validacion para checar si la ip esta ocupada

	$chequeo = Get-DhcpServerv4Lease -ScopeId 192.168.100.0 | Where-Object IPAddress -eq $ip
	if ($chequeo) { 
		Write-Host "Esa IP ya esta en uso por $($chequeo.ClientId)" Start-Sleep -Seconds 4
		return
	}

## validacion para checar si el rango de la ip es acertado
	$regexRango = "^192\.168\.100\.([5-9]\d|1[0-4]\d|150)$"
	if ($ip -match $regexRango){
		Write-Host "Ip dentro del rango" -ForegroundColor Green
		Start-Sleep -Seconds 1
	}
	else {
		Write-Host "Rango Incorrecto ://" -ForegroundColor Red
		Start-Sleep -Seconds 2
		return
	}
}



Function validarIP2{
	param ([string] $ipi, [string] $ipf)
	
## validacion para checar si la ip esta ocupada

	$chequeo = Get-DhcpServerv4Lease -ScopeId 192.168.100.0 | Where-Object IPAddress -eq $ipf
	if ($chequeo) { Write-Host "Esa IP ya esta en uso por $($chequeo.ClientId)" Start-Sleep -Seconds 3 }

## validacion para checar si el rango de la ip final es acertado
	$regexRango = "^192\.168\.100\.([5-9]\d|1[0-4]\d|150)$"
	if ($ip -match $regexRango){
		Write-Host "Ip correcta :D" -ForegroundColor Green
		Start-Sleep -Seconds 5
	}
	else {
		Write-Host "Rango Incorrecto :///" -ForegroundColor Red
		Start-Sleep -Seconds 5
	}

## validacion para checar si la ip final es mayor q la ip inicial
	
	$ipicv = [int]($ipi -split'\.')[3]
	$ipfcv = [int]($ipf -split'\.')[3]

	if ($ipfcv -gt $ipicv) {
		$validacion = $true
	}
	else {
		$validacion = $false
	}	

}




Function mostrarRedes {
	Write-Host "Equipos conectados:" -ForegroundColor Yellow
	$leases = Get-DhcpServerv4Lease -ScopeId 192.168.100.0 -ErrorAction SilentlyContinue
	Start-Sleep -Seconds 3

	if ($leases) {
        	$leases | Select-Object IPAddress, ClientId, HostName, LeaseExpiryTime | Format-Table -AutoSize
		Start-Sleep -Seconds 5
    	} else {
        	Write-Host "No hay concesiones activas o el Scope no existe." -ForegroundColor Gray
		Start-Sleep -Seconds 3
    	}
}

Function configRed{


	Add-DhcpServerv4Scope -Name "Rango" `
                      -StartRange 192.168.100.50 `
                      -EndRange 192.168.100.150 `
                      -SubnetMask 255.255.255.0 `
                      -State Active

	Set-DhcpServerv4Scope -ScopeId $scopeId -LeaseDuration 1.00:00:00 		     # 1 día

}


Function instalacionDHCP{
	Install-WindowsFeature -Name DHCP -IncludeManagementTools
	Start-Sleep -Seconds 3
    	Write-Host "DHCP ha sido instalado correctamente :D" -ForegroundColor Green
}

Function desinstalarDHCP {
    	Write-Host "Desinstalando DHCP... Por favor espere." -ForegroundColor Yellow
    	Uninstall-WindowsFeature -Name DHCP -IncludeManagementTools
	Start-Sleep -Seconds 3
    	Write-Host "DHCP ha sido desinstalado correctamente ;)" -ForegroundColor Green
}


Function configScope{
	param ( [string] $nombre,
	[string] $rangoIni,
	[string] $rangoFin,
	[string] $masc,
	[int] $duracion
	)

	$scopeId = "192.168.10.0"

    Add-DhcpServerv4Scope -Name $nombre `
	-StartRange $rangoIni `
        -EndRange $rangoFin `
        -SubnetMask $masc `
	-State Active

	Set-DhcpServerv4OptionValue -ScopeId $scopeId -OptionId 3 -Value 192.168.10.1        # gateway
	Set-DhcpServerv4OptionValue -ScopeId $scopeId -OptionId 6 -Value 8.8.8.8             # dns
	

	$dconv = New-TimeSpan -Days $duracion
	Set-DhcpServerv4Scope -ScopeId $rangoIni -LeaseDuration $dconv

	write-host "Scope agregado con exito" -ForegroundColor Green
	Start-Sleep -Seconds 3
}

#	 MAIN

do {

clear-host
write-host "------------------------" -ForegroundColor Blue
write-host "Menu" -ForegroundColor Blue
write-host "1- Verificar la instalacion DHCP"
write-host "2- Instalacion silenciosa"
write-host "3- Monitoreo IPs"
write-host "4- Ver configuracion de Scope"
write-host "5- Reiniciar servicio DHCP"
write-host "6- Salir" -ForegroundColor Red
write-host "------------------------" -ForegroundColor Blue
$opc = read-host "Elija su opcion"


switch($opc) {

## opcion 1

	1 {
		$dhcpEstado= Get-WindowsFeature -Name DHCP

		if ($dhcpEstado.InstallState -eq "Installed"){
			write-host "DHCP ya se encuentra instalado :)" -ForegroundColor Green
			Start-Sleep -Seconds 4
		}
		else {
			write-host "DHCP no se encuentra instalado :o" -ForegroundColor Red
			$opcc = read-host "Desea instalarlo? (S/N)" 
			if ($opcc -eq "S"){
				instalacionDHCP
			}
			else {
				write-host "Entendido, regresando al menu..."
				Start-Sleep -Seconds 5
			}	
		}
	}

## opcion 2

	2 {
		$opc = Read-Host "Seguro que desea instalar? (s/n)"
		if ($opc -eq "s"){
			write-host "Verificando estado..."
			if ((Get-WindowsFeature DHCP).Installed){
				write-host "DHCP ya se encuentra instalado :)" -ForegroundColor Green
				$opc = Read-Host  "Desea volverlo a instalar? (s/n)" 
				if ($opc -eq "s"){
					desinstalarDHCP
					write-host "Iniciando instalacion..."
					instalacionDHCP
					Start-Sleep -Seconds 3
				}
				else {
					write-host "Entendido, regresando al menu..."
					Start-Sleep -Seconds 3
				}
			}
			else {
				write-host "Iniciando instalacion..."
				instalacionDHCP
				Start-Sleep -Seconds 3
			}
		}
		else {
			write-host "Entendido, regresando al menu..."
			Start-Sleep -Seconds 3
		}

	}

### opcion 3

	3 {
		$estadoServicio = Get-Service -Name DHCPServer -ErrorAction SilentlyContinue
		write-host "Verificando estado..."
			if ($estadoServicio.Status -eq "Running"){
				mostrarRedes
				Start-Sleep -Seconds 3
			}
			else {
				Write-Host "El servicio DHCP no está instalado en este equipo." -ForegroundColor Red
				Start-Sleep -Seconds 2
        			return
			}
	}

## opcion 4

	4 {
	do {
		clear-host
		write-host "------------------------" -ForegroundColor Green
		write-host "Menu Scope" -ForegroundColor Green
		write-host "1- Ver Scopes activos"
		write-host "2- Agregar Scope"
		write-host "3- Eliminar Scope"
		write-host "4- Volver al menu principal" -ForegroundColor Yellow
		write-host "------------------------" -ForegroundColor Green
		$opcScope = read-host "Elija su opcion"

		switch($opcScope) {

			1 {	
				$scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue

				if ($null -eq $scopes) {
	    				Write-Host "No hay scopes creados actualmente." -ForegroundColor Red
					Start-Sleep -Seconds 5
				} else {
					$conteo = ($scopes).Count
	    				Write-Host "Se encontraron $conteo scopes activos:" -ForegroundColor Green
	    				Get-DhcpServerv4Scope | Select-Object ScopeId, Name, StartRange, EndRange, SubnetMask, State | Format-Table -AutoSize
					Start-Sleep -Seconds 5
				}
			}

			2 {
				$n = Read-Host "Nombre"
                		$i = Read-Host "Inicio"
				validarIP -ip $i
                		$f = Read-Host "Fin"
				validarIP2 -ipi $i -ipf $f
                		$m = Read-Host "Mascara"
				$d = Read-Host "Duracion (en días, ejemplo: 1)"

				configScope -nombre $n -rangoIni $i -rangoFin $f -masc $m -duracion $d
				Start-Sleep -Seconds 3
			}

			3 {
				$nscope = read-host "Escriba el ID del Scope que desea eliminar"
				Remove-DhcpServerv4Scope -ScopeId $nscope -Force
				Start-Sleep -Seconds 3
			}

			4 {
				write-host "Entendido, regresando al menu principal..."
				Start-Sleep -Seconds 3
			}
		}
	} while ($opc -ne 4)
	}

## opcion 5

	5 {
		write-host "Reiniciando servicio..." -ForegroundColor Yellow
		Restart-Service DHCPServer 
		Start-Sleep -Seconds 5
	}



## opcion 6

	6 { 
            Write-Host "Saliendo..." -ForegroundColor Yellow
            return 
        }
    }
} while ($opc -ne 6)
