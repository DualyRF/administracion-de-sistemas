# ─────────────────────────────────────────────────────────────────────────────
#  CONFIGURACIÓN GLOBAL
# ─────────────────────────────────────────────────────────────────────────────
$FTP_ROOT      = "C:\FTP"
$GENERAL_PATH  = "$FTP_ROOT\general"
$REPROB_PATH   = "$GENERAL_PATH\reprobados"
$RECURS_PATH   = "$GENERAL_PATH\recursadores"
$SITE_NAME     = "MiFTP"
$FTP_PORT      = 21
$GROUPS        = @("reprobados", "recursadores")

# ─────────────────────────────────────────────────────────────────────────────
#  FUNCIONES DE UTILIDAD
# ─────────────────────────────────────────────────────────────────────────────

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info","OK","Warn","Error")][string]$Level = "Info"
    )
    $colors = @{ Info = "White"; OK = "Green"; Warn = "Yellow"; Error = "Red" }
    $prefix = @{ Info = "[INFO]"; OK = "[ OK ]"; Warn = "[WARN]"; Error = "[ERR ]" }
    Write-Host "$(Get-Date -Format 'HH:mm:ss') $($prefix[$Level]) $Message" -ForegroundColor $colors[$Level]
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
}

function Confirm-Prompt {
    param([string]$Question)
    $r = Read-Host "$Question (s/n)"
    return $r -match '^[sS]$'
}

# ─────────────────────────────────────────────────────────────────────────────
#  PARTE 1: INSTALACIÓN IDEMPOTENTE DE IIS + FTP
# ─────────────────────────────────────────────────────────────────────────────

function Install-FTPServer {
    Write-Section "INSTALACIÓN DE IIS + FTP SERVER"

    $features = @("Web-Server", "Web-Ftp-Server", "Web-Ftp-Service", "Web-Mgmt-Console")

    foreach ($feature in $features) {
        $state = (Get-WindowsFeature -Name $feature -ErrorAction SilentlyContinue).InstallState
        if ($state -eq "Installed") {
            Write-Log "'$feature' ya está instalado." "OK"
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

    # Importar módulo de administración web
    try {
        Import-Module WebAdministration -ErrorAction Stop
        Write-Log "Módulo WebAdministration cargado." "OK"
    } catch {
        Write-Log "No se pudo cargar WebAdministration. Verifica la instalación de IIS." "Error"
        exit 1
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  PARTE 2: ESTRUCTURA DE DIRECTORIOS BASE
# ─────────────────────────────────────────────────────────────────────────────

function Initialize-FolderStructure {
    Write-Section "CREANDO ESTRUCTURA DE CARPETAS"

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

# ─────────────────────────────────────────────────────────────────────────────
#  PARTE 3: GRUPOS LOCALES
# ─────────────────────────────────────────────────────────────────────────────

function Initialize-Groups {
    Write-Section "CREANDO GRUPOS LOCALES"

    foreach ($group in $GROUPS) {
        if (-not (Get-LocalGroup -Name $group -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $group -Description "Grupo FTP: $group" | Out-Null
            Write-Log "Grupo '$group' creado." "OK"
        } else {
            Write-Log "Grupo '$group' ya existe." "Warn"
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  PARTE 4: SITIO FTP EN IIS
# ─────────────────────────────────────────────────────────────────────────────

function Add-FtpAuthRule {
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

    Write-Log "Regla FTP [$Permission] → ruta='$locationPath' usuarios='$Users' roles='$Roles'" "OK"
}

function Initialize-FTPSite {
    Write-Section "CONFIGURANDO SITIO FTP EN IIS"

    # Recrear el sitio si ya existe
    if (Get-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue) {
        Write-Log "Sitio '$SITE_NAME' ya existe. Eliminando para reconfigurar..." "Warn"
        Remove-WebSite -Name $SITE_NAME
    }

    # Crear sitio FTP
    New-WebFtpSite -Name $SITE_NAME -Port $FTP_PORT -PhysicalPath $FTP_ROOT -Force | Out-Null
    Write-Log "Sitio FTP '$SITE_NAME' creado en puerto $FTP_PORT." "OK"

    # Autenticación básica (usuarios locales con usuario/contraseña)
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name "ftpServer.security.authentication.basicAuthentication.enabled" `
        -Value $true
    Write-Log "Autenticación básica habilitada." "OK"

    # Autenticación anónima
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name "ftpServer.security.authentication.anonymousAuthentication.enabled" `
        -Value $true
    Write-Log "Acceso anónimo habilitado." "OK"

    # SSL: permitir sin SSL (entorno de laboratorio)
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name "ftpServer.security.ssl.controlChannelPolicy" -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name "ftpServer.security.ssl.dataChannelPolicy"    -Value "SslAllow"
    Write-Log "Política SSL configurada (SslAllow)." "OK"

    # ── Reglas de autorización ────────────────────────────────────────────────

    # Anónimo: solo lectura en /general
    Add-FtpAuthRule -SubPath "general" -Users "anonymous" -Permission "Read"

    # Usuarios autenticados: escritura en /general
    Add-FtpAuthRule -SubPath "general" -Roles "reprobados,recursadores" -Permission "Read, Write"

    # Grupos: escritura en su carpeta de grupo
    Add-FtpAuthRule -SubPath "general/reprobados"   -Roles "reprobados"   -Permission "Read, Write"
    Add-FtpAuthRule -SubPath "general/recursadores" -Roles "recursadores" -Permission "Read, Write"

    # Iniciar el sitio
    Start-WebItem "IIS:\Sites\$SITE_NAME" -ErrorAction SilentlyContinue
    Start-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
    Write-Log "Servicio FTP iniciado." "OK"
}

# ─────────────────────────────────────────────────────────────────────────────
#  PARTE 5: PERMISOS NTFS EN CARPETAS BASE
# ─────────────────────────────────────────────────────────────────────────────

function Set-BaseFolderPermissions {
    Write-Section "ASIGNANDO PERMISOS NTFS BASE"

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

        # Anónimo (IUSR) en /general: solo lectura
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

# ─────────────────────────────────────────────────────────────────────────────
#  PARTE 6: CREAR USUARIO FTP
# ─────────────────────────────────────────────────────────────────────────────

function New-FtpUser {
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
        Write-Log "Usuario '$Username' ya existe. Se actualizará su grupo." "Warn"
    }

    # 2. Asegurar que no esté en el grupo contrario
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

    # 6. Regla de autorización FTP para carpeta personal
    Add-FtpAuthRule `
        -SubPath "general/$Group/$Username" `
        -Users $Username `
        -Permission "Read, Write"
}

# ─────────────────────────────────────────────────────────────────────────────
#  PARTE 7: CAMBIO DE GRUPO DE UN USUARIO
# ─────────────────────────────────────────────────────────────────────────────

function Move-UserToGroup {
    param(
        [string]$Username,
        [string]$NewGroup
    )

    $OldGroup    = if ($NewGroup -eq "reprobados") { "recursadores" } else { "reprobados" }
    $oldFolder   = if ($OldGroup -eq "reprobados") { "$REPROB_PATH\$Username" } else { "$RECURS_PATH\$Username" }
    $newFolder   = if ($NewGroup -eq "reprobados") { "$REPROB_PATH\$Username" } else { "$RECURS_PATH\$Username" }

    # Verificar que el usuario existe
    if (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {
        Write-Log "Usuario '$Username' no encontrado." "Error"
        return
    }

    Write-Log "Moviendo '$Username' de '$OldGroup' a '$NewGroup'..." "Info"

    # Cambiar grupos
    Remove-LocalGroupMember -Group $OldGroup -Member $Username -ErrorAction SilentlyContinue
    Add-LocalGroupMember    -Group $NewGroup -Member $Username -ErrorAction SilentlyContinue
    Write-Log "Membresía de grupo actualizada." "OK"

    # Mover carpeta personal
    if (Test-Path $oldFolder) {
        if (Test-Path $newFolder) {
            Write-Log "La carpeta destino '$newFolder' ya existe. Fusionando contenido..." "Warn"
            Get-ChildItem $oldFolder | Move-Item -Destination $newFolder -Force
            Remove-Item $oldFolder -Recurse -Force
        } else {
            Move-Item -Path $oldFolder -Destination $newFolder
        }
        Write-Log "Carpeta movida a: $newFolder" "OK"
    } else {
        # Si no existía, crearla en el nuevo grupo
        New-Item -ItemType Directory -Path $newFolder -Force | Out-Null
        Write-Log "Carpeta personal creada en nuevo grupo: $newFolder" "OK"
    }

    # Re-asignar permisos NTFS
    $acl = Get-Acl $newFolder
    $acl.SetAccessRuleProtection($true, $false)

    $ruleOwner = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Username, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $ruleAdmin = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $acl.AddAccessRule($ruleOwner)
    $acl.AddAccessRule($ruleAdmin)
    Set-Acl -Path $newFolder -AclObject $acl
    Write-Log "Permisos NTFS actualizados en '$newFolder'." "OK"

    Write-Log "Usuario '$Username' movido exitosamente al grupo '$NewGroup'." "OK"
}

# ─────────────────────────────────────────────────────────────────────────────
#  PARTE 8: MENÚ INTERACTIVO
# ─────────────────────────────────────────────────────────────────────────────

function Start-UserCreationMenu {
    Write-Section "CREACIÓN MASIVA DE USUARIOS FTP"

    $n = 0
    do {
        $input = Read-Host "¿Cuántos usuarios deseas crear?"
    } while (-not ($input -match '^\d+$' -and ($n = [int]$input) -gt 0))

    for ($i = 1; $i -le $n; $i++) {
        Write-Host ""
        Write-Host "  ── Usuario $i de $n ──" -ForegroundColor Magenta

        # Nombre
        do {
            $username = (Read-Host "  Nombre de usuario").Trim()
        } while ([string]::IsNullOrWhiteSpace($username))

        # Contraseña
        do {
            $password = (Read-Host "  Contraseña").Trim()
        } while ([string]::IsNullOrWhiteSpace($password))

        # Grupo
        do {
            $group = (Read-Host "  Grupo [reprobados / recursadores]").Trim().ToLower()
        } while ($group -notin $GROUPS)

        New-FtpUser -Username $username -Password $password -Group $group
    }
}

function Start-ChangeGroupMenu {
    Write-Section "CAMBIO DE GRUPO DE USUARIO"

    do {
        $username = (Read-Host "Nombre del usuario a mover").Trim()
    } while ([string]::IsNullOrWhiteSpace($username))

    do {
        $newGroup = (Read-Host "Nuevo grupo [reprobados / recursadores]").Trim().ToLower()
    } while ($newGroup -notin $GROUPS)

    Move-UserToGroup -Username $username -NewGroup $newGroup
}

# ─────────────────────────────────────────────────────────────────────────────
#  PARTE 9: MONITOREO Y DIAGNÓSTICO
# ─────────────────────────────────────────────────────────────────────────────

function Show-FTPStatus {
    Write-Section "ESTADO DEL SERVIDOR FTP"

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
        Write-Host "  Ruta física   : $($site.PhysicalPath)"
        Write-Host "  Puerto        : $FTP_PORT"
    }

    Write-Section "USUARIOS Y GRUPOS FTP"
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

    Write-Section "ESTRUCTURA DE CARPETAS"
    if (Test-Path $FTP_ROOT) {
        Get-ChildItem $FTP_ROOT -Recurse -Directory | ForEach-Object {
            $depth  = ($_.FullName.Split('\').Count - $FTP_ROOT.Split('\').Count)
            $indent = "  " * $depth
            Write-Host "$indent📁 $($_.Name)"
        }
    } else {
        Write-Log "La carpeta raíz '$FTP_ROOT' no existe aún." "Warn"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  MENÚ PRINCIPAL
# ─────────────────────────────────────────────────────────────────────────────

function Show-MainMenu {
    do {
        Write-Host ""
        Write-Host "╔═══════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║       GESTIÓN SERVIDOR FTP - IIS      ║" -ForegroundColor Cyan
        Write-Host "╠═══════════════════════════════════════╣" -ForegroundColor Cyan
        Write-Host "║  1. Instalación completa (primera vez)║" -ForegroundColor Cyan
        Write-Host "║  2. Crear usuarios                    ║" -ForegroundColor Cyan
        Write-Host "║  3. Cambiar grupo a un usuario        ║" -ForegroundColor Cyan
        Write-Host "║  4. Ver estado y diagnóstico          ║" -ForegroundColor Cyan
        Write-Host "║  5. Salir                             ║" -ForegroundColor Cyan
        Write-Host "╚═══════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""

        $opcion = Read-Host "Selecciona una opción"

        switch ($opcion) {
            "1" {
                Install-FTPServer
                Initialize-FolderStructure
                Initialize-Groups
                Initialize-FTPSite
                Set-BaseFolderPermissions
                Write-Log "Instalación y configuración inicial completada." "OK"
            }
            "2" { Start-UserCreationMenu }
            "3" { Start-ChangeGroupMenu }
            "4" { Show-FTPStatus }
            "5" { Write-Log "Saliendo..." "Info"; return }
            default { Write-Log "Opción no válida." "Warn" }
        }
    } while ($true)
}

# ─────────────────────────────────────────────────────────────────────────────
#  PUNTO DE ENTRADA
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "  Ejecutando como: $env:USERNAME en $env:COMPUTERNAME" -ForegroundColor DarkGray
Write-Host ""

Show-MainMenu
