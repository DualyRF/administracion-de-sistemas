$Old = Get-DnsServerResourceRecord -ZoneName "zona.com" -Name "nombre" -RRType "A"
$New = $Old.Clone()
$New.RecordData.IPv4Address = [System.Net.IPAddress]::Parse("nueva.ip")
Set-DnsServerResourceRecord -OldInputObject $Old -NewInputObject $New -ZoneName "zona.com"   