$archivo = "C:\Users\Administrador\Desktop\administracion-de-sistemas\windowsVM\practica8\tarea8.ps1"
(Get-Content $archivo) -replace '-Force\s+\$true', '-Force' | Set-Content $archivo