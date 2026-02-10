Function validarRango{
	param ([string] $ip)
	
	$regexRango = "^192\.168\.100\.([5-9]\d|1[0-4]\d|150)$"
	if ($ip -match $regexRango){
		Write-Host "Ip correcta :D" -ForegroundColor Green
	}
	else {
		Write-Host "Rango Incorrecto :///" -ForegroundColor Red
	}
}


#	 MAIN

# declaracion de variables 
$ipEntrada = Read-Host "Ingresa tu IP"

if ($ipEntrada -match "^[0-9]+\.+[0-9]+\.[0-9]+\.[0-9]+$"){
	validarRango -ip $ipEntrada
}
else{
	Write-Host "Ip invalida" -ForegroundColor Yellow
}