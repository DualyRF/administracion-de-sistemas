$Old = Get-DnsServerResourceRecord -ZoneName "prueba.com.dns" -Name "prueba.com" -RRType "A"
$New = $Old.Clone()
$New.RecordData.IPv4Address = [System.Net.IPAddress]::Parse("nueva.ip")
Set-DnsServerResourceRecord -OldInputObject $Old -NewInputObject $New -ZoneName "prueba.com.dns"   