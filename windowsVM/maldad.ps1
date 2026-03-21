$archivo = "C:\Users\Administrador\Desktop\administracion-de-sistemas\windowsVM\practica8\tarea8.ps1"

$contenido = Get-Content $archivo -Raw

$funcionNueva = @'
function configurarAppLocker {
    $rutaNotepad = "$env:SystemRoot\System32\notepad.exe"

    if (-not (Test-Path $rutaNotepad)) {
        Print-Err "No se encontro notepad.exe en $rutaNotepad"
        return
    }

    Print-Info "Calculando hash SHA256 de notepad.exe..."
    $info   = Get-AppLockerFileInformation -Path $rutaNotepad
    $hash   = $info.Hash[0].HashDataString
    $tamano = (Get-Item $rutaNotepad).Length

    $sidCuates   = (Get-ADGroup -Identity "Cuates").SID.Value
    $sidNoCuates = (Get-ADGroup -Identity "NoCuates").SID.Value
    $sidAdmins   = "S-1-5-32-544"

    $g1 = [System.Guid]::NewGuid().ToString()
    $g2 = [System.Guid]::NewGuid().ToString()
    $g3 = [System.Guid]::NewGuid().ToString()
    $g4 = [System.Guid]::NewGuid().ToString()

    Print-Info "Generando politica XML de AppLocker..."

    $xml = "<?xml version=""1.0"" encoding=""utf-8""?>`n"
    $xml += "<AppLockerPolicy Version=""1"">`n"
    $xml += "  <RuleCollection Type=""Exe"" EnforcementMode=""Enabled"">`n"
    $xml += "    <FilePathRule Id=""$g1"" Name=""Admins - permitir todo"" Description=""Administradores sin restricciones"" UserOrGroupSid=""$sidAdmins"" Action=""Allow"">`n"
    $xml += "      <Conditions><FilePathCondition Path=""*""/></Conditions>`n"
    $xml += "    </FilePathRule>`n"
    $xml += "    <FilePathRule Id=""$g2"" Name=""Cuates - permitir notepad"" Description=""Cuates pueden usar notepad"" UserOrGroupSid=""$sidCuates"" Action=""Allow"">`n"
    $xml += "      <Conditions><FilePathCondition Path=""%SYSTEM32%\notepad.exe""/></Conditions>`n"
    $xml += "    </FilePathRule>`n"
    $xml += "    <FileHashRule Id=""$g3"" Name=""NoCuates - bloquear notepad por hash"" Description=""Bloqueo por hash resiste renombrado"" UserOrGroupSid=""$sidNoCuates"" Action=""Deny"">`n"
    $xml += "      <Conditions>`n"
    $xml += "        <FileHashCondition>`n"
    $xml += "          <FileHash Type=""SHA256"" Data=""$hash"" SourceFileName=""notepad.exe"" SourceFileLength=""$tamano""/>`n"
    $xml += "        </FileHashCondition>`n"
    $xml += "      </Conditions>`n"
    $xml += "    </FileHashRule>`n"
    $xml += "    <FilePathRule Id=""$g4"" Name=""NoCuates - permitir carpeta Windows"" Description=""Permitir ejecucion desde Windows"" UserOrGroupSid=""$sidNoCuates"" Action=""Allow"">`n"
    $xml += "      <Conditions><FilePathCondition Path=""%WINDIR%\*""/></Conditions>`n"
    $xml += "    </FilePathRule>`n"
    $xml += "  </RuleCollection>`n"
    $xml += "</AppLockerPolicy>"

    $rutaXML = "C:\applocker-policy.xml"
    $xml | Out-File $rutaXML -Encoding UTF8
    Print-Ok "XML guardado en $rutaXML"

    $nombreGPO = "GPO-AppLocker"

    if (-not (Get-GPO -Name $nombreGPO -ErrorAction SilentlyContinue)) {
        New-GPO -Name $nombreGPO | Out-Null
        Print-Ok "GPO creada: $nombreGPO"
    } else {
        Print-Warn "GPO ya existe: $nombreGPO"
    }

    try {
        New-GPLink -Name $nombreGPO -Target $DC_PATH -LinkEnabled Yes -ErrorAction Stop
        Print-Ok "GPO AppLocker vinculada al dominio."
    } catch {
        Print-Warn "Vinculo de GPO ya existe."
    }

    Set-AppLockerPolicy -XMLPolicy $rutaXML -Merge

    Start-Service -Name AppIDSvc -ErrorAction SilentlyContinue

    Invoke-GPUpdate -Force -ErrorAction SilentlyContinue

    Print-Ok "AppLocker configurado correctamente."
}
'@

# Reemplazar la funcion en el archivo
$inicio = $contenido.IndexOf("function configurarAppLocker {")
$fin    = $contenido.IndexOf("`nfunction verificar")
$contenidoNuevo = $contenido.Substring(0, $inicio) + $funcionNueva + "`n`n" + $contenido.Substring($fin)
$contenidoNuevo | Set-Content $archivo -Encoding UTF8

Write-Host "Funcion reemplazada correctamente." -ForegroundColor Green