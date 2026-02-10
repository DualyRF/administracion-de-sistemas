Function validarRango{
	param ([string] $ip)
	
## validacion para checar si la ip esta ocupada

	$chequeo = Get-DhcpServerv4Lease -ScopeId 192.168.100.0 | Where-Object IPAddress -eq $ip
	if ($chequeo) { Write-Host "Esa IP ya esta en uso por $($chequeockLease.ClientId)" }

## validacion para checar si el rango de la ip es acertado
	$regexRango = "^192\.168\.100\.([5-9]\d|1[0-4]\d|150)$"
	if ($ip -match $regexRango){
		Write-Host "Ip correcta :D" -ForegroundColor Green
	}
	else {
		Write-Host "Rango Incorrecto :///" -ForegroundColor Red
	}
}

Function instalacionDHCP{
	Install-WindowsFeature -Name DHCP -IncludeManagementTools
}


#	 MAIN

clear-host
write-host "------------------------" -ForegroundColor Blue
write-host "Menu" 
write-host "1- Verificar la instalacion DHCP"
write-host "2- Instalación silenciosa"
write-host "3- Monitoreo IPs"
write-host "4- Ver configuración"
write-host "5- Reiniciar servicio DHCP"
write-host "6- Salir"
write-host "------------------------" -ForegroundColor Blue
$opc = read-host "Elija su opcion:"


switch($opc) {

## opcion 1

	1 {
		$dhcpEstado= Get-WindowsFeature -Name DHCP

		if ($dhcpEstado.InstallState -eq "Installed"){
			write-host "DHCP ya se encuentra instalado :)" -ForegroundColor Green
			write-host "Informacion actual: " -ForegroundColor Red
			get-DhcpServerv4Scope
		}
		else {
			write-host "DHCP no se encuentra instalado :o" -ForegroundColor Red
			$opcc = read-host "Desea instalarlo? (S/N)" 
			if ($opcc -eq "S"){
				instalacionDHCP
			}
			else {
				write-host "Entendido, regresando al menú..."
			}	
		}
	}

## opcion 2

	2 {
		write-host "Iniciando instalacion..."
		instalacionDHCP
	}

### opcion 3

	3 {
		$ipEntrada = Read-Host "Ingresa tu IP"

		if ($ipEntrada -match "^[0-9]+\.+[0-9]+\.[0-9]+\.[0-9]+$"){
		validarRango -ip $ipEntrada
		}
		else{
			Write-Host "Ip invalida" -ForegroundColor Yellow
		}
	}

## opcion 4

	4 {
		write-host "Configuracion actual:"  -ForegroundColor Yellow
	}

## opcion 5

	5 {
		write-host "Reiniciando servicio..." -ForegroundColor Yellow
		Restart-service dhcpserver
	}

## opcion 6

	6 {
		write-host "Saliendo..."  -ForegroundColor Yellow; exit
	}

}
