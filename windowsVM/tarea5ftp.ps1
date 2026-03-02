# -----------------------------------------------------------------------------
#  CONFIGURACION GLOBAL
# -----------------------------------------------------------------------------
$FTP_ROOT      = "C:\FTP"
$GENERAL_PATH  = "$FTP_ROOT\general"
$REPROB_PATH   = "$GENERAL_PATH\reprobados"
$RECURS_PATH   = "$GENERAL_PATH\recursadores"
$SITE_NAME     = "MiFTP"
$FTP_PORT      = 21
$GROUPS        = @("reprobados", "recursadores")

# -----------------------------------------------------------------------------
#  FUNCIONES DE UTILIDAD
# -----------------------------------------------------------------------------

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info","OK","Warn","Error")][string]$Level = "Info"
    )
    $color = @{ Info = "White"; OK = "Green"; Warn = "Yellow"; Error = "Red" }
    $texto = @{ Info = "[INFO]"; OK = "[ OK ]"; Warn = "[WARN]"; Error = "[ERR ]" }
    Write-Host "$(Get-Date -Format 'HH:mm:ss') $($texto[$Level]) $Message" -ForegroundColor $color[$Level]
}

function titulos {
    param([string]$Title)
    Write-Host ""
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
}

function confirmaciones {
    param([string]$Question)
    $r = Read-Host "$Question (s/n)"
    return $r -match '^[sS]$'
}

# -----------------------------------------------------------------------------
#  INSTALACION IDEMPOTENTE DE IIS + FTP
# -----------------------------------------------------------------------------

function instalarFTP {
    titulos "INSTALACION DE IIS + FTP SERVER"

    $features = @("Web-Server", "Web-Ftp-Server", "Web-Ftp-Service", "Web-Mgmt-Console")

    foreach ($feature in $features) {
        $state = (Get-WindowsFeature -Name $feature -ErrorAction SilentlyContinue).InstallState
        if ($state -eq "Installed") {
            Write-Log "'$feature' ya esta instalado." "OK"
        } else {
            Write-Log "Instalando '$feature'..." "Info"
            $result = Install-WindowsFeature -Name $feature -IncludeManagementTools
            if ($result.Success) {
                Write-Log "'$feature' instalado correctamente." "OK"
            } else {
                Write-Log "Error al instalar '$feature'." "Error"
                exit 1
            }
        }
    }

    # Importar modulo de administracion web
    try {
        Import-Module WebAdministration -ErrorAction Stop
        Write-Log "Modulo WebAdministration cargado." "OK"
    } catch {
        Write-Log "No se pudo cargar WebAdministration. Verifica la instalacion de IIS." "Error"
        exit 1
    }
}

# -----------------------------------------------------------------------------
#  ESTRUCTURA DE DIRECTORIOS BASE
# -----------------------------------------------------------------------------

function inicializarDirectorios {
    titulos "CREANDO ESTRUCTURA DE CARPETAS"

    $dirs = @($FTP_ROOT, $GENERAL_PATH, $REPROB_PATH, $RECURS_PATH)
    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Log "Carpeta creada: $dir" "OK"
        } else {
            Write-Log "Carpeta ya existe: $dir" "Warn"
        }
    }
}

# -----------------------------------------------------------------------------
#  GRUPOS LOCALES
# -----------------------------------------------------------------------------

function inicializarGrupos {
    titulos "CREANDO GRUPOS LOCALES"

    foreach ($group in $GROUPS) {
        if (-not (Get-LocalGroup -Name $group -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $group -Description "Grupo FTP: $group" | Out-Null
            Write-Log "Grupo '$group' creado." "OK"
        } else {
            Write-Log "Grupo '$group' ya existe." "Warn"
        }
    }
}

# -----------------------------------------------------------------------------
#  SITIO FTP EN IIS
# -----------------------------------------------------------------------------

function reglaAutorizacionFTP {
    param(
        [string]$SubPath    = "",
        [string]$Users      = "",
        [string]$Roles      = "",
        [string]$Permission = "Read"   # "Read", "Write", "Read, Write"
    )

    # IIS usa 1=Read, 2=Write, 3=Read+Write
    $permValue = switch ($Permission) {
        "Read"        { 1 }
        "Write"       { 2 }
        "Read, Write" { 3 }
        default       { 1 }
    }

    $locationPath = $SITE_NAME
    if ($SubPath -ne "") { $locationPath += "/$SubPath" }

    Add-WebConfiguration "/system.ftpServer/security/authorization" `
        -PSPath "IIS:\" `
        -Location $locationPath `
        -Value @{
            accessType  = "Allow"
            users       = $Users
            roles       = $Roles
            permissions = $permValue
        } -ErrorAction SilentlyContinue

    Write-Log "Regla FTP [$Permission] -> ruta='$locationPath' usuarios='$Users' roles='$Roles'" "OK"
}

function inicializarSitio {
    titulos "CONFIGURANDO SITIO FTP EN IIS"

    # Recrear el sitio si ya existe
    if (Get-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue) {
        Write-Log "Sitio '$SITE_NAME' ya existe. Eliminando para reconfigurar..." "Warn"
        Remove-WebSite -Name $SITE_NAME
    }

    # Crear sitio FTP
    New-WebFtpSite -Name $SITE_NAME -Port $FTP_PORT -PhysicalPath $FTP_ROOT -Force | Out-Null
    Write-Log "Sitio FTP '$SITE_NAME' creado en puerto $FTP_PORT." "OK"

    # Autenticacion basica (usuarios locales con usuario/contrasena)
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name "ftpServer.security.authentication.basicAuthentication.enabled" `
        -Value $true
    Write-Log "Autenticacion basica habilitada." "OK"

    # Autenticacion anonima
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name "ftpServer.security.authentication.anonymousAuthentication.enabled" `
        -Value $true
    Write-Log "Acceso anonimo habilitado." "OK"

    # SSL: permitir sin SSL (entorno de laboratorio)
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name "ftpServer.security.ssl.controlChannelPolicy" -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name "ftpServer.security.ssl.dataChannelPolicy"    -Value "SslAllow"
    Write-Log "Politica SSL configurada (SslAllow)." "OK"

    # -- Reglas de autorizacion ------------------------------------------------

    # Anonimo: solo lectura en /general
    reglaAutorizacionFTP -SubPath "general" -Users "anonymous" -Permission "Read"

    # Usuarios autenticados: escritura en /general
    reglaAutorizacionFTP -SubPath "general" -Roles "reprobados,recursadores" -Permission "Read, Write"

    # Grupos: escritura en su carpeta de grupo
    reglaAutorizacionFTP -SubPath "general/reprobados"   -Roles "reprobados"   -Permission "Read, Write"
    reglaAutorizacionFTP -SubPath "general/recursadores" -Roles "recursadores" -Permission "Read, Write"

    # Iniciar el sitio
    Start-WebItem "IIS:\Sites\$SITE_NAME" -ErrorAction SilentlyContinue
    Start-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
    Write-Log "Servicio FTP iniciado." "OK"
}

# -----------------------------------------------------------------------------
#  PERMISOS NTFS EN CARPETAS BASE
# -----------------------------------------------------------------------------

function permisosBase {
    titulos "ASIGNANDO PERMISOS NTFS BASE"

    # /general: todos los usuarios autenticados pueden leer y escribir
    foreach ($folder in @($GENERAL_PATH, $REPROB_PATH, $RECURS_PATH)) {
        $acl = Get-Acl $folder

        # Usuarios autenticados: acceso de escritura
        $ruleAuth = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "Authenticated Users",
            "Modify",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )
        $acl.AddAccessRule($ruleAuth)

        # Anonimo (IUSR) en /general: solo lectura
        if ($folder -eq $GENERAL_PATH) {
            $ruleAnon = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "IUSR",
                "ReadAndExecute",
                "ContainerInherit,ObjectInherit",
                "None",
                "Allow"
            )
            $acl.AddAccessRule($ruleAnon)
        }

        Set-Acl -Path $folder -AclObject $acl
        Write-Log "Permisos NTFS aplicados en: $folder" "OK"
    }

    # Quitar herencia de NTFS en /reprobados y /recursadores para aislar grupos
    foreach ($groupFolder in @($REPROB_PATH, $RECURS_PATH)) {
        $acl = Get-Acl $groupFolder
        $acl.SetAccessRuleProtection($true, $true)   # romper herencia, conservar reglas actuales
        Set-Acl -Path $groupFolder -AclObject $acl
        Write-Log "Herencia NTFS desactivada en: $groupFolder" "OK"
    }
}

# -----------------------------------------------------------------------------
#  CREAR USUARIO FTP
# -----------------------------------------------------------------------------

function crearUsuarioFTP {
    param(
        [string]$Username,
        [string]$Password,
        [string]$Group
    )

    # 1. Crear usuario local (idempotente)
    if (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {
        $secPwd = ConvertTo-SecureString $Password -AsPlainText -Force
        New-LocalUser -Name $Username `
            -Password $secPwd `
            -PasswordNeverExpires `
            -UserMayNotChangePassword | Out-Null
        Write-Log "Usuario '$Username' creado." "OK"
    } else {
        Write-Log "Usuario '$Username' ya existe. Se actualizara su grupo." "Warn"
    }

    # 2. Asegurar que no este en el grupo contrario
    $otherGroup = if ($Group -eq "reprobados") { "recursadores" } else { "reprobados" }
    Remove-LocalGroupMember -Group $otherGroup -Member $Username -ErrorAction SilentlyContinue

    # 3. Agregar al grupo correcto
    Add-LocalGroupMember -Group $Group -Member $Username -ErrorAction SilentlyContinue
    Write-Log "Usuario '$Username' asignado al grupo '$Group'." "OK"

    # 4. Crear carpeta personal
    $groupFolder = if ($Group -eq "reprobados") { $REPROB_PATH } else { $RECURS_PATH }
    $userFolder  = "$groupFolder\$Username"

    if (-not (Test-Path $userFolder)) {
        New-Item -ItemType Directory -Path $userFolder -Force | Out-Null
        Write-Log "Carpeta personal creada: $userFolder" "OK"
    }

    # 5. Permisos NTFS en carpeta personal: solo ese usuario
    $acl = Get-Acl $userFolder
    $acl.SetAccessRuleProtection($true, $false)   # herencia rota, sin copiar reglas

    $ruleOwner = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Username,
        "FullControl",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )
    $acl.AddAccessRule($ruleOwner)

    # Administradores siempre tienen control total
    $ruleAdmin = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators",
        "FullControl",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )
    $acl.AddAccessRule($ruleAdmin)
    Set-Acl -Path $userFolder -AclObject $acl
    Write-Log "Permisos NTFS asignados en carpeta personal '$userFolder'." "OK"

    # 6. Regla de autorizacion FTP para carpeta personal
    reglaAutorizacionFTP `
        -SubPath "general/$Group/$Username" `
        -Users $Username `
        -Permission "Read, Write"
}

# -----------------------------------------------------------------------------
#  CAMBIO DE GRUPO DE UN USUARIO
# -----------------------------------------------------------------------------

function cambioDeGrupo {
 param(
        [string]$Username,
        [string]$gruponv
    )

    # Normalizar: quitar prefijo SERVIDOR\ si el usuario lo incluyo
    $Username = $Username -replace "^.*\\", ""

    # Busca en cuál grupo está realmente el usuario
    $grupovj = $null
    foreach ($g in $GROUPS) {
        $members = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue
        $encontrado = $members | Where-Object {
            ($_.Name -replace "^.*\\", "") -eq $Username
        }
        if ($encontrado) { $grupovj = $g; break }
    }

    $carpetavj   = if ($grupovj -eq "reprobados") { "$REPROB_PATH\$Username" } else { "$RECURS_PATH\$Username" }
    $carpetanv   = if ($gruponv -eq "reprobados") { "$REPROB_PATH\$Username" } else { "$RECURS_PATH\$Username" }

    # Verificar que el usuario existe
    if (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {
        Write-Log "Usuario '$Username' no encontrado." "Error"
        return
    }

    Write-Log "Moviendo '$Username' de '$grupovj' a '$gruponv'..." "Info"

    # Cambiar grupos
    Remove-LocalGroupMember -Group $grupovj -Member $Username -ErrorAction SilentlyContinue
    Add-LocalGroupMember    -Group $gruponv -Member $Username -ErrorAction SilentlyContinue
    Write-Log "Membresia de grupo actualizada." "OK"

    # Mover carpeta personal
    if (Test-Path $carpetavj) {
        if (Test-Path $carpetanv) {
            Write-Log "La carpeta destino '$carpetanv' ya existe. Fusionando contenido..." "Warn"
            Get-ChildItem $carpetavj | Move-Item -Destination $carpetanv -Force
            Remove-Item $carpetavj -Recurse -Force
        } else {
            Move-Item -Path $carpetavj -Destination $carpetanv
        }
        Write-Log "Carpeta movida a: $carpetanv" "OK"
    } else {
        # Si no existia, crearla en el nuevo grupo
        New-Item -ItemType Directory -Path $carpetanv -Force | Out-Null
        Write-Log "Carpeta personal creada en nuevo grupo: $carpetanv" "OK"
    }

    # Re-asignar permisos NTFS
    $acl = Get-Acl $carpetanv
    $acl.SetAccessRuleProtection($true, $false)

    $ruleOwner = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Username, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $ruleAdmin = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $acl.AddAccessRule($ruleOwner)
    $acl.AddAccessRule($ruleAdmin)
    Set-Acl -Path $carpetanv -AclObject $acl
    Write-Log "Permisos NTFS actualizados en '$carpetanv'." "OK"

    Write-Log "Usuario '$Username' movido exitosamente al grupo '$gruponv'." "OK"
}

# -----------------------------------------------------------------------------
#  MENU INTERACTIVO
# -----------------------------------------------------------------------------

function crearUsuario {
    titulos "CREACION DE USUARIOS FTP"

    $n = 0
    do {
        $input = Read-Host "Cuantos usuarios deseas crear?"
    } while (-not ($input -match '^\d+$' -and ($n = [int]$input) -gt 0))

    for ($i = 1; $i -le $n; $i++) {
        Write-Host ""
        Write-Host "  -- Usuario $i de $n --" -ForegroundColor Magenta

        # Nombre
        do {
            $username = (Read-Host "  Nombre de usuario").Trim()
        } while ([string]::IsNullOrWhiteSpace($username))

        # Contrasena
        do {
            $password = (Read-Host "  Contrasena").Trim()
        } while ([string]::IsNullOrWhiteSpace($password))

        # Grupo
        do {
            $group = (Read-Host "  Grupo [reprobados / recursadores]").Trim().ToLower()
        } while ($group -notin $GROUPS)

        crearUsuarioFTP -Username $username -Password $password -Group $group
    }
}

function menuCambioGrupo {
    titulos "CAMBIO DE GRUPO DE USUARIO"

    # Mostrar usuarios existentes por grupo para referencia
    Write-Host ""
    Write-Host "  Usuarios registrados:" -ForegroundColor Yellow
    foreach ($g in $GROUPS) {
        $members = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue
        if ($members) {
            Write-Host "  [$g]" -ForegroundColor Cyan
            $members | ForEach-Object {
                # Mostrar solo el nombre corto sin SERVIDOR
                $shortName = $_.Name -replace "^.*\\", ""
                Write-Host "    - $shortName"
            }
        }
    }
    Write-Host ""

    do {
        $username = (Read-Host "Nombre del usuario a mover").Trim()
    } while ([string]::IsNullOrWhiteSpace($username))

    do {
        $gruponv = (Read-Host "Nuevo grupo [reprobados / recursadores]").Trim().ToLower()
    } while ($gruponv -notin $GROUPS)

    cambioDeGrupo -Username $username -gruponv $gruponv
}

# -----------------------------------------------------------------------------
#  MONITOREO Y DIAGNOSTICO
# -----------------------------------------------------------------------------

function mostrarEstadoFTP {
    titulos "ESTADO DEL SERVIDOR FTP"

    # Estado del servicio Windows
    $svc = Get-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
    if ($svc) {
        $color = if ($svc.Status -eq "Running") { "Green" } else { "Red" }
        Write-Host "  Servicio ftpsvc : " -NoNewline
        Write-Host $svc.Status -ForegroundColor $color
    }

    # Estado del sitio IIS
    $site = Get-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue
    if ($site) {
        $color = if ($site.State -eq "Started") { "Green" } else { "Red" }
        Write-Host "  Sitio IIS '$SITE_NAME': " -NoNewline
        Write-Host $site.State -ForegroundColor $color
        Write-Host "  Ruta fisica   : $($site.PhysicalPath)"
        Write-Host "  Puerto        : $FTP_PORT"
    }

    titulos "USUARIOS Y GRUPOS FTP"
    foreach ($group in $GROUPS) {
        Write-Host ""
        Write-Host "  Grupo: $group" -ForegroundColor Yellow
        $members = Get-LocalGroupMember -Group $group -ErrorAction SilentlyContinue
        if ($members) {
            $members | ForEach-Object { Write-Host "    - $($_.Name)" }
        } else {
            Write-Host "    (sin usuarios)" -ForegroundColor DarkGray
        }
    }

    titulos "ESTRUCTURA DE CARPETAS"
    if (Test-Path $FTP_ROOT) {
        Get-ChildItem $FTP_ROOT -Recurse -Directory | ForEach-Object {
            $depth  = ($_.FullName.Split('\').Count - $FTP_ROOT.Split('\').Count)
            $indent = "  " * $depth
            Write-Host "$indent[D] $($_.Name)"
        }
    } else {
        Write-Log "La carpeta raiz '$FTP_ROOT' no existe aun." "Warn"
    }
}

# -----------------------------------------------------------------------------
#  MENU PRINCIPAL
# -----------------------------------------------------------------------------

function menuPrincipalFTP {
    do {
        Start-Sleep -Seconds 5
        Clear-Host
        Write-Host ""
        Write-Host "--------------------------------------------" -ForegroundColor Magenta
        Write-Host "            GESTION SERVIDOR FTP            " -ForegroundColor Magenta
        Write-Host "--------------------------------------------" -ForegroundColor Magenta
        Write-Host "  1. Instalacion completa (primera vez)     " -ForegroundColor Magenta
        Write-Host "  2. Inicializar directorios (primera vez)  " -ForegroundColor Magenta
        Write-Host "  3. Crear usuarios                         " -ForegroundColor Magenta
        Write-Host "  4. Cambiar grupo a un usuario             " -ForegroundColor Magenta
        Write-Host "  5. Ver estado y diagnostico               " -ForegroundColor Magenta
        Write-Host "  6. Salir                                  " -ForegroundColor Magenta
        Write-Host "--------------------------------------------" -ForegroundColor Magenta
        Write-Host ""

        $opcion = Read-Host "Selecciona una opcion"

        switch ($opcion) {
            "1" {
                instalarFTP
                permisosBase
                Write-Log "Instalacion completada."
            }
            "2" {
                inicializarDirectorios
                inicializarGrupos
                inicializarSitio
            }
            "3" { crearUsuario }
            "4" { menuCambioGrupo }
            "5" { mostrarEstadoFTP }
            "6" { Write-Host "Saliendo..."; return }
            default { Write-Log "Opcion no valida." "Warn" }
        }
    } while ($true)
}

# -----------------------------------------------------------------------------
#  MAIN
# -----------------------------------------------------------------------------
menuPrincipalFTP