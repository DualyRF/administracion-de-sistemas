$Old = Get-DnsServerResourceRecord -ZoneName "prueba.com" -Name "pruebaa" -RRType "A"
$New = $Old.Clone()
$New.RecordData.IPv4Address = [System.Net.IPAddress]::Parse("nueva.ip")
Set-DnsServerResourceRecord -OldInputObject $Old -NewInputObject $New -ZoneName "prueba.com"



Import-CSV "C:PSNewDnsRecords.txt" | %{
Add-DNSServerResourceRecordA -ZoneName woshub.com -Name $_."HostName" -IPv4Address $_."IPAddress"
}