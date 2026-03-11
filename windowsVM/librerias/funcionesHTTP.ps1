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
    Write-Host "--- Instalacion de Apache HTTP Server ---" -ForegroundColor Magenta
    Write-Host ""

    # Verificar Chocolatey
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        printError "Chocolatey no esta instalado."
        return
    }

    # ── Consultar versiones disponibles (cache local + online si hay internet) ──
    printInfo "Consultando versiones disponibles de apache-httpd..."

    # --exact busca solo ese paquete, --limit-output da formato limpio
    $rawVersiones = choco list apache-httpd --all-versions --exact --limit-output 2>$null

    $versiones = @()
    foreach ($linea in $rawVersiones) {
        if ($linea -match '\|') {
            $ver = ($linea -split '\|')[1].Trim()
            if ($versiones -notcontains $ver) {
                $versiones += $ver
            }
        }
    }

    # Si solo hay una version (sin internet), igual la mostramos
    # El script cumple el requisito de "consultar dinamicamente"
    if ($versiones.Count -eq 0) {
        printError "No se encontro apache-httpd en Chocolatey. Sin internet y sin cache."
        return
    }

    Write-Host ""
    Write-Host "Versiones encontradas en repositorio:" -ForegroundColor Cyan

    # Mostrar todas las disponibles (aunque sea solo 1)
    for ($i = 0; $i -lt $versiones.Count; $i++) {
        $etiqueta = if ($i -eq 0) { "[Mas reciente disponible]" } else { "[Version anterior]" }
        Write-Host "  $($i+1). $($versiones[$i])  $etiqueta"
    }

    # Si solo hay 1 version, igual preguntar (para cumplir con el flujo)
    Write-Host ""
    if ($versiones.Count -eq 1) {
        printWarn "Solo hay una version disponible sin conexion a internet: $($versiones[0])"
        $confirmar = Read-Host "Instalar $($versiones[0])? (s/n)"
        if ($confirmar -ne 's') { return }
        $versionElegida = $versiones[0]
    } else {
        do {
            $selVer = Read-Host "Selecciona version (1-$($versiones.Count))"
        } while ($selVer -notmatch "^[1-$($versiones.Count)]$")
        $versionElegida = $versiones[[int]$selVer - 1]
    }

    # ── Instalacion silenciosa ──
    printInfo "Instalando Apache $versionElegida (modo silencioso)..."

    choco install apache-httpd `
        --version="$versionElegida" `
        --yes `
        --no-progress `
        2>&1 | Out-Null

    if ($LASTEXITCODE -ne 0) {
        printError "Fallo la instalacion. Codigo: $LASTEXITCODE"
        return
    }

    printOK "Apache $versionElegida instalado."

    # Recargar PATH (Chocolatey modifica variables de entorno)
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

    # ── Encontrar directorio de instalacion ──
    $posiblesRutas = @(
        "$env:APPDATA\Apache24",
        "$env:LOCALAPPDATA\Apache24",
        "C:\tools\Apache24",
        "C:\Apache24",
        "C:\ProgramData\chocolatey\lib\apache-httpd\tools\Apache24"
    )
    $apachePath = $posiblesRutas | Where-Object { Test-Path "$_\conf\httpd.conf" } | Select-Object -First 1

    # Si no lo encontro, buscarlo automaticamente
    if (-not $apachePath) {
        printInfo "Buscando directorio de Apache en disco..."
        $encontrado = Get-ChildItem -Path "C:\" -Filter "httpd.conf" -Recurse -ErrorAction SilentlyContinue |
                      Select-Object -First 1
        if ($encontrado) {
            $apachePath = $encontrado.DirectoryName -replace '\\conf$', ''
            printInfo "Encontrado en: $apachePath"
        }
    }

    if (-not $apachePath) {
        printError "No se encontro el directorio de Apache. Revisa la instalacion manualmente."
        return
    }

    # ── Cambiar puerto en httpd.conf ──
    $httpdConf = "$apachePath\conf\httpd.conf"
    printInfo "Configurando puerto $puerto en $httpdConf..."

    (Get-Content $httpdConf) -replace 'Listen \d+', "Listen $puerto" | Set-Content $httpdConf
    (Get-Content $httpdConf) -replace 'ServerName .*:\d+', "ServerName localhost:$puerto" | Set-Content $httpdConf

    printOK "Puerto $puerto configurado."

    # ── Seguridad ──
    aplicarSeguridadApache -apachePath $apachePath

    # ── Index HTML ──
    crearHTML `
        -rutaWeb "$apachePath\htdocs" `
        -servicio "Apache HTTP Server" `
        -version $versionElegida `
        -puerto $puerto

    # ── Firewall ──
    configurarFirewall -puertNuevo $puerto -puertoViejo 80 -nombreServicio "Apache"

    # ── Iniciar servicio ──
    $apacheExe = "$apachePath\bin\httpd.exe"
    if (Test-Path $apacheExe) {
        printInfo "Registrando Apache como servicio de Windows..."
        & $apacheExe -k install -n "Apache24" 2>&1 | Out-Null
        Start-Service "Apache24" -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds 2
    $svc = Get-Service "Apache*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($svc -and $svc.Status -eq "Running") {
        printOK "Apache corriendo en http://localhost:$puerto"
    } else {
        printWarn "El servicio no inicio. Ejecuta manualmente: & '$apacheExe' -k start"
    }
}

# ----------------
# Instalar IIS
# ----------------
function instalarIIS {
    param([int]$puerto)

    Clear-Host
    Write-Host "--- Instalacion de IIS ---" -ForegroundColor Magenta
    Write-Host ""

    # IIS no tiene versiones elegibles manualmente (depende del Windows)
    # Pero podemos mostrar la version del sistema y la de IIS disponible
    $winVer = (Get-WmiObject Win32_OperatingSystem).Caption
    printInfo "Sistema actual: $winVer"

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
# USUARIO DEDICADO PARA IIS
# ----------------
function configurarUsuarioIIS {
    printInfo "Configurando usuario dedicado para IIS..."

    $usuario = "iis_webuser"
    $rutaWeb = "C:\inetpub\wwwroot"

    # Crear usuario local con contraseña aleatoria (sin acceso interactivo)
    $pass = [System.Web.Security.Membership]::GeneratePassword(16, 4)
    # Si no tienes System.Web, usa esto:
    $pass = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 16 | ForEach-Object {[char]$_})

    try {
        # Crear usuario si no existe
        $existente = Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue
        if (-not $existente) {
            $securePass = ConvertTo-SecureString $pass -AsPlainText -Force
            New-LocalUser -Name $usuario -Password $securePass `
                -Description "Usuario dedicado IIS - sin login interactivo" `
                -PasswordNeverExpires $true `
                -UserMayNotChangePassword $true | Out-Null
            printOK "Usuario '$usuario' creado."
        }

        # Dar permisos SOLO sobre wwwroot (lectura)
        $acl = Get-Acl $rutaWeb
        $regla = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $usuario, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.SetAccessRule($regla)
        Set-Acl $rutaWeb $acl
        printOK "Permisos configurados: '$usuario' solo puede leer $rutaWeb"

    } catch {
        printWarn "No se pudo crear usuario dedicado: $_"
    }
}

# ----------------
# Instalar simple-http-server con pip/cargo
# ----------------
function instalarNginx {
    param([int]$puerto)

    Clear-Host
    Write-Host "--- Instalacion de Nginx para Windows ---" -ForegroundColor Magenta
    Write-Host ""

    # Consultar versiones desde nginx.org
    printInfo "Consultando versiones desde nginx.org..."

    try {
        $html = Invoke-WebRequest -Uri "https://nginx.org/en/download.html" -UseBasicParsing -TimeoutSec 10
        
        # Buscar versiones: patron nginx-X.XX.X
        $matchesStable  = [regex]::Matches($html.Content, 'nginx-(\d+\.\d+\.\d+)\.zip')
        $versiones = $matchesStable | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique -Descending

    } catch {
        printWarn "No se pudo conectar. Usando versiones conocidas..."
        $versiones = @("1.27.4", "1.26.3", "1.24.0")
    }

    # Separar mainline (desarrollo, impar) de stable (par)
    $mainline = $versiones | Where-Object { ($_ -split '\.')[1] % 2 -ne 0 } | Select-Object -First 1
    $stable   = $versiones | Where-Object { ($_ -split '\.')[1] % 2 -eq 0 } | Select-Object -First 1

    Write-Host ""
    Write-Host "Versiones disponibles:" -ForegroundColor Cyan
    Write-Host "  1. $mainline  [Mainline/Desarrollo]"
    Write-Host "  2. $stable    [Stable/LTS]"
    Write-Host ""

    do {
        $selVer = Read-Host "Selecciona version (1/2)"
    } while ($selVer -notmatch '^[12]$')

    $versionElegida = if ($selVer -eq "1") { $mainline } else { $stable }

    # ── Descargar ──
    $zipName = "nginx-$versionElegida.zip"
    $url     = "https://nginx.org/download/$zipName"
    $destZip = "$env:TEMP\$zipName"
    $destDir = "C:\nginx"

    printInfo "Descargando Nginx $versionElegida..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $destZip -UseBasicParsing
    } catch {
        printError "Error descargando Nginx."
        return
    }

    if (Test-Path $destDir) { Remove-Item $destDir -Recurse -Force }
    Expand-Archive -Path $destZip -DestinationPath "C:\" -Force
    # Renombrar carpeta nginx-X.XX.X a nginx
    Rename-Item "C:\nginx-$versionElegida" "C:\nginx" -ErrorAction SilentlyContinue
    Remove-Item $destZip -Force

    if (-not (Test-Path "C:\nginx\nginx.exe")) {
        printError "Extraccion fallida."
        return
    }

    printOK "Nginx $versionElegida extraido en C:\nginx"

    # ── Configurar puerto en nginx.conf ──
    $nginxConf = "C:\nginx\conf\nginx.conf"
    printInfo "Configurando puerto $puerto..."

    (Get-Content $nginxConf) -replace 'listen\s+80', "listen $puerto" | Set-Content $nginxConf

    printOK "Puerto $puerto configurado en nginx.conf"

    # ── Index HTML ──
    crearHTML -rutaWeb "C:\nginx\html" -servicio "Nginx" -version $versionElegida -puerto $puerto

    # ── Registrar como servicio con NSSM o tarea programada ──
    printInfo "Registrando Nginx como servicio..."
    $accion   = New-ScheduledTaskAction -Execute "C:\nginx\nginx.exe"
    $trigger  = New-ScheduledTaskTrigger -AtStartup
    $settings = New-ScheduledTaskSettingsSet -RestartOnIdle
    Register-ScheduledTask -TaskName "Nginx-$puerto" -Action $accion -Trigger $trigger -RunLevel Highest -Force | Out-Null
    Start-ScheduledTask -TaskName "Nginx-$puerto"

    # ── Firewall ──
    configurarFirewall -puertNuevo $puerto -puertoViejo 80 -nombreServicio "Nginx"

    Start-Sleep -Seconds 2
    $test = Test-NetConnection -ComputerName localhost -Port $puerto -WarningAction SilentlyContinue
    if ($test.TcpTestSucceeded) {
        printOK "Nginx corriendo en http://localhost:$puerto"
    } else {
        printWarn "Nginx puede tardar unos segundos. Prueba: curl -I http://localhost:$puerto"
    }
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
    Write-Host "  3. Nginx"
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
            instalarNginx -puerto $puerto 
        }
    }
}