$ipi = Read-Host "IP inicial"
$ipf = Read-Host "IP final"

## validacion para checar si la ip final es mayor q la ip inicial
	
	$ipicv = [int]($ipi -split'\.')[3]
	$ipfcv = [int]($ipf -split'\.')[3]

	if ($ipfcv -gt $ipicv) {
		$validacion = $true
		write-host "ip correcta"
	}
	else {
		$validacion = $false
		write-host "ip incorrecta"
	}