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
$LOCAL_USER = "$FTP_ROOT\LocalUser"

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

function Get-AdminGroupName {
    $sid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    return $sid.Translate([System.Security.Principal.NTAccount]).Value
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
    # Estructura plana para que todos la vean al entrar
    $dirs = @($FTP_ROOT, $GENERAL_PATH, $REPROB_PATH, $RECURS_PATH)
    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
    # Ya no necesitas LocalUser si desactivas el aislamiento
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

    if (Get-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue) {
        Write-Log "Sitio '$SITE_NAME' ya existe. Eliminando para reconfigurar..." "Warn"
        Remove-WebSite -Name $SITE_NAME
    }

    New-WebFtpSite -Name $SITE_NAME -Port $FTP_PORT -PhysicalPath $FTP_ROOT -Force | Out-Null
    Write-Log "Sitio FTP '$SITE_NAME' creado en puerto $FTP_PORT." "OK"

    # Autenticacion basica
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name "ftpServer.security.authentication.basicAuthentication.enabled" `
        -Value $true
    Write-Log "Autenticacion basica habilitada." "OK"

    # Autenticacion anonima
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name "ftpServer.security.authentication.anonymousAuthentication.enabled" `
        -Value $true
    Write-Log "Acceso anonimo habilitado." "OK"

    # SSL desactivado (laboratorio)
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name "ftpServer.security.ssl.controlChannelPolicy" -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name "ftpServer.security.ssl.dataChannelPolicy" -Value "SslAllow"
    Write-Log "Politica SSL configurada (SslAllow)." "OK"

    # User Isolation: cada usuario aterriza en LocalUser\<username> al conectarse
    # Esto resuelve el error "530 home directory inaccessible"
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name "ftpServer.userIsolation.mode" -Value 0
    Write-Log "User Isolation DESACTIVADO (Modo 0). Los usuarios verán la raíz compartida." "OK"

    # Reglas de autorizacion
# Permite que todos los usuarios vean la lista de carpetas en la raíz
    reglaAutorizacionFTP -SubPath "" -Users "*" -Permission "Read" 
    reglaAutorizacionFTP -SubPath "general" -Roles "reprobados,recursadores" -Permission "Read,Write"

    Start-WebItem "IIS:\Sites\$SITE_NAME" -ErrorAction SilentlyContinue
    Start-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
    Write-Log "Servicio FTP iniciado." "OK"
}

# -----------------------------------------------------------------------------
#  PERMISOS NTFS EN CARPETAS BASE
# -----------------------------------------------------------------------------

function permisosBase {
    titulos "CONFIGURANDO AISLAMIENTO POR GRUPOS (NTFS)"

    # 1. Ajuste para la carpeta GENERAL (El contenedor padre)
    # Solo damos permiso de lectura en la raíz de /general para que vean las subcarpetas,
    # pero NO heredamos el permiso de escritura a los hijos de forma automática.
    $aclGen = Get-Acl $GENERAL_PATH
    $aclGen.SetAccessRuleProtection($true, $true) # Rompe herencia pero mantiene Admins
    
    # "Authenticated Users" solo puede leer esta carpeta (para ver los nombres de los grupos)
    $ruleGen = New-Object System.Security.AccessControl.FileSystemAccessRule("Authenticated Users", "ReadAndExecute", "None", "None", "Allow")
    $aclGen.AddAccessRule($ruleGen)
    Set-Acl $GENERAL_PATH $aclGen

    # 2. Ajuste para las carpetas de GRUPO (Aislamiento Total)
    $gruposRutas = @{
        "reprobados"   = $REPROB_PATH
        "recursadores" = $RECURS_PATH
    }

    foreach ($group in $gruposRutas.Keys) {
        $path = $gruposRutas[$group]
        $acl = Get-Acl $path

        # IMPORTANTE: $true, $false elimina TODOS los permisos heredados (incluyendo Authenticated Users)
        $acl.SetAccessRuleProtection($true, $false) 

        # Solo entran Admins y el Grupo específico
        $adminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
        $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule($adminSid, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($adminRule)

        $groupRule = New-Object System.Security.AccessControl.FileSystemAccessRule($group, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($groupRule)

        Set-Acl -Path $path -AclObject $acl
        Write-Log "Aislamiento estricto: Solo '$group' puede entrar a $path" "OK"
    }
}

# -----------------------------------------------------------------------------
#  CREAR HOME DE USUARIO (estructura LocalUser requerida por IIS)
# -----------------------------------------------------------------------------
function crearHomeUsuario {
    param(
        [string]$Username,
        [string]$Group
    )

    $adminName = Get-AdminGroupName
    $fullUsername = "$env:COMPUTERNAME\$Username"

    # Estructura: C:\FTP\LocalUser\<usuario>\general\<grupo>\<usuario>
    $homeDir   = "$LOCAL_USER\$Username"
    $groupLink = if ($Group -eq "reprobados") { "$homeDir\general\reprobados" } `
                 else                         { "$homeDir\general\recursadores" }
    $userDir   = "$groupLink\$Username"

    # Crear toda la jerarquia de carpetas del home
    foreach ($dir in @($homeDir, "$homeDir\general", $groupLink, $userDir)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Log "Carpeta creada: $dir" "OK"
        }
    }

    # Permisos NTFS en el home del usuario: solo el usuario + admins
    $acl = Get-Acl $homeDir
    $acl.SetAccessRuleProtection($true, $false)

    $ruleOwner = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $fullUsername, "FullControl",
        "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $ruleAdmin = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $adminName, "FullControl",
        "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $acl.AddAccessRule($ruleOwner)
    $acl.AddAccessRule($ruleAdmin)
    Set-Acl -Path $homeDir -AclObject $acl
    Write-Log "Permisos NTFS asignados en home '$homeDir'." "OK"
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

    # 1. Crear Usuario Local si no existe
    if (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {
        $secPwd = ConvertTo-SecureString $Password -AsPlainText -Force
        New-LocalUser -Name $Username -Password $secPwd -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
        Write-Log "Usuario '$Username' creado." "OK"
        Start-Sleep -Seconds 1
    }

    # 2. Gestionar pertenencia al grupo
    $otherGroup = if ($Group -eq "reprobados") { "recursadores" } else { "reprobados" }
    Remove-LocalGroupMember -Group $otherGroup -Member $Username -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group $Group -Member $Username -ErrorAction SilentlyContinue

    # 3. Crear Carpeta Personal (dentro del grupo)
    $groupFolder = if ($Group -eq "reprobados") { $REPROB_PATH } else { $RECURS_PATH }
    $userFolder  = "$groupFolder\$Username"

    if (-not (Test-Path $userFolder)) {
        New-Item -ItemType Directory -Path $userFolder -Force | Out-Null
    }

    # 4. Permisos NTFS: El usuario es dueño de su carpeta, pero el GRUPO tiene acceso por herencia
    # (Esto permite que los del mismo grupo colaboren)
    $acl = Get-Acl $userFolder
    $ruleOwner = New-Object System.Security.AccessControl.FileSystemAccessRule("$Username", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($ruleOwner)
    Set-Acl -Path $userFolder -AclObject $acl

    Write-Log "Usuario '$Username' configurado en grupo '$Group'." "OK"
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

    # Verificar que el usuario existe
    if (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {
        Write-Log "Usuario '$Username' no encontrado." "Error"
        return
    }

    # Detectar el grupo actual del usuario dinamicamente
    $grupovj = $null
    foreach ($g in $GROUPS) {
        $members = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue
        $encontrado = $members | Where-Object {
            ($_.Name -replace "^.*\\", "") -eq $Username
        }
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

    # Rutas en estructura /general
    $carpetavj = if ($grupovj -eq "reprobados") { "$REPROB_PATH\$Username" } else { "$RECURS_PATH\$Username" }
    $carpetanv = if ($gruponv -eq "reprobados") { "$REPROB_PATH\$Username" } else { "$RECURS_PATH\$Username" }

    # Cambiar grupos
    if ($grupovj) {
        Remove-LocalGroupMember -Group $grupovj -Member $Username -ErrorAction SilentlyContinue
        Write-Log "Usuario removido de '$grupovj'." "OK"
    }
    Add-LocalGroupMember -Group $gruponv -Member $Username -ErrorAction SilentlyContinue
    Write-Log "Usuario agregado a '$gruponv'." "OK"

    # Mover carpeta en /general
    if ($grupovj -and (Test-Path $carpetavj)) {
        if (Test-Path $carpetanv) {
            Get-ChildItem $carpetavj | Move-Item -Destination $carpetanv -Force
            Remove-Item $carpetavj -Recurse -Force
        } else {
            Move-Item -Path $carpetavj -Destination $carpetanv
        }
        Write-Log "Carpeta /general movida a: $carpetanv" "OK"
    } else {
        if (-not (Test-Path $carpetanv)) {
            New-Item -ItemType Directory -Path $carpetanv -Force | Out-Null
        }
    }

    # elimine lo de que la carpeta se elimine al cambiar de grupo

    crearHomeUsuario -Username $Username -Group $gruponv
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
        Start-Sleep -Seconds 3
        Clear-Host
        Write-Host ""
        Write-Host "--------------------------------------------" -ForegroundColor Magenta
        Write-Host "            GESTION SERVIDOR FTP            " -ForegroundColor Magenta
        Write-Host "--------------------------------------------" -ForegroundColor Magenta
        Write-Host "  1. Instalacion completa (primera vez)     " 
        Write-Host "  2. Inicializar directorios (primera vez)  " 
        Write-Host "  3. Crear usuarios                         " 
        Write-Host "  4. Cambiar grupo a un usuario             " 
        Write-Host "  5. Ver estado y diagnostico               " 
        Write-Host "  6. Salir                                  " 
        Write-Host "--------------------------------------------" -ForegroundColor Magenta
        Write-Host ""

        $opcion = Read-Host "Selecciona una opcion"

        switch ($opcion) {
            "1" {
                instalarFTP
                permisosBase
                Write-Log "Instalacion completada."
                Read-Host "`nPresiona Enter para continuar"
            }
            "2" {
                inicializarDirectorios
                inicializarGrupos
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
            "6" { Write-Host "Saliendo..."; return }
            default { Write-Log "Opcion no valida." "Warn" }
        }
    } while ($true)
}

# -----------------------------------------------------------------------------
#  MAIN
# -----------------------------------------------------------------------------
menuPrincipalFTP