function instalarSSH {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    Get-NetTCPConnection -LocalPort 22 -ErrorAction SilentlyContinue
    Start-Service sshd
    Set-Service -Name sshd -StartupType 'Automatic'
    if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow
    }
}
function verNiveldeAcceso {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    
    if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "NIVEL DE ACCESO: [ ADMINISTRADOR / ELEVADO ]" -ForegroundColor Green -BackgroundColor Black
    } else {
        Write-Host "NIVEL DE ACCESO: [ USUARIO ESTÁNDAR / RESTRINGIDO ]" -ForegroundColor Yellow
    }
}

function admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
