# -----------------------------------------------------------------------------
#  CONFIGURACION GLOBAL
# -----------------------------------------------------------------------------
$FTP_ROOT      = "C:\FTP"
$LOCAL_USER    = "$FTP_ROOT\LocalUser"
$GENERAL_PATH  = "$LOCAL_USER\Public\general"
$REPROB_PATH   = "$LOCAL_USER\reprobados"
$RECURS_PATH   = "$LOCAL_USER\recursadores"
$SITE_NAME     = "MiFTP"
$FTP_PORT      = 21
$GROUPS        = @("reprobados", "recursadores")

# -----------------------------------------------------------------------------
#  IDENTIDADES POR SID - Independiente del idioma del SO
#  S-1-5-32-544 = Administrators / Administradores
#  S-1-5-18     = SYSTEM / SISTEMA
#  S-1-5-11     = Authenticated Users / Usuarios autenticados
#  S-1-5-17     = IUSR (cuenta anonima IIS)
# -----------------------------------------------------------------------------
$ID_ADMINS = (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")).Translate([System.Security.Principal.NTAccount])
$ID_SYSTEM = (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")).Translate([System.Security.Principal.NTAccount])
$ID_AUTH   = (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-11")).Translate([System.Security.Principal.NTAccount])

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
#  FUNCION: Crear regla ACL reutilizable
# -----------------------------------------------------------------------------
function New-ACLRule {
    param(
        [object]$Identity,
        [string]$Rights = "FullControl",
        [string]$Type   = "Allow"
    )
    return New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Identity, $Rights,
        "ContainerInherit,ObjectInherit", "None", $Type
    )
}

# -----------------------------------------------------------------------------
#  FUNCION: Aplicar ACL limpia a una carpeta (rompe herencia, aplica reglas)
# -----------------------------------------------------------------------------
function Set-FolderACL {
    param(
        [string]$Path,
        [System.Security.AccessControl.FileSystemAccessRule[]]$Rules
    )
    $acl = Get-Acl $Path
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in $Rules) {
        $acl.AddAccessRule($rule)
    }
    Set-Acl -Path $Path -AclObject $acl
}

# -----------------------------------------------------------------------------
#  FUNCION: Otorgar derecho "Log on locally" requerido por IIS FTP
# -----------------------------------------------------------------------------
function Grant-FTPLogonRight {
    param([string]$Username)

    $exportInf = "$env:TEMP\secedit_export.inf"
    $applyInf  = "$env:TEMP\secedit_apply.inf"
    $applyDb   = "$env:TEMP\secedit_apply.sdb"

    & secedit /export /cfg $exportInf /quiet 2>$null

    $cfg    = Get-Content $exportInf -ErrorAction SilentlyContinue
    $linea  = $cfg | Where-Object { $_ -match "^SeInteractiveLogonRight" }

    if ($linea -and $linea -match [regex]::Escape($Username)) {
        Write-Log "'$Username' ya tiene derecho de logon local." "Info"
        return
    }

    $nuevaLinea = if ($linea) { "$linea,*$Username" } else { "SeInteractiveLogonRight = *$Username" }

    $infContent = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]
$nuevaLinea
"@
    $infContent | Out-File -FilePath $applyInf -Encoding Unicode
    & secedit /configure /db $applyDb /cfg $applyInf /quiet 2>$null
    Remove-Item $exportInf, $applyInf, $applyDb -ErrorAction SilentlyContinue
    Write-Log "Derecho 'Log on locally' otorgado a '$Username'." "OK"
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

    try {
        Import-Module WebAdministration -ErrorAction Stop
        Write-Log "Modulo WebAdministration cargado." "OK"
    } catch {
        Write-Log "No se pudo cargar WebAdministration. Verifica la instalacion de IIS." "Error"
        exit 1
    }
}


function inicializarDirectorios {
    titulos "CREANDO ESTRUCTURA DE CARPETAS"

    $dirs = @(
        $FTP_ROOT,
        $LOCAL_USER,
        "$LOCAL_USER\Public",
        $GENERAL_PATH,
        $REPROB_PATH,
        $RECURS_PATH
    )

    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Log "Carpeta creada: $dir" "OK"
        } else {
            Write-Log "Ya existe: $dir" "Info"
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
#  PERMISOS NTFS EN CARPETAS BASE
# -----------------------------------------------------------------------------

function permisosBase {
    titulos "CONFIGURANDO PERMISOS NTFS BASE"

    # Raiz FTP: solo Admins y SYSTEM
    Set-FolderACL -Path $FTP_ROOT -Rules @(
        (New-ACLRule $ID_ADMINS "FullControl"),
        (New-ACLRule $ID_SYSTEM "FullControl")
    )
    Write-Log "Permisos raiz FTP configurados." "OK"

    # LocalUser\Public: Admins + SYSTEM + Auth Users (para que IIS pueda leer)
    Set-FolderACL -Path "$LOCAL_USER\Public" -Rules @(
        (New-ACLRule $ID_ADMINS "FullControl"),
        (New-ACLRule $ID_SYSTEM "FullControl"),
        (New-ACLRule $ID_AUTH   "ReadAndExecute")
    )

    # /general: todos los autenticados pueden leer y escribir
    Set-FolderACL -Path $GENERAL_PATH -Rules @(
        (New-ACLRule $ID_ADMINS "FullControl"),
        (New-ACLRule $ID_SYSTEM "FullControl"),
        (New-ACLRule $ID_AUTH   "Modify")
    )
    Write-Log "Permisos /general configurados (todos los usuarios autenticados)." "OK"

    # /reprobados y /recursadores: AISLAMIENTO TOTAL por grupo
    $gruposRutas = @{ "reprobados" = $REPROB_PATH; "recursadores" = $RECURS_PATH }
    foreach ($group in $gruposRutas.Keys) {
        $path = $gruposRutas[$group]
        Set-FolderACL -Path $path -Rules @(
            (New-ACLRule $ID_ADMINS "FullControl"),
            (New-ACLRule $ID_SYSTEM "FullControl"),
            (New-ACLRule $group     "Modify")
        )
        Write-Log "Aislamiento NTFS: solo '$group' accede a $path" "OK"
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
        [string]$Permission = "Read"
    )

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

    Import-Module WebAdministration -ErrorAction Stop

    if (Get-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue) {
        Write-Log "Sitio '$SITE_NAME' ya existe. Eliminando para reconfigurar..." "Warn"
        & "$env:SystemRoot\System32\inetsrv\appcmd.exe" stop site $SITE_NAME 2>$null
        Remove-WebSite -Name $SITE_NAME
    }

    # Sitio apunta a LocalUser (raiz de las jaulas)
    New-WebFtpSite -Name $SITE_NAME -Port $FTP_PORT -PhysicalPath $LOCAL_USER -Force | Out-Null
    Write-Log "Sitio FTP '$SITE_NAME' creado en puerto $FTP_PORT." "OK"

    # Solo autenticacion basica (sin anonimo)
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name "ftpServer.security.authentication.basicAuthentication.enabled" -Value $true
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name "ftpServer.security.authentication.anonymousAuthentication.enabled" -Value $false
    Write-Log "Autenticacion basica habilitada. Anonimo DESACTIVADO." "OK"

    # SSL opcional (laboratorio)
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name "ftpServer.security.ssl.controlChannelPolicy" -Value 0
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name "ftpServer.security.ssl.dataChannelPolicy" -Value 0
    Write-Log "SSL configurado como opcional (SslAllow)." "OK"

    # Puertos pasivos
    Set-WebConfigurationProperty -PSPath "IIS:\" `
        -Filter "system.ftpServer/firewallSupport" `
        -Name "lowDataChannelPort"  -Value 40000
    Set-WebConfigurationProperty -PSPath "IIS:\" `
        -Filter "system.ftpServer/firewallSupport" `
        -Name "highDataChannelPort" -Value 40100
    Write-Log "Puertos pasivos 40000-40100 configurados." "OK"

    # User Isolation modo 3: cada usuario aterriza en LocalUser\<username>
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name "ftpServer.userIsolation.mode" -Value 3
    Write-Log "User Isolation ACTIVADO (Modo 3)." "OK"

    # Reglas de autorizacion IIS: usuarios autenticados tienen acceso total
    # El aislamiento real lo hacen los permisos NTFS de cada jaula
    reglaAutorizacionFTP -SubPath "" -Users "*" -Permission "Read, Write"

    # Reiniciar servicio para aplicar cambios
    Stop-Service ftpsvc -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Service ftpsvc
    Start-Sleep -Seconds 2

    & "$env:SystemRoot\System32\inetsrv\appcmd.exe" start site $SITE_NAME
    Write-Log "Servicio FTP iniciado." "OK"
}


function construirJaulaUsuario {
    param(
        [string]$Username,
        [string]$Group
    )

    Write-Log "Construyendo jaula FTP para '$Username'..." "Info"

    $homeDir  = "$LOCAL_USER\$Username"
    $personal = "$homeDir\$Username"

    # Obtener SID del usuario (evita problemas de idioma del SO)
    $userSID     = (Get-LocalUser -Name $Username).SID
    $userAccount = $userSID.Translate([System.Security.Principal.NTAccount])

    # Crear carpeta home
    if (-not (Test-Path $homeDir)) {
        New-Item -ItemType Directory -Path $homeDir -Force | Out-Null
    }

    # Permisos home: el usuario puede listar, Admins control total
    Set-FolderACL -Path $homeDir -Rules @(
        (New-ACLRule $ID_ADMINS   "FullControl"),
        (New-ACLRule $ID_SYSTEM   "FullControl"),
        (New-ACLRule $userAccount "ReadAndExecute")
    )

    # Crear carpeta personal fisica
    if (-not (Test-Path $personal)) {
        New-Item -ItemType Directory -Path $personal -Force | Out-Null
    }

    # Permisos carpeta personal: solo el usuario (Modify = leer/escribir/borrar)
    Set-FolderACL -Path $personal -Rules @(
        (New-ACLRule $ID_ADMINS   "FullControl"),
        (New-ACLRule $ID_SYSTEM   "FullControl"),
        (New-ACLRule $userAccount "Modify")
    )
    Write-Log "Carpeta personal creada: $personal" "OK"

    # Junction: general (publica, todos leen y escriben)
    $jGeneral = "$homeDir\general"
    if (-not (Test-Path $jGeneral)) {
        cmd /c "mklink /J `"$jGeneral`" `"$GENERAL_PATH`"" | Out-Null
        Write-Log "Junction 'general' creado." "OK"
    }

    # Junction: carpeta del grupo (solo los del mismo grupo acceden por NTFS)
    $groupPath = if ($Group -eq "reprobados") { $REPROB_PATH } else { $RECURS_PATH }
    $jGroup    = "$homeDir\$Group"
    if (-not (Test-Path $jGroup)) {
        cmd /c "mklink /J `"$jGroup`" `"$groupPath`"" | Out-Null
        Write-Log "Junction '$Group' creado." "OK"
    }

    Write-Log "Jaula lista para '$Username'." "OK"
}

# -----------------------------------------------------------------------------
#  DESTRUIR JAULA DEL USUARIO
# -----------------------------------------------------------------------------
function destruirJaulaUsuario {
    param([string]$Username)

    Write-Log "Eliminando jaula de '$Username'..." "Info"

    $homeDir = "$LOCAL_USER\$Username"

    # Eliminar junctions con rmdir (NO Remove-Item: borraria el contenido real)
    foreach ($junc in @("general", "reprobados", "recursadores")) {
        $juncPath = "$homeDir\$junc"
        if (Test-Path $juncPath) {
            cmd /c "rmdir `"$juncPath`"" | Out-Null
            Write-Log "Junction '$junc' eliminado." "OK"
        }
    }

    # Eliminar home completo (incluye carpeta personal)
    if (Test-Path $homeDir) {
        Remove-Item -Path $homeDir -Recurse -Force
        Write-Log "Carpeta home de '$Username' eliminada." "OK"
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

    # 1. Crear usuario local del sistema
    if (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {
        $secPwd = ConvertTo-SecureString $Password -AsPlainText -Force
        try {
            New-LocalUser -Name $Username -Password $secPwd `
                -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
            Write-Log "Usuario '$Username' creado." "OK"
        } catch {
            Write-Log "Error al crear usuario '$Username': $_" "Error"
            return
        }
        # Esperar a que Windows registre la identidad antes de usarla en ACLs
        Start-Sleep -Seconds 3
    } else {
        Write-Log "Usuario '$Username' ya existe." "Warn"
    }

    # 2. Otorgar derecho de logon local (requerido por IIS FTP)
    Grant-FTPLogonRight -Username $Username

    # 3. Gestionar pertenencia al grupo
    $otherGroup = if ($Group -eq "reprobados") { "recursadores" } else { "reprobados" }
    Remove-LocalGroupMember -Group $otherGroup -Member $Username -ErrorAction SilentlyContinue
    Add-LocalGroupMember    -Group $Group      -Member $Username -ErrorAction SilentlyContinue
    Write-Log "Usuario '$Username' agregado al grupo '$Group'." "OK"

    # 4. Construir jaula con junctions
    construirJaulaUsuario -Username $Username -Group $Group

    Write-Log "Usuario '$Username' configurado correctamente." "OK"
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

    if (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {
        Write-Log "Usuario '$Username' no encontrado." "Error"
        return
    }

    # Detectar grupo actual dinamicamente
    $grupovj = $null
    foreach ($g in $GROUPS) {
        $members = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue
        $encontrado = $members | Where-Object { ($_.Name -replace "^.*\\", "") -eq $Username }
        if ($encontrado) { $grupovj = $g; break }
    }

    if (-not $grupovj) {
        Write-Log "El usuario '$Username' no esta en ningun grupo FTP." "Warn"
        Write-Log "Se agregara directamente al grupo '$gruponv'." "Info"
    } elseif ($grupovj -eq $gruponv) {
        Write-Log "El usuario '$Username' ya esta en '$gruponv'. Nada que hacer." "Warn"
        return
    } else {
        Write-Log "Grupo actual: '$grupovj' -> Nuevo grupo: '$gruponv'" "Info"
    }

    # Cambiar grupos locales
    if ($grupovj) {
        Remove-LocalGroupMember -Group $grupovj -Member $Username -ErrorAction SilentlyContinue
        Write-Log "Usuario removido de '$grupovj'." "OK"
    }
    Add-LocalGroupMember -Group $gruponv -Member $Username -ErrorAction SilentlyContinue
    Write-Log "Usuario agregado a '$gruponv'." "OK"

    # Actualizar junction del grupo en la jaula
    $homeDir   = "$LOCAL_USER\$Username"
    $juncViejo = "$homeDir\$grupovj"
    $juncNuevo = "$homeDir\$gruponv"
    $groupPath = if ($gruponv -eq "reprobados") { $REPROB_PATH } else { $RECURS_PATH }

    if ($grupovj -and (Test-Path $juncViejo)) {
        cmd /c "rmdir `"$juncViejo`"" | Out-Null
        Write-Log "Junction '$grupovj' eliminado." "OK"
    }

    if (-not (Test-Path $juncNuevo)) {
        cmd /c "mklink /J `"$juncNuevo`" `"$groupPath`"" | Out-Null
        Write-Log "Junction '$gruponv' creado." "OK"
    }

    Write-Log "Usuario '$Username' movido exitosamente al grupo '$gruponv'." "OK"
}

# -----------------------------------------------------------------------------
#  RESET COMPLETO DEL SERVIDOR
# -----------------------------------------------------------------------------

function resetearServidor {
    titulos "RESET COMPLETO DEL SERVIDOR FTP"

    if (-not (confirmaciones "Esto eliminara TODOS los usuarios y carpetas FTP. Continuar?")) {
        Write-Log "Reset cancelado." "Warn"
        return
    }

    # 1. Eliminar todos los usuarios de los grupos FTP
    foreach ($group in $GROUPS) {
        $members = Get-LocalGroupMember -Group $group -ErrorAction SilentlyContinue
        foreach ($member in $members) {
            $shortName = $member.Name -replace "^.*\\", ""
            Remove-LocalGroupMember -Group $group -Member $shortName -ErrorAction SilentlyContinue
            Remove-LocalUser -Name $shortName -ErrorAction SilentlyContinue
            Write-Log "Usuario '$shortName' eliminado." "OK"
        }
    }

    # 2. Detener y eliminar el sitio FTP de IIS
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    if (Get-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue) {
        & "$env:SystemRoot\System32\inetsrv\appcmd.exe" stop site $SITE_NAME 2>$null
        Remove-WebSite -Name $SITE_NAME
        Write-Log "Sitio IIS '$SITE_NAME' eliminado." "OK"
    }

    # 3. Eliminar toda la estructura de carpetas FTP
    if (Test-Path $FTP_ROOT) {
        Remove-Item -Path $FTP_ROOT -Recurse -Force
        Write-Log "Carpeta raiz FTP eliminada: $FTP_ROOT" "OK"
    }

    Write-Log "Reset completado. Usa opciones 1 y 2 para reinicializar." "OK"
}

# -----------------------------------------------------------------------------
#  MENU INTERACTIVO - CREACION DE USUARIOS
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

        do {
            $username = (Read-Host "  Nombre de usuario").Trim()
        } while ([string]::IsNullOrWhiteSpace($username))

        do {
            $password = (Read-Host "  Contrasena").Trim()
        } while ([string]::IsNullOrWhiteSpace($password))

        do {
            $group = (Read-Host "  Grupo [reprobados / recursadores]").Trim().ToLower()
        } while ($group -notin $GROUPS)

        crearUsuarioFTP -Username $username -Password $password -Group $group
    }
}

# -----------------------------------------------------------------------------
#  MENU INTERACTIVO - CAMBIO DE GRUPO
# -----------------------------------------------------------------------------

function menuCambioGrupo {
    titulos "CAMBIO DE GRUPO DE USUARIO"

    Write-Host ""
    Write-Host "  Usuarios registrados:" -ForegroundColor Yellow
    foreach ($g in $GROUPS) {
        $members = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue
        if ($members) {
            Write-Host "  [$g]" -ForegroundColor Cyan
            $members | ForEach-Object {
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

    Import-Module WebAdministration -ErrorAction SilentlyContinue

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

        $isolation = (Get-ItemProperty "IIS:\Sites\$SITE_NAME" `
            -Name "ftpServer.userIsolation.mode" -ErrorAction SilentlyContinue).Value
        $isoText = switch ($isolation) {
            3 { "IsolateAllDirectories (correcto)" }
            0 { "Sin aislamiento (incorrecto)" }
            default { "Modo $isolation" }
        }
        Write-Host "  User Isolation: $isoText"
    }

    titulos "USUARIOS Y GRUPOS FTP"
    foreach ($group in $GROUPS) {
        Write-Host ""
        Write-Host "  Grupo: $group" -ForegroundColor Yellow
        $members = Get-LocalGroupMember -Group $group -ErrorAction SilentlyContinue
        if ($members) {
            $members | ForEach-Object {
                $shortName = $_.Name -replace "^.*\\", ""
                $jaulaOk   = Test-Path "$LOCAL_USER\$shortName"
                $estado    = if ($jaulaOk) { "[jaula OK]" } else { "[SIN JAULA]" }
                Write-Host "    - $shortName $estado"
            }
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

    Write-Host ""
    Write-Log "Conexiones activas en puerto 21:" "Info"
    netstat -an | Select-String ":21 "
}

# -----------------------------------------------------------------------------
#  MENU PRINCIPAL
# -----------------------------------------------------------------------------

function menuPrincipalFTP {
    do {
        Start-Sleep -Seconds 2
        Clear-Host
        Write-Host ""
        Write-Host "------------------------------------------------" -ForegroundColor Magenta
        Write-Host "            GESTION SERVIDOR FTP                " -ForegroundColor Magenta
        Write-Host "------------------------------------------------" -ForegroundColor Magenta
        Write-Host "  1. Instalacion completa (primera vez)         "
        Write-Host "  2. Inicializar directorios y sitio FTP        "
        Write-Host "  3. Crear usuarios                             "
        Write-Host "  4. Cambiar grupo a un usuario                 "
        Write-Host "  5. Ver estado y diagnostico                   "
        Write-Host "  6. Reset completo del servidor (Borrar todo)  "
        Write-Host "  7. Salir                                      "
        Write-Host "------------------------------------------------" -ForegroundColor Magenta
        Write-Host ""

        $opcion = Read-Host "Selecciona una opcion"

        switch ($opcion) {
            "1" {
                instalarFTP
                inicializarDirectorios
                permisosBase
                Write-Log "Instalacion completada." "OK"
                Read-Host "`nPresiona Enter para continuar"
            }
            "2" {
                inicializarDirectorios
                inicializarGrupos
                permisosBase
                inicializarSitio
                Read-Host "`nPresiona Enter para continuar"
            }
            "3" {
                crearUsuario
                Read-Host "`nPresiona Enter para continuar"
            }
            "4" {
                menuCambioGrupo
                Read-Host "`nPresiona Enter para continuar"
            }
            "5" {
                mostrarEstadoFTP
                Read-Host "`nPresiona Enter para continuar"
            }
            "6" {
                resetearServidor
                Read-Host "`nPresiona Enter para continuar"
            }
            "7" { Write-Host "Saliendo..."; return }
            default { Write-Log "Opcion no valida." "Warn" }
        }
    } while ($true)
}

# -----------------------------------------------------------------------------
#  MAIN
# -----------------------------------------------------------------------------
menuPrincipalFTP