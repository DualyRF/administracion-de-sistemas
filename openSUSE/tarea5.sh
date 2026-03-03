#!/bin/bash

# Cargar librerías 
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/librerias/varios.sh"
source "$SCRIPT_DIR/librerias/validar.sh"

# Variables Globales
readonly PAQUETE="vsftpd"
readonly VSFTPD_CONF="/etc/vsftpd.conf"
readonly FTP_ROOT="/srv/ftp"
readonly GRUPO_REPROBADOS="reprobados"
readonly GRUPO_RECURSADORES="recursadores"
readonly INTERFAZ_RED="enp0s9"
# Nuevas rutas necesarias para la lógica de aislamiento
readonly VSFTPD_USER_CONF_DIR="/etc/vsftpd/users"
readonly JAULAS_DIR="$FTP_ROOT/usuarios"

# Mostrar menú con los comandos para ayuda
ayuda() {
    echo "Uso del script: $0"
    echo "Opciones:"
    echo -e "  -vr, --verify       Verifica si esta instalado VSFTPD"
    echo -e "  -in, --install      Instala / Configura el servidor FTP"
    echo -e "  -us, --users        Gestionar a los usuarios FTP"
    echo -e "  -rs, --restart      Reiniciar el servidor FTP"
    echo -e "  -st, --status       Verificar el estado del servidor FTP"
    echo -e "  -ls, --list         Mostrar usuarios y estructura FTP"
    echo -e "  -?, --help          Muestra este menu"
}

# -------------
# Funciones para la base del servidor FTP
# -------------

crearBase() {
    print_info "Creando estructura de directorios con aislamiento..."
    
    # Directorios principales
    local dirs=("$FTP_ROOT" "$FTP_ROOT/general" "$FTP_ROOT/$GRUPO_REPROBADOS" "$FTP_ROOT/$GRUPO_RECURSADORES" "$FTP_ROOT/personal" "$JAULAS_DIR" "$VSFTPD_USER_CONF_DIR")
    
    for dir in "${dirs[@]}"; do
        [ ! -d "$dir" ] && sudo mkdir -p "$dir" && print_success "Creado: $dir"
    done
    
    # Permisos Estrictos
    sudo chown root:root "$FTP_ROOT"
    sudo chmod 755 "$FTP_ROOT"
    
    # Carpeta general (lectura para todos, escritura para grupo users)
    sudo chown root:users "$FTP_ROOT/general"
    sudo chmod 775 "$FTP_ROOT/general"
    
    # Carpetas de grupo: solo root y el grupo pueden entrar
    sudo chown root:"$GRUPO_REPROBADOS" "$FTP_ROOT/$GRUPO_REPROBADOS"
    sudo chmod 770 "$FTP_ROOT/$GRUPO_REPROBADOS"
    
    sudo chown root:"$GRUPO_RECURSADORES" "$FTP_ROOT/$GRUPO_RECURSADORES"
    sudo chmod 770 "$FTP_ROOT/$GRUPO_RECURSADORES"

    sudo chown root:root "$JAULAS_DIR"
    sudo chmod 755 "$JAULAS_DIR"
}

crearGrupos() {
    print_info "Configurando grupos..."
    for grupo in "$GRUPO_REPROBADOS" "$GRUPO_RECURSADORES"; do
        if ! getent group "$grupo" &>/dev/null; then
            sudo groupadd "$grupo"
            print_success "Grupo '$grupo' creado"
        fi
    done
}

# -------------
# Funciones de JAULA (Aislamiento real)
# -------------

construirJaula() {
    local usuario="$1"
    local grupo="$2"
    local jaula="$JAULAS_DIR/$usuario"

    print_info "Construyendo aislamiento para '$usuario'..."

    # La raíz de la jaula DEBE ser propiedad de root para vsftpd chroot
    sudo mkdir -p "$jaula"
    sudo chown root:root "$jaula"
    sudo chmod 755 "$jaula"

    # Puntos de montaje (carpetas que el usuario verá al entrar)
    sudo mkdir -p "$jaula/general" "$jaula/$grupo" "$jaula/mi_espacio"

    # Realizar Bind Mounts (Espejos de las carpetas reales)
    sudo mount --bind "$FTP_ROOT/general" "$jaula/general"
    sudo mount --bind "$FTP_ROOT/$grupo" "$jaula/$grupo"
    sudo mount --bind "$FTP_ROOT/personal/$usuario" "$jaula/mi_espacio"

    # Configuración individual para decirle a vsftpd dónde "aterriza" este usuario
    echo "local_root=$jaula" | sudo tee "$VSFTPD_USER_CONF_DIR/$usuario" > /dev/null
}

destruirJaula() {
    local usuario="$1"
    local jaula="$JAULAS_DIR/$usuario"

    print_info "Removiendo aislamiento de '$usuario'..."
    
    # Desmontar todo
    for p en "general" "$GRUPO_REPROBADOS" "$GRUPO_RECURSADORES" "mi_espacio"; do
        sudo umount "$jaula/$p" 2>/dev/null
    done

    sudo rm -f "$VSFTPD_USER_CONF_DIR/$usuario"
    sudo rm -rf "$jaula"
}

# -------------
# Funciones para instalar y configurar servidor FTP
# -------------

configurarVSFTPD() {
    print_info "Configurando vsftpd con soporte para jaulas..."
    
    sudo tee "$VSFTPD_CONF" > /dev/null << EOF
listen=YES
listen_ipv6=NO
local_enable=YES
write_enable=YES
local_umask=022

# Acceso anónimo a la carpeta general
anonymous_enable=YES
anon_root=$FTP_ROOT/general
no_anon_password=YES

# AISLAMIENTO (Chroot)
chroot_local_user=YES
allow_writeable_chroot=YES
user_config_dir=$VSFTPD_USER_CONF_DIR

# Seguridad y Puertos
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
userlist_enable=YES
userlist_deny=NO
userlist_file=/etc/vsftpd.user_list
ftpd_banner=Servidor FTP con Aislamiento de Grupos
EOF
}

instalarFTP() {
    print_titulo "Instalación de Servidor FTP Protegido"
    
    if ! verificarVSFTPD; then
        sudo zypper --non-interactive install $PAQUETE
    fi
    
    crearGrupos
    crearBase
    configurarVSFTPD
    
    # Asegurar que nologin sea válido para el shell
    if ! grep -q "/sbin/nologin" /etc/shells; then
        echo "/sbin/nologin" | sudo tee -a /etc/shells
    fi

    sudo systemctl enable vsftpd
    sudo systemctl restart vsftpd
    print_success "Servidor instalado y configurado"
}

# -------------
# Gestión de Usuarios
# -------------

crearUsuarioFTP() {
    local usuario="$1"
    local password="$2"
    local grupo="$3"
    
    # 1. Crear usuario en el sistema (sin home tradicional, usa nologin)
    sudo useradd -M -s /sbin/nologin -g "$grupo" -G users "$usuario"
    echo "$usuario:$password" | sudo chpasswd
    
    # 2. Crear su carpeta física real donde se guardan sus datos
    local dir_real="$FTP_ROOT/personal/$usuario"
    sudo mkdir -p "$dir_real"
    sudo chown "$usuario:$grupo" "$dir_real"
    sudo chmod 700 "$dir_real"
    
    # 3. Construir la jaula (Aislamiento)
    construirJaula "$usuario" "$grupo"
    
    # 4. Permitir entrada en vsftpd
    echo "$usuario" | sudo tee -a /etc/vsftpd.user_list > /dev/null
    
    print_success "Usuario '$usuario' creado y aislado en grupo '$grupo'"
}

cambioGrupo() {
    local usuario="$1"
    [ ! id "$usuario" &>/dev/null ] && print_warning "Usuario no existe" && return 1
    
    local grupo_actual=$(id -gn "$usuario")
    echo "1) $GRUPO_REPROBADOS | 2) $GRUPO_RECURSADORES"
    read -p "Nuevo grupo [1-2]: " opc
    local nuevo_grupo=$([ "$opc" == "1" ] && echo "$GRUPO_REPROBADOS" || echo "$GRUPO_RECURSADORES")

    if [ "$grupo_actual" == "$nuevo_grupo" ]; then
        print_info "Ya pertenece a ese grupo"
        return 0
    fi

    # Para cambiar de grupo y mantener aislamiento:
    destruirJaula "$usuario"
    sudo usermod -g "$nuevo_grupo" "$usuario"
    construirJaula "$usuario" "$nuevo_grupo"
    
    print_success "Usuario movido: $grupo_actual -> $nuevo_grupo. Ahora solo verá carpetas de $nuevo_grupo"
}

gestionUsuarios() {
    print_titulo "Gestión de Usuarios FTP"
    echo "1) Crear | 2) Cambiar Grupo | 3) Eliminar | 4) Volver"
    read -p "Opción: " opcion
    
    case $opcion in
        1)
            read -p "Nombre: " usuario
            read -s -p "Pass: " password; echo ""
            echo "1) $GRUPO_REPROBADOS | 2) $GRUPO_RECURSADORES"
            read -p "Grupo: " gopc
            local grupo=$([ "$gopc" == "1" ] && echo "$GRUPO_REPROBADOS" || echo "$GRUPO_RECURSADORES")
            crearUsuarioFTP "$usuario" "$password" "$grupo"
            ;;
        2)
            read -p "Usuario: " usuario
            cambioGrupo "$usuario"
            ;;
        3)
            read -p "Usuario a eliminar: " usuario
            destruirJaula "$usuario"
            sudo userdel -r "$usuario"
            sudo sed -i "/^$usuario$/d" /etc/vsftpd.user_list
            print_success "Usuario eliminado"
            ;;
    esac
}

# -------------
# Estado y Diagnóstico
# -------------

verificarVSFTPD() {
    rpm -q $PAQUETE &>/dev/null && return 0 || return 1
}

verEstadoServ() {
    sudo systemctl status vsftpd --no-pager
    print_info "Usuarios enjaulados actualmente:"
    ls "$JAULAS_DIR"
}

mostrarEstructura() {
    print_titulo "Estructura del Servidor"
    if command -v tree &>/dev/null; then
        sudo tree -L 3 "$FTP_ROOT"
    else
        sudo find "$FTP_ROOT" -maxdepth 3
    fi
}

reiniciarFTP() {
    sudo systemctl restart vsftpd
    print_success "Servicio reiniciado"
}

# VERIFICAR PERMISOS DE ROOT
if [[ $EUID -ne 0 ]]; then
    print_warning "Este script debe ejecutarse como root o con sudo"
    exit 1
fi

# Main
case $1 in
    -vr | --verify)  verificarVSFTPD ;;
    -in | --install) instalarFTP ;;
    -us | --users)   gestionUsuarios ;;
    -st | --status)  verEstadoServ ;;
    -rs | --restart) reiniciarFTP ;;
    -ls | --list)    mostrarEstructura ;;
    *)              ayuda ;;
esac