# ============================================================
# Funciones para gestion de los servidores HTTP
# ============================================================

# ----------------
# Generales
# ----------------

function printWarn {
    param([string]$msg)
    Write-Host "[!] $msg" -ForegroundColor Yellow
}

function printOK {
    param([string]$msg)
    Write-Host "[+] $msg" -ForegroundColor Green
}

function printError {
    param([string]$msg)
    Write-Host "[x] $msg" -ForegroundColor Red
}

function printInfo {
    param([string]$msg)
    Write-Host "[i] $msg" -ForegroundColor Cyan
}

# ----------------
# Pedir puerto al usuario + validacion de que sea un puerto usable lol
# ----------------
function pedirPuerto {
    param([int]$default = 80)

    while ($true) {
        $input = Read-Host "Puerto de escucha (default: $default, rango: 1024-65535)"

        # Si presiona Enter sin escribir, usar default
        if ([string]::IsNullOrWhiteSpace($input)) {
            $puerto = $default
        } else {
            # Validar que sea numero
            if ($input -notmatch '^\d+$') {
                printWarn "Ingresa solo numeros."
                continue
            }
            $puerto = [int]$input
        }

        # Rango valido (evitar puertos del sistema < 1024, excepto 80)
        if ($puerto -ne 80 -and ($puerto -lt 1024 -or $puerto -gt 65535)) {
            printWarn "Puerto fuera de rango. Usa 80 o entre 1024-65535."
            continue
        }

        if (validarPuerto -puerto $puerto) {
            return $puerto
        } else {
            printWarn "Elige otro puerto."
        }
    }
}

# ----------------
# Retorna $true si esta libre, $false si ocupado
# ----------------
function validarPuerto {
    param([int]$puerto)

    # Puertos reservados del sistema que no se deben usar
    $reservados = @(22, 23, 25, 443, 3306, 3389, 5432, 8443)
    if ($reservados -contains $puerto) {
        printWarn "El puerto $puerto esta reservado para otro servicio."
        return $false
    }

    # Verificar si el puerto esta en uso
    $enUso = Get-NetTCPConnection -LocalPort $puerto -ErrorAction SilentlyContinue
    if ($enUso) {
        # Identificar que proceso lo usa (informativo)
        $proceso = Get-Process -Id $enUso[0].OwningProcess -ErrorAction SilentlyContinue
        printWarn "Puerto $puerto ocupado por: $($proceso.ProcessName) (PID: $($enUso[0].OwningProcess))"
        return $false
    }

    return $true
}

# ----------------
# Configuracion del firewall, cierra el puerto default (80) y abre el que pide el usuario
# ----------------
function configurarFirewall {
    param(
        [int]$puertNuevo,
        [int]$puertoViejo = 80,
        [string]$nombreServicio = "HTTP"
    )

    printInfo "Configurando firewall..."

    # Eliminar regla vieja si existe
    Remove-NetFirewallRule -DisplayName "HTTP-$nombreServicio-$puertoViejo" -ErrorAction SilentlyContinue

    # Crear nueva regla para el puerto elegido
    New-NetFirewallRule `
        -DisplayName "HTTP-$nombreServicio-$puertNuevo" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $puertNuevo `
        -Action Allow | Out-Null

    printOK "Firewall: puerto $puertNuevo abierto."

    # Si el puerto viejo era 80 y el nuevo no es 80, cerrar el 80
    if ($puertoViejo -eq 80 -and $puertNuevo -ne 80) {
        # Solo cerrar si ningun otro servicio lo necesita
        $reglas = Get-NetFirewallRule -DisplayName "HTTP-*-80" -ErrorAction SilentlyContinue
        if (-not $reglas) {
            New-NetFirewallRule `
                -DisplayName "BLOCK-HTTP-80" `
                -Direction Inbound `
                -Protocol TCP `
                -LocalPort 80 `
                -Action Block | Out-Null
            printOK "Firewall: puerto 80 bloqueado (no en uso)."
        }
    }
}


# ----------------
# Instalar apache con chocolatey
# ----------------
function instalarApache {
    param([int]$puerto)

    Clear-Host
    Write-Host "─── Instalacion de Apache HTTP Server ───" -ForegroundColor Magenta
    Write-Host ""

    # Verificar que Chocolatey este instalado
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        printInfo "Instalando Chocolatey (gestor de paquetes)..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
        # Recargar PATH para que choco este disponible
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    }

    # ── Consultar versiones disponibles dinamicamente ──
    printInfo "Consultando versiones disponibles de Apache..."

    # choco list apache-httpd --all-versions --limit-output
    # El formato de salida es: paquete|version
    $verOut = choco list apache-httpd --all-versions --limit-output 2>$null
    
    if (-not $verOut) {
        printWarn "No se encontro 'apache-httpd' en Chocolatey. Buscando alternativas..."
        $verOut = choco list apache --all-versions --limit-output 2>$null
    }

    # Parsear versiones (formato: "apache-httpd|2.4.62")
    $versiones = @()
    foreach ($linea in $verOut) {
        if ($linea -match '\|') {
            $partes = $linea -split '\|'
            if ($partes.Length -ge 2) {
                $versiones += $partes[1].Trim()
            }
        }
    }

    if ($versiones.Count -eq 0) {
        printError "No se pudieron obtener versiones. Verifica conexion a internet."
        return
    }

    # Mostrar versiones: la primera es la mas reciente (desarrollo/latest)
    # La segunda o la ultima LTS seria la estable
    Write-Host "Versiones disponibles:" -ForegroundColor Cyan
    Write-Host "  1. $($versiones[0])  [Mas reciente]"
    if ($versiones.Count -ge 2) {
        Write-Host "  2. $($versiones[1])  [Anterior/Estable]"
    }
    if ($versiones.Count -ge 3) {
        Write-Host "  3. $($versiones[-1]) [Mas antigua disponible]"
    }
    Write-Host ""

    $selVer = Read-Host "Selecciona version (1/2/3)"
    $versionElegida = switch ($selVer) {
        "1" { $versiones[0] }
        "2" { if ($versiones.Count -ge 2) { $versiones[1] } else { $versiones[0] } }
        "3" { if ($versiones.Count -ge 3) { $versiones[-1] } else { $versiones[0] } }
        default { $versiones[0] }
    }

    printInfo "Instalando Apache $versionElegida..."
    choco install apache-httpd --version=$versionElegida --yes --no-progress 2>&1 | Tee-Object -Variable chocoOutput | Out-Null

    if ($LASTEXITCODE -ne 0) {
        printError "Error en la instalacion. Salida: $chocoOutput"
        return
    }

    printOK "Apache $versionElegida instalado."

    # ── Configurar puerto en httpd.conf ──
    # Apache en Windows instala en C:\tools\apache24\ o C:\Apache24\
    $apachePath = @("C:\tools\Apache24", "C:\Apache24", "C:\Program Files\Apache Software Foundation\Apache2.4") |
                  Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $apachePath) {
        printWarn "No se encontro directorio de Apache. Ajusta la ruta manualmente."
    } else {
        $httpdConf = "$apachePath\conf\httpd.conf"
        printInfo "Editando $httpdConf para usar puerto $puerto (elegido)..."

        # Cambiar "Listen 80" por el puerto elegido
        (Get-Content $httpdConf) -replace 'Listen 80', "Listen $puerto" |
            Set-Content $httpdConf

        # Cambiar ServerName tambien (evita warnings)
        (Get-Content $httpdConf) -replace '#ServerName www.example.com:80', "ServerName localhost:$puerto" |
            Set-Content $httpdConf

        printOK "Puerto $puerto configurado en httpd.conf"

        # ----------------
        # Llamando a las funciones de seguridad y configuracion general
        # ----------------

        # ── Seguridad: ocultar version en Apache ──
        aplicarSeguridadApache -apachePath $apachePath

        # ── Crear index.html ──
        CrearHTML `
            -rutaWeb "$apachePath\htdocs" `
            -servicio "Apache HTTP Server" `
            -version $versionElegida `
            -puerto $puerto

        # ── Firewall ──
        configurarFirewall -puertNuevo $puerto -puertoViejo 80 -nombreServicio "Apache"

        # ── Iniciar Apache como servicio ──
        $apacheService = "$apachePath\bin\httpd.exe"
        if (Test-Path $apacheService) {
            & $apacheService -k install -n "Apache24" | Out-Null
            Start-Service Apache24 -ErrorAction SilentlyContinue
            printOK "Apache activo en http://localhost:$puerto"
        }
    }
}

# ----------------
# Instalar IIS
# ----------------
function instalarIIS {
    param([int]$puerto)

    Clear-Host
    Write-Host "─── Instalacion de IIS ───" -ForegroundColor Magenta
    Write-Host ""

    # IIS no tiene versiones elegibles manualmente (depende del Windows)
    # Pero podemos mostrar la version del sistema y la de IIS disponible
    $winVer = (Get-WmiObject Win32_OperatingSystem).Caption
    printInfo "Sistema: $winVer"

    # Determinar version IIS segun Windows
    $iisVersion = switch -Wildcard ($winVer) {
        "*Windows 11*"     { "10.0" }
        "*Windows 10*"     { "10.0" }
        "*Server 2022*"    { "10.0" }
        "*Server 2019*"    { "10.0" }
        "*Server 2016*"    { "10.0" }
        "*Server 2012*"    { "8.5"  }
        default             { "10.0" }
    }

    Write-Host ""
    Write-Host "Version IIS disponible para tu sistema: $iisVersion" -ForegroundColor Cyan
    Write-Host "(IIS se instala segun la version de Windows, no se puede elegir otra)"
    Write-Host ""

    $confirmar = Read-Host "¿Instalar IIS $iisVersion en puerto $puerto? (s/n)"
    if ($confirmar -ne 's') { return }

    # ── Instalacion ──
    printInfo "Instalando IIS..."

    # Instalar IIS con herramientas de administracion
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools -ErrorAction Stop | Out-Null

    # Instalar modulos de seguridad adicionales
    Install-WindowsFeature -Name Web-Security | Out-Null         # Request Filtering
    Install-WindowsFeature -Name Web-IP-Security | Out-Null      # Restricciones IP

    printOK "IIS instalado."

    # ── Importar modulo WebAdministration (para manejar IIS con PS) ──
    Import-Module WebAdministration -ErrorAction Stop

    # ── Cambiar puerto ──
    printInfo "Configurando puerto $puerto..."

    # Limpiar binding por defecto (*:80:) y agregar el nuevo
    Remove-WebBinding -Name "Default Web Site" -BindingInformation "*:80:" -ErrorAction SilentlyContinue
    New-WebBinding -Name "Default Web Site" -Protocol "http" -Port $puerto -IPAddress "*"

    printOK "Puerto configurado: $puerto"

    # ── Seguridad: ocultar version del servidor ──
    SeguridadIIS

    # ── Firewall ──
    configurarFirewall -puertNuevo $puerto -puertoViejo 80 -nombreServicio "IIS"

    # ── Permisos: usuario dedicado para IIS ──
    Configurar-UsuarioIIS

    # ── Crear index.html ──
    CrearHTML -rutaWeb "C:\inetpub\wwwroot" -servicio "IIS" -version $iisVersion -puerto $puerto

    # ── Iniciar servicio ──
    Start-Service W3SVC
    Set-Service W3SVC -StartupType Automatic

    printOK "IIS activo en http://localhost:$puerto"
    Write-Host ""

    # Verificar con curl
    Start-Sleep -Seconds 2
    printInfo "Verificando headers HTTP..."
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:$puerto" -Method HEAD -UseBasicParsing
        Write-Host "Headers recibidos:" -ForegroundColor Cyan
        $response.Headers | Format-Table -AutoSize
    } catch {
        printWarn "No se pudo verificar automaticamente. Usa: curl -I http://localhost:$puerto"
    }
}

# ----------------
# Instalar simple-http-server con pip/cargo
# ----------------
function instalarSSH {
    param([int]$puerto)

    Clear-Host
    Write-Host "─── Instalacion de simple-http-server ───" -ForegroundColor Magenta
    Write-Host ""

    # simple-http-server es un binario en Rust (cargo)
    # Alternativa mas simple: usar Python http.server o http-server (npm)
    # Aqui usamos http-server de Node.js/npm por ser mas comun

    # Verificar Node.js
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        printInfo "Node.js no encontrado. Instalando via Chocolatey..."
        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
            # Instalar Chocolatey primero
            Set-ExecutionPolicy Bypass -Scope Process -Force
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        }
        choco install nodejs --yes --no-progress | Out-Null
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    }

    # Consultar versiones disponibles de http-server en npm
    printInfo "Consultando versiones de http-server en npm..."
    $verJson = npm view http-server versions --json 2>$null | ConvertFrom-Json

    if (-not $verJson) {
        printError "No se pudieron obtener versiones de npm."
        return
    }

    # Mostrar ultimas versiones
    $verArray = $verJson | Select-Object -Last 5
    Write-Host "Versiones disponibles (ultimas 5):" -ForegroundColor Cyan
    for ($i = 0; $i -lt $verArray.Count; $i++) {
        $etiqueta = if ($i -eq ($verArray.Count - 1)) { "[Latest]" } elseif ($i -eq 0) { "[LTS/Estable]" } else { "" }
        Write-Host "  $($i+1). $($verArray[$i]) $etiqueta"
    }
    Write-Host ""

    $selVer = Read-Host "Selecciona version (1-$($verArray.Count))"
    $idx = [int]$selVer - 1
    if ($idx -lt 0 -or $idx -ge $verArray.Count) { $idx = $verArray.Count - 1 }
    $versionElegida = $verArray[$idx]

    printInfo "Instalando http-server@$versionElegida globalmente..."
    npm install -g http-server@$versionElegida --silent 2>&1 | Out-Null

    if ($LASTEXITCODE -ne 0) {
        printError "Error instalando http-server."
        return
    }

    printOK "http-server $versionElegida instalado."

    # Directorio de contenido web
    $webRoot = "C:\inetpub\http-server"
    if (-not (Test-Path $webRoot)) { New-Item -ItemType Directory -Path $webRoot -Force | Out-Null }

    # Crear index.html
    CrearHTML -rutaWeb $webRoot -servicio "simple-http-server" -version $versionElegida -puerto $puerto

    # Firewall
    configurarFirewall -puertNuevo $puerto -puertoViejo 8080 -nombreServicio "SHS"

    # Registrar como tarea programada (para que arranque como servicio)
    printInfo "Registrando http-server como servicio (Tarea Programada)..."
    $accion = New-ScheduledTaskAction `
        -Execute "cmd.exe" `
        -Argument "/c http-server `"$webRoot`" -p $puerto --silent"

    $trigger = New-ScheduledTaskTrigger -AtStartup
    $settings = New-ScheduledTaskSettingsSet -RestartOnIdle

    Register-ScheduledTask `
        -TaskName "SimpleHTTPServer-$puerto" `
        -Action $accion `
        -Trigger $trigger `
        -RunLevel Highest `
        -Force | Out-Null

    # Ejecutar ahora
    Start-ScheduledTask -TaskName "SimpleHTTPServer-$puerto"

    printOK "simple-http-server activo en http://localhost:$puerto"
}

# ----------------
# Oculta los comentarios peligrosos jajaj dependiendo del servidor
# ----------------

function SeguridadIIS {
    printInfo "Aplicando configuracion de seguridad en IIS..."

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # 1. Ocultar header "Server: Microsoft-IIS/X.X"
    try {
        Set-WebConfigurationProperty `
            -PSPath "MACHINE/WEBROOT/APPHOST" `
            -Filter "system.webServer/security/requestFiltering" `
            -Name "removeServerHeader" `
            -Value $true
        printOK "Header 'Server' ocultado."
    } catch {
        printWarn "No se pudo ocultar header Server (puede requerir IIS 10+)."
    }

    # 2. Eliminar header "X-Powered-By"
    try {
        Remove-WebConfigurationProperty `
            -PSPath "MACHINE/WEBROOT/APPHOST" `
            -Filter "system.webServer/httpProtocol/customHeaders" `
            -Name "." `
            -AtElement @{name='X-Powered-By'} `
            -ErrorAction SilentlyContinue
        printOK "Header 'X-Powered-By' eliminado."
    } catch {
        printWarn "Header X-Powered-By no encontrado (puede que ya no existiera)."
    }

    # 3. Agregar headers de seguridad
    # X-Frame-Options: evita Clickjacking (que tu pagina sea metida en un iframe)
    Add-WebConfigurationProperty `
        -PSPath "MACHINE/WEBROOT/APPHOST" `
        -Filter "system.webServer/httpProtocol/customHeaders" `
        -Name "." `
        -Value @{name='X-Frame-Options'; value='SAMEORIGIN'} `
        -ErrorAction SilentlyContinue

    # X-Content-Type-Options: evita que el navegador "adivine" el tipo de archivo
    Add-WebConfigurationProperty `
        -PSPath "MACHINE/WEBROOT/APPHOST" `
        -Filter "system.webServer/httpProtocol/customHeaders" `
        -Name "." `
        -Value @{name='X-Content-Type-Options'; value='nosniff'} `
        -ErrorAction SilentlyContinue

    # 4. Deshabilitar metodos HTTP peligrosos (TRACE, TRACK)
    # TRACE permite a atacantes robar cookies mediante Cross-Site Tracing (XST)
    Add-WebConfigurationProperty `
        -PSPath "MACHINE/WEBROOT/APPHOST" `
        -Filter "system.webServer/security/requestFiltering/verbs" `
        -Name "." `
        -Value @{verb='TRACE'; allowed='false'} `
        -ErrorAction SilentlyContinue

    Add-WebConfigurationProperty `
        -PSPath "MACHINE/WEBROOT/APPHOST" `
        -Filter "system.webServer/security/requestFiltering/verbs" `
        -Name "." `
        -Value @{verb='TRACK'; allowed='false'} `
        -ErrorAction SilentlyContinue

    printOK "Seguridad IIS configurada."
}

function SeguridadApache {
    param([string]$apachePath)

    printInfo "Aplicando seguridad en Apache..."
    $httpdConf = "$apachePath\conf\httpd.conf"

    # Ocultar version: ServerTokens Prod (solo muestra "Apache", no la version)
    # ServerSignature Off (quita la firma del pie de pagina de errores)
    $seguridad = @"

# === SEGURIDAD: Ocultar informacion del servidor ===
ServerTokens Prod
ServerSignature Off

# Deshabilitar metodos peligrosos
<LimitExcept GET POST HEAD>
    Require all denied
</LimitExcept>

# Headers de seguridad
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
"@

    Add-Content -Path $httpdConf -Value $seguridad
    printOK "Seguridad Apache configurada."
}

# ----------------
# Crear una pagina html personalizada
# ----------------
function CrearHTML {
    param(
        [string]$rutaWeb,      # Ej: C:\inetpub\wwwroot
        [string]$servicio,     # Ej: IIS
        [string]$version,      # Ej: 10.0
        [int]$puerto           # Ej: 8080
    )

    $contenido = @"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>$servicio - Activo</title>
    <style>
        body { font-family: Arial, sans-serif; background: #1a1a2e; color: #eee; 
               display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .card { background: #16213e; padding: 40px; border-radius: 10px; 
                border-left: 5px solid #0f3460; text-align: center; }
        h1 { color: #e94560; }
        .info { background: #0f3460; padding: 10px; border-radius: 5px; margin: 10px 0; }
    </style>
</head>
<body>
    <div class="card">
        <h1>Servidor Activo</h1>
        <div class="info">Servidor: <strong>$servicio</strong></div>
        <div class="info">Version: <strong>$version</strong></div>
        <div class="info">Puerto: <strong>$puerto</strong></div>
    </div>
</body>
</html>
"@

    # Crear directorio si no existe
    if (-not (Test-Path $rutaWeb)) {
        New-Item -ItemType Directory -Path $rutaWeb -Force | Out-Null
    }

    $contenido | Out-File -FilePath "$rutaWeb\index.html" -Encoding UTF8
    printOK "index.html creado en $rutaWeb"
}

# ----------------
# Funcion "principal"
# ----------------
function InstalarHTTP {
    Clear-Host
    Write-Host ""
    Write-Host "------------------------------------------------" -ForegroundColor Blue
    Write-Host "            GESTION SERVIDOR HTTPS              " -ForegroundColor Blue
    Write-Host "------------------------------------------------" -ForegroundColor Blue
    Write-Host "  1. IIS  (nativo Windows)"
    Write-Host "  2. Apache HTTP Server"
    Write-Host "  3. simple-http-server (Node.js)"
    Write-Host "  0. Volver"
    Write-Host "------------------------------------------------" -ForegroundColor Blue
    Write-Host ""

    $s = Read-Host "Servidor"

    if ($s -eq "0") { return }
    if ($s -notin @("1","2","3")) {
        printWarn "Opcion no valida."
        return
    }

    # Pedir puerto DESPUeS de elegir servidor
    Write-Host ""
    $puerto = pedirPuerto -default 80

    switch ($s) {
        "1" { 
            instalarIIS    -puerto $puerto 
        }
        "2" { 
            instalarApache -puerto $puerto 
        }
        "3" { 
            instalarSSH -puerto $puerto 
        }
    }
}

