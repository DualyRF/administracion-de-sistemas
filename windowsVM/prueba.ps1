Write-Host "Abriendo puerto 53 para consultas DNS..." -ForegroundColor Cyan

# Esta regla abre el puerto 53 para TCP y UDP (ambos necesarios para DNS)
New-NetFirewallRule -DisplayName "DNS-UDP-In" -Direction Inbound -LocalPort 53 -Protocol UDP -Action Allow -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "DNS-TCP-In" -Direction Inbound -LocalPort 53 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue

Write-Host "Puerto 53 abierto." -ForegroundColor Green

#activar el puerto 53
Get-NetTCPConnection -LocalPort 53 -ErrorAction SilentlyContinue

# copy para regresar la configuracion de red a dhcp para poder usar git
# netsh interface ip set address "Ethernet" dhcp
# netsh interface ip set dns "Ethernet" dhcp

# Resolve-DnsName -Name www.jotelulu.com

# Esto cambia la IP del Ethernet 2 a la .1
Get-NetIPInterface -InterfaceAlias "Ethernet 2" | New-NetIPAddress -IPAddress 200.200.200.1 -PrefixLength 27 -DefaultGateway 200.200.200.1

# Desactiva el firewall para que el ping y el DNS pasen sin problemas
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False


# Borramos cualquier IP previa del Ethernet 2 y ponemos la buena
Remove-NetIPAddress -InterfaceAlias "Ethernet 2" -Confirm:$false -ErrorAction SilentlyContinue
New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress 200.200.200.1 -PrefixLength 27 -DefaultGateway 200.200.200.1

# Esto quita el DHCP y le regresa su identidad
Set-NetIPInterface -InterfaceAlias "Ethernet 2" -DHCP Disabled
Netsh interface ip set address name="Ethernet 2" static 200.200.200.1 255.255.255.224 200.200.200.1


Disable-NetAdapter -Name "Ethernet" -Confirm:$false
Enable-NetAdapter -Name "Ethernet"
