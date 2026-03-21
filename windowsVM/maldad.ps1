$archivo = "C:\Users\Administrador\Desktop\administracion-de-sistemas\windowsVM\practica8\tarea8.ps1"

(Get-Content $archivo) -replace '-SoftLimit\s+\$false', '' | Set-Content $archivo

Write-Host "Corregido." -ForegroundColor Green