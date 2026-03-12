# colores en variables
rojo='\033[0;95m'  
amarillo='\033[1;93m'
verde='\033[0;96m'
azul='\033[1;34m'
nc='\033[0m'
cyan='\033[0;36m'

# Funciones para imprimir mensajes 
print_warning(){
    echo -e "${rojo}$1${nc}"
}

print_success(){
    echo -e "${verde}$1${nc}"
}

print_info(){
    echo -e "${amarillo}$1${nc}"
}

print_menu(){
    echo -e "${cyan}$1${nc}"
}

print_title(){ 
    echo -e "\n${azul}========================================${nc}";
    echo -e "${azul}  $1${nc}";
    echo -e "${azul}========================================${nc}\n"; 
}

# -----------------------------------------------------------------------------
# VERIFICAR ROOT
# -----------------------------------------------------------------------------
verificar_root() {
    if (( EUID != 0 )); then
        print_warning "[ERROR] Este script debe ejecutarse como root (o con sudo)."
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# VERIFICAR QUE UN COMANDO EXISTE
# Uso: requiere_comando "zypper"
# -----------------------------------------------------------------------------
requiere_comando() {
    if ! command -v "$1" &>/dev/null; then
        print_warning "[ERROR] Comando requerido no encontrado: $1"
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# VALIDAR INPUT GENÉRICO
# Uso: validar_input "valor" "nombre_campo"
# Rechaza: vacíos y caracteres peligrosos
# -----------------------------------------------------------------------------
validar_input() {
    local valor="$1"
    local campo="$2"

    if [[ -z "$valor" ]]; then
        print_warning "[ERROR] El campo '$campo' no puede estar vacío."
        return 1
    fi

    if [[ "$valor" =~ [';|&$<>(){}\\`!'] ]]; then
        print_warning "[ERROR] El campo '$campo' contiene caracteres no permitidos."
        return 1
    fi

    return 0
}

# -----------------------------------------------------------------------------
# VALIDAR PUERTO
# Uso: validar_puerto "8080"
# Verifica: que sea número, rango 1024-65535, no reservado, no ocupado
# -----------------------------------------------------------------------------
PUERTOS_RESERVADOS=(22 21 23 25 53 110 143 443 3306 5432 6379 27017)

validar_puerto() {
    local puerto="$1"

    if ! [[ "$puerto" =~ ^[0-9]+$ ]]; then
        print_warning "[ERROR] El puerto debe ser un número entero."
        return 1
    fi

    if (( puerto < 1024 || puerto > 65535 )); then
        print_warning "[ERROR] Puerto $puerto fuera de rango permitido (1024-65535)."
        return 1
    fi

    for reservado in "${PUERTOS_RESERVADOS[@]}"; do
        if (( puerto == reservado )); then
            print_warning "[ERROR] Puerto $puerto reservado para otro servicio del sistema."
            return 1
        fi
    done

    local ss_output
    ss_output=$(/usr/bin/ss -tulnp 2>/dev/null | grep ":${puerto}")

    if [[ -n "$ss_output" ]]; then
        # Extraer nombre del proceso desde users:(("nombre",pid=X,fd=X))
        local proceso_raw proceso_nombre proceso_pid
        proceso_raw=$(echo "$ss_output" | grep -oP 'users:\(\(.*?\)\)' | head -1)
        proceso_nombre=$(echo "$proceso_raw" | grep -oP '(?<=")[^"]+(?=")' | head -1)
        proceso_pid=$(echo "$proceso_raw" | grep -oP 'pid=\K[0-9]+' | head -1)

        print_warning "[ERROR] Puerto $puerto ya está en uso."
        if [[ -n "$proceso_nombre" ]]; then
            print_warning "        Proceso : $proceso_nombre"
            print_warning "        PID     : $proceso_pid"
        else
            print_warning "        (ejecuta como root para ver el proceso)"
        fi
        return 1
    fi

    print_success "[OK] Puerto $puerto disponible."
    return 0
}

# -----------------------------------------------------------------------------
# PEDIR PUERTO AL USUARIO (con reintentos)
# Exporta: PUERTO_ELEGIDO
# -----------------------------------------------------------------------------
pedir_puerto() {
    local intentos=0
    local max_intentos=3

    while (( intentos < max_intentos )); do
        echo -ne "${cyan}Ingresa el puerto de escucha (ej. 8080, 8888): ${nc}"
        read -r puerto_raw

        if validar_input "$puerto_raw" "puerto" && validar_puerto "$puerto_raw"; then
            export PUERTO_ELEGIDO="$puerto_raw"
            return 0
        fi

        (( intentos++ ))
        print_info "[WARN] Intento $intentos de $max_intentos."
    done

    print_warning "[ERROR] Demasiados intentos fallidos al ingresar el puerto."
    return 1
}

# -----------------------------------------------------------------------------
# ABRIR PUERTO EN FIREWALL (firewalld — OpenSUSE)
# Uso: abrir_puerto_firewall "8080"
# Cierra el puerto 80 por defecto si el usuario eligió otro
# -----------------------------------------------------------------------------
abrir_puerto_firewall() {
    local puerto="$1"

    if ! requiere_comando "firewall-cmd"; then
        print_info "[WARN] firewalld no encontrado. Saltando configuración de firewall."
        return 0
    fi

    print_info "[INFO] Abriendo puerto $puerto/tcp en firewalld..."
    firewall-cmd --permanent --add-port="${puerto}/tcp" &>/dev/null

    if (( puerto != 80 )); then
        if firewall-cmd --list-ports 2>/dev/null | grep -q "80/tcp"; then
            print_info "[INFO] Cerrando puerto 80 por defecto (no utilizado)..."
            firewall-cmd --permanent --remove-port="80/tcp" &>/dev/null
        fi
        if firewall-cmd --list-services 2>/dev/null | grep -q "\bhttp\b"; then
            firewall-cmd --permanent --remove-service="http" &>/dev/null
        fi
    fi

    firewall-cmd --reload &>/dev/null

    # Registrar el puerto en SELinux si está en modo Enforcing
    if command -v getenforce &>/dev/null && [[ "$(getenforce)" == "Enforcing" ]]; then
        if command -v semanage &>/dev/null; then
            if ! semanage port -l 2>/dev/null | grep "http_port_t" | grep -q "${puerto}"; then
                semanage port -a -t http_port_t -p tcp "$puerto" 2>/dev/null
                print_info "[INFO] Puerto $puerto registrado en SELinux."
            fi
        else
            print_info "[WARN] semanage no encontrado. Instala: zypper install -y policycoreutils-python-utils"
        fi
    fi

    print_success "[OK] Firewall actualizado. Puerto $puerto habilitado."
}

# -----------------------------------------------------------------------------
# CREAR USUARIO DEDICADO PARA UN SERVICIO
# Uso: crear_usuario_servicio "apache" "/srv/www"
# -----------------------------------------------------------------------------
crear_usuario_servicio() {
    local usuario="$1"
    local directorio="$2"

    if id "$usuario" &>/dev/null; then
        print_info "[INFO] Usuario '$usuario' ya existe."
    else
        print_info "[INFO] Creando usuario dedicado '$usuario'..."
        useradd --system \
                --no-create-home \
                --shell /sbin/nologin \
                --home-dir "$directorio" \
                "$usuario" 2>/dev/null
        print_success "[OK] Usuario '$usuario' creado."
    fi

    if [[ -d "$directorio" ]]; then
        chown -R "${usuario}:${usuario}" "$directorio"
        chmod 750 "$directorio"
        print_success "[OK] Permisos aplicados en $directorio para '$usuario'."
    fi
}

# -----------------------------------------------------------------------------
# CREAR INDEX.HTML PERSONALIZADO
# Uso: crear_index "Apache2" "2.4.58" "8080" "/srv/www/htdocs"
# -----------------------------------------------------------------------------
crear_index() {
    local servicio="$1"
    local version="$2"
    local puerto="$3"
    local ruta_web="$4"

    mkdir -p "$ruta_web"

    cat > "${ruta_web}/index.html" <<EOF

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title> Servidor HTTP UwU </title>

    <style>
        .infoServ { 
            background:#252526; 
            border:1px solid #3c3c3c; 
            padding:2rem 3rem;
            border-radius:8px; 
            text-align:center; 
        }
        span { 
            color: #f44462; 
        }
        h1 { 
            color: #982f4a; 
        }
    </style>

</head>
<body style="background-color: rgb(255, 226, 231)">
    <h1> KiiiKiii 키키 '404 (New Era)' Audio </h1>
    <p><img src="kiikii.webp" width="300" height="300"> </p>
    
    <p>
    <audio controls>
        <source src="404(New-Era).mp3" type="audio/mpeg">
        <source src="audio.ogg" type="audio/ogg">
            Tu navegador no soporta la etiqueta de audio.
    </audio>
    </p>

    <div class="infoServ">
        <h1>Servidor Activo!!</h1>
        <p>Servidor : <span>$servicio</span></p>
        <p>Versión  : <span>$version</span></p>
        <p>Puerto   : <span>$puerto</span></p>
        <p> Disfruta la canción :3 </p>
    </div>

</body>
</html>


EOF

    print_success "[OK] index.html creado en $ruta_web"
}