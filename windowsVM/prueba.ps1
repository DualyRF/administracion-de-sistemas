Write-Host "Abriendo puerto 53 para consultas DNS..." -ForegroundColor Cyan

# Esta regla abre el puerto 53 para TCP y UDP (ambos necesarios para DNS)
New-NetFirewallRule -DisplayName "DNS-UDP-In" -Direction Inbound -LocalPort 53 -Protocol UDP -Action Allow -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "DNS-TCP-In" -Direction Inbound -LocalPort 53 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue

Write-Host "Puerto 53 abierto." -ForegroundColor Green

Get-NetTCPConnection -LocalPort 53 -ErrorAction SilentlyContinue

# copy para regresar la configuracion de red a dhcp para poder usar git
# netsh interface ip set address "Ethernet" dhcp
# netsh interface ip set dns "Ethernet" dhcp

# Resolve-DnsName -Name www.jotelulu.com