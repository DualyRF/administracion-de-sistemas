function agregarRegistro {
    param(
        [string]$name,
        [string]$zoneName,
        [string]$ip
    )

    Add-DNSServerResourceRecordA -Name $name -ZoneName $zoneName  -AllowUpdateAny -IPv4Address $ip
}

	$n = Read-Host "Dame el nombre del registro"
	$zn = Read-Host "Dame el nombre de la zona"
	$i = Read-Host "Dame la IP para la zona"
	agregarRegistro -name $n, -zoneName $zn, -ip $i