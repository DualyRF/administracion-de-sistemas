#!/bin/bash

# Cargar librerías 
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/librerias/varios.sh"
source "$SCRIPT_DIR/librerias/validar.sh"

# Variables Globales
readonly PAQUETE="vsftpd"
readonly VSFTPD_CONF="/etc/vsftpd.conf"
readonly FTP_ROOT="/srv/ftp"
readonly VSFTPD_USER_CONF_DIR="/etc/vsftpd/users"
readonly GRUPO_REPROBADOS="reprobados"
readonly GRUPO_RECURSADORES="recursadores"
readonly INTERFAZ_RED="enp0s9"

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
# Funciones de formato para textos en pantalla
# -------------
print_info()       { echo -e "${azul}[INFO]${nc} $1"; }
print_completado() { echo -e "${verde}[OK]${nc}   $1"; }
print_error()      { echo -e "${rojo}[ERROR]${nc} $1"; }
print_titulo()     { echo -e "\n${negrita}${amarillo}=== $1 ===${nc}\n"; }


# -------------
# Funciones para la base del servidor FTP
# -------------

crearBase() {
    print_info "Creando estructura de directorios con aislamiento..."

    local dirs=(
        "$FTP_ROOT"
        "$FTP_ROOT/general"
        "$FTP_ROOT/$GRUPO_REPROBADOS"
        "$FTP_ROOT/$GRUPO_RECURSADORES"
        "$FTP_ROOT/personal"
        "$JAULAS_DIR"
        "$VSFTPD_USER_CONF_DIR"
    )

    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            sudo mkdir -p "$dir"
            print_success "Creado: $dir"
        fi
    done

    sudo chown root:root "$FTP_ROOT"
    sudo chmod 755 "$FTP_ROOT"

    sudo chown root:users "$FTP_ROOT/general"
    sudo chmod 775 "$FTP_ROOT/general"

    sudo chown root:"$GRUPO_REPROBADOS" "$FTP_ROOT/$GRUPO_REPROBADOS"
    sudo chmod 775 "$FTP_ROOT/$GRUPO_REPROBADOS"

    sudo chown root:"$GRUPO_RECURSADORES" "$FTP_ROOT/$GRUPO_RECURSADORES"
    sudo chmod 775 "$FTP_ROOT/$GRUPO_RECURSADORES"

    sudo chown root:root "$FTP_ROOT/personal"
    sudo chmod 755 "$FTP_ROOT/personal"

    sudo chown root:root "$JAULAS_DIR"
    sudo chmod 755 "$JAULAS_DIR"

    print_success "Estructura base configurada"
}

crearGrupos() {
    print_info "Configurando grupos..."
    for grupo in "$GRUPO_REPROBADOS" "$GRUPO_RECURSADORES"; do
        if ! getent group "$grupo" &>/dev/null; then
            sudo groupadd "$grupo"
            print_success "Grupo '$grupo' creado"
        else
            print_info "Grupo '$grupo' ya existe"
        fi
    done
}

crearCarpetaPersonal() {
    local usuario="$1"
    local grupo="$2"
    local carpeta_real="$FTP_ROOT/personal/$usuario"

    if [ ! -d "$carpeta_real" ]; then
        sudo mkdir -p "$carpeta_real"
        sudo chown "$usuario:$grupo" "$carpeta_real"
        sudo chmod 700 "$carpeta_real"
        print_success "Carpeta personal: $carpeta_real"
    fi
}

# -------------
# Funciones de JAULA (Aislamiento real)
# -------------

construirJaula() {
    local usuario="$1"
    local grupo="$2"
    local jaula="$JAULAS_DIR/$usuario"

    print_info "Construyendo aislamiento para '$usuario'..."

    # Raiz de la jaula: DEBE ser root:root y no escribible (requisito vsftpd chroot)
    sudo mkdir -p "$jaula"
    sudo chown root:root "$jaula"
    sudo chmod 755 "$jaula"

    # Puntos de montaje dentro de la jaula
    sudo mkdir -p "$jaula/general"
    sudo chown root:root "$jaula/general"
    sudo chmod 755 "$jaula/general"

    sudo mkdir -p "$jaula/$grupo"
    sudo chown root:root "$jaula/$grupo"
    sudo chmod 755 "$jaula/$grupo"

    sudo mkdir -p "$jaula/$usuario"
    sudo chown "$usuario:$grupo" "$jaula/$usuario"
    sudo chmod 700 "$jaula/$usuario"

    # Bind mounts: conectar carpetas reales con la jaula
    if ! mountpoint -q "$jaula/general" 2>/dev/null; then
        sudo mount --bind "$FTP_ROOT/general" "$jaula/general"
        print_success "Bind mount: general"
    fi

    if ! mountpoint -q "$jaula/$grupo" 2>/dev/null; then
        sudo mount --bind "$FTP_ROOT/$grupo" "$jaula/$grupo"
        print_success "Bind mount: $grupo"
    fi

    if ! mountpoint -q "$jaula/$usuario" 2>/dev/null; then
        sudo mount --bind "$FTP_ROOT/personal/$usuario" "$jaula/$usuario"
        print_success "Bind mount: $usuario (personal)"
    fi

    # Persistencia en /etc/fstab para que sobreviva reinicios
    local fstab_entries=(
        "$FTP_ROOT/general  $jaula/general  none  bind  0  0"
        "$FTP_ROOT/$grupo  $jaula/$grupo  none  bind  0  0"
        "$FTP_ROOT/personal/$usuario  $jaula/$usuario  none  bind  0  0"
    )

    for entry in "${fstab_entries[@]}"; do
        if ! grep -Fx "$entry" /etc/fstab >/dev/null; then
            echo "$entry" >> /etc/fstab
            print_success "fstab: $(echo $entry | awk '{print $2}')"
        fi
    done

    # Archivo de configuracion individual para vsftpd
    echo "local_root=$jaula" | sudo tee "$VSFTPD_USER_CONF_DIR/$usuario" > /dev/null
    print_success "Config individual: $VSFTPD_USER_CONF_DIR/$usuario"
    print_success "Jaula lista: $jaula"
}

destruirJaula() {
    local usuario="$1"
    local jaula="$JAULAS_DIR/$usuario"

    print_info "Removiendo aislamiento de '$usuario'..."

    for punto in "$jaula/$usuario" "$jaula/$GRUPO_REPROBADOS" "$jaula/$GRUPO_RECURSADORES" "$jaula/general"; do
        if mountpoint -q "$punto" 2>/dev/null; then
            sudo umount "$punto" && print_success "Desmontado: $punto"
        fi
    done

    sed -i "\| $jaula/general |d" /etc/fstab
    sed -i "\| $jaula/$GRUPO_REPROBADOS |d" /etc/fstab
    sed -i "\| $jaula/$GRUPO_RECURSADORES |d" /etc/fstab
    sed -i "\| $jaula/$usuario |d" /etc/fstab

    sudo rm -f "$VSFTPD_USER_CONF_DIR/$usuario"
    sudo rm -rf "$jaula"
    print_success "Jaula eliminada"
}

# -------------
# Funciones para instalar y configurar servidor FTP
# -------------

configurarVSFTPD() {
    print_info "Configurando vsftpd con soporte para jaulas..."

    if [ -f "$VSFTPD_CONF" ]; then
        cp "$VSFTPD_CONF" "${VSFTPD_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
        print_info "Backup creado"
    fi

    sudo mkdir -p "$VSFTPD_USER_CONF_DIR"

    sudo tee "$VSFTPD_CONF" > /dev/null << EOF
# ============================================================
# Configuracion vsftpd - Servidor FTP Seguro
# ============================================================

listen=YES
listen_ipv6=NO

# --- Usuarios locales ---
local_enable=YES
write_enable=YES
local_umask=022
chmod_enable=YES
session_support=YES

# --- Anonimo (solo lectura a /general) ---
anonymous_enable=YES
anon_root=$FTP_ROOT/general
no_anon_password=YES
anon_upload_enable=NO
anon_mkdir_write_enable=NO
anon_other_write_enable=NO

# --- Chroot / Aislamiento por usuario ---
chroot_local_user=YES
allow_writeable_chroot=YES
user_sub_token=\$USER
local_root=$FTP_ROOT/usuarios/\$USER
user_config_dir=$VSFTPD_USER_CONF_DIR

# --- Seguridad ---
hide_ids=YES
use_localtime=YES

# --- Permisos ---
file_open_mode=0666
local_umask=022

# --- Logging ---
xferlog_enable=YES
xferlog_file=/var/log/vsftpd.log
log_ftp_protocol=YES

# --- Conexion ---
connect_from_port_20=YES
idle_session_timeout=600
data_connection_timeout=120

ftpd_banner=Bienvenido al servidor FTP - Acceso restringido

# --- Modo pasivo ---
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100

# --- Lista blanca de usuarios ---
userlist_enable=YES
userlist_deny=NO
userlist_file=/etc/vsftpd.user_list
EOF

    print_success "vsftpd.conf creado"

    [ ! -f /etc/vsftpd.user_list ] && touch /etc/vsftpd.user_list && \
        print_success "Archivo user_list creado"

    for u in anonymous ftp; do
        if ! grep -q "^$u$" /etc/vsftpd.user_list; then
            echo "$u" >> /etc/vsftpd.user_list
            print_success "Usuario '$u' agregado a user_list"
        fi
    done

    if ! id ftp &>/dev/null; then
        useradd -r -d "$FTP_ROOT/general" -s /sbin/nologin ftp
        print_success "Usuario 'ftp' (anonimo) creado"
    fi
}

instalarFTP() {
    print_titulo "Instalacion de Servidor FTP Protegido"

    if verificarVSFTPD; then
        read -rp "vsftpd ya esta instalado. Reconfigurar? [s/N]: " reconf
        if [[ ! "$reconf" =~ ^[Ss]$ ]]; then
            print_info "Operacion cancelada"
            return 0
        fi
    else
        print_info "Instalando vsftpd con zypper..."
        sudo zypper --non-interactive install $PAQUETE
        if [ $? -eq 0 ]; then
            print_success "vsftpd instalado"
        else
            print_error "Error en la instalacion"
            return 1
        fi
    fi

    echo ""
    configurarSELinux
    echo ""
    crearGrupos
    echo ""
    crearBase
    echo ""
    configurarVSFTPD
    echo ""
    configurarPAM
    echo ""

    print_info "Habilitando y arrancando vsftpd..."
    sudo systemctl enable vsftpd 2>/dev/null && print_success "Servicio habilitado"

    if systemctl is-active --quiet vsftpd; then
        sudo systemctl restart vsftpd && print_success "Servicio reiniciado"
    else
        sudo systemctl start vsftpd && print_success "Servicio iniciado"
    fi

    if ! systemctl is-active --quiet vsftpd; then
        print_error "El servicio no pudo iniciar"
        print_error "Revise: journalctl -xeu vsftpd.service"
        return 1
    fi

    # Configuracion de firewall
    print_info "Configurando firewall..."
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --add-service=ftp --permanent 2>/dev/null && \
            print_success "Puerto 21 abierto (firewalld)"
        firewall-cmd --add-port=40000-40100/tcp --permanent 2>/dev/null && \
            print_success "Puertos pasivos abiertos (firewalld)"
        firewall-cmd --reload 2>/dev/null && print_success "Firewall recargado"
    elif command -v SuSEfirewall2 &>/dev/null; then
        sed -i 's/^FW_SERVICES_EXT_TCP.*/FW_SERVICES_EXT_TCP="ftp"/' /etc/sysconfig/SuSEfirewall2
        echo "FW_SERVICES_EXT_TCP=\"40000:40100\"" >> /etc/sysconfig/SuSEfirewall2
        systemctl restart SuSEfirewall2 && print_success "SuSEfirewall2 recargado"
    else
        print_warning "No se detecto firewall. Abra manualmente 21/tcp y 40000-40100/tcp."
    fi

    local ip
    ip=$(ip addr show $INTERFAZ_RED 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    [ -z "$ip" ] && \
        ip=$(ip addr | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -1)

    echo ""
    print_success "Servidor FTP listo"
    print_info "  IP             : $ip"
    print_info "  Puerto         : 21"
    print_info "  Acceso anonimo : ftp://$ip  (solo lectura en /general)"
    print_info "  Jaulas         : $FTP_ROOT/usuarios/<nombre>/"
    echo ""
    print_info "Cree usuarios con: $0 -us"
}


# -------------
# Configuraciones para VSFTPD
# -------------
configurarPAM() {
    print_info "Configurando PAM para vsftpd..."

    tee /etc/pam.d/ftp > /dev/null << 'EOF'
auth     required    pam_unix.so     shadow nullok
account  required    pam_unix.so
session  required    pam_unix.so
EOF
    print_success "PAM configurado en /etc/pam.d/ftp"

    if ! grep -q "^/sbin/nologin$" /etc/shells; then
        echo "/sbin/nologin" >> /etc/shells
        print_success "/sbin/nologin agregado a /etc/shells"
    else
        print_info "/sbin/nologin ya esta en /etc/shells"
    fi
}

configurarSELinux() {
    print_info "Verificando SELinux..."

    if ! command -v getenforce &>/dev/null; then
        print_info "SELinux no esta presente en este sistema"
        return 0
    fi

    local estado
    estado=$(getenforce 2>/dev/null)
    print_info "Estado actual de SELinux: $estado"

    if ! command -v semanage &>/dev/null && [ ! -f /usr/sbin/semanage ]; then
        print_info "Instalando policycoreutils-python-utils..."
        zypper --non-interactive --quiet install policycoreutils-python-utils
    fi

    setsebool -P ftpd_full_access on 2>/dev/null && \
        print_success "Booleano ftpd_full_access activado"

    /usr/sbin/semanage fcontext -a -t public_content_rw_t "$FTP_ROOT(/.*)?" 2>/dev/null || \
    /usr/sbin/semanage fcontext -m -t public_content_rw_t "$FTP_ROOT(/.*)?" 2>/dev/null
    print_success "Contexto SELinux aplicado a $FTP_ROOT"

    restorecon -Rv "$FTP_ROOT" 2>/dev/null && \
        print_success "Contextos restaurados con restorecon"

    print_success "SELinux configurado para vsftpd"
}


# -------------
# Gestión de Usuarios
# -------------

crearUsuarioFTP() {
    local usuario="$1"
    local password="$2"
    local grupo="$3"

    print_info "Creando usuario '$usuario' en grupo '$grupo'..."

    sudo useradd \
        -M \
        -d "$JAULAS_DIR/$usuario" \
        -s /sbin/nologin \
        -g "$grupo" \
        -G users \
        "$usuario" 2>/dev/null

    if [ $? -ne 0 ]; then
        print_error "Error al crear el usuario '$usuario'"
        return 1
    fi
    print_success "Usuario del sistema creado"

    echo "$usuario:$password" | sudo chpasswd
    if [ $? -ne 0 ]; then
        print_error "Error al establecer contrasena"
        sudo userdel "$usuario" 2>/dev/null
        return 1
    fi
    print_success "Contrasena establecida"

    crearCarpetaPersonal "$usuario" "$grupo"
    construirJaula "$usuario" "$grupo"

    if ! grep -q "^$usuario$" /etc/vsftpd.user_list 2>/dev/null; then
        echo "$usuario" | sudo tee -a /etc/vsftpd.user_list > /dev/null
        print_success "Agregado a /etc/vsftpd.user_list"
    fi

    echo ""
    print_success "Usuario '$usuario' creado"
    print_info "  Jaula FTP : $JAULAS_DIR/$usuario/"
    print_info "  Carpetas disponibles:"
    print_info "    /general/       (publica)"
    print_info "    /$grupo/        (su grupo)"
    print_info "    /$usuario/      (personal)"
    return 0
}

cambioGrupo() {
    local usuario="$1"

    if ! id "$usuario" &>/dev/null; then
        print_error "El usuario '$usuario' no existe"
        return 1
    fi

    local grupo_actual
    grupo_actual=$(id -gn "$usuario")
    print_info "Grupo actual de '$usuario': $grupo_actual"

    echo ""
    echo "Grupos disponibles:"
    echo "  1) $GRUPO_REPROBADOS"
    echo "  2) $GRUPO_RECURSADORES"
    read -rp "Seleccione el nuevo grupo [1-2]: " opcion

    local nuevo_grupo
    case $opcion in
        1) nuevo_grupo="$GRUPO_REPROBADOS" ;;
        2) nuevo_grupo="$GRUPO_RECURSADORES" ;;
        *)
            print_error "Opcion invalida"
            return 1
            ;;
    esac

    if [ "$grupo_actual" == "$nuevo_grupo" ]; then
        print_info "El usuario ya pertenece a '$nuevo_grupo'"
        return 0
    fi

    print_info "Cambiando '$usuario': '$grupo_actual' -> '$nuevo_grupo'..."

    local carpeta_actual="$FTP_ROOT/personal/$usuario"
    local mover_contenido="n"

    if [ -d "$carpeta_actual" ] && [ "$(ls -A "$carpeta_actual" 2>/dev/null)" ]; then
        echo ""
        print_info "La carpeta personal tiene archivos."
        read -rp "Moverlos a la nueva ubicacion? [s/N]: " mover_contenido
    fi

    destruirJaula "$usuario"

    if [[ "$mover_contenido" =~ ^[Ss]$ ]]; then
        if [ -d "$carpeta_actual" ]; then
            mv "$carpeta_actual"/* "$carpeta_actual"/ 2>/dev/null
            print_success "Contenido conservado en $carpeta_actual"
        fi
    else
        print_info "Archivos conservados en $carpeta_actual (sin acceso FTP hasta reconstruccion)"
    fi

    sudo usermod -g "$nuevo_grupo" "$usuario"
    print_success "Grupo del sistema actualizado"

    crearCarpetaPersonal "$usuario" "$nuevo_grupo"
    construirJaula "$usuario" "$nuevo_grupo"

    echo ""
    print_success "Usuario '$usuario' movido a '$nuevo_grupo'"
    print_info "  Nueva estructura FTP:"
    print_info "  |-- general/"
    print_info "  |-- $nuevo_grupo/"
    print_info "  |-- $usuario/"
}

gestionUsuarios() {
    print_titulo "Gestion de Usuarios FTP"

    if ! verificarVSFTPD &>/dev/null; then
        print_error "vsftpd no esta instalado. Ejecute: $0 -in"
        return 1
    fi

    echo "Opciones:"
    echo "  1) Crear nuevos usuarios"
    echo "  2) Cambiar grupo de un usuario"
    echo "  3) Eliminar usuario"
    echo "  4) Volver"
    echo ""
    read -rp "Seleccione una opcion [1-4]: " opcion

    case $opcion in
        1)
            echo ""
            read -rp "Cuantos usuarios desea crear?: " num_usuarios

            if ! [[ "$num_usuarios" =~ ^[0-9]+$ ]] || [ "$num_usuarios" -lt 1 ]; then
                print_error "Numero invalido"
                return 1
            fi

            for ((i=1; i<=num_usuarios; i++)); do
                echo ""
                print_titulo "Usuario $i de $num_usuarios"

                while true; do
                    read -rp "Nombre de usuario: " usuario
                    # Validar usando funcion de libreria si existe, sino validacion inline
                    if command -v validarUsuario &>/dev/null; then
                        validarUsuario "$usuario" && break
                    else
                        [ -z "$usuario" ] && print_error "Nombre vacio" && continue
                        id "$usuario" &>/dev/null && print_error "El usuario '$usuario' ya existe" && continue
                        break
                    fi
                done

                while true; do
                    read -rsp "Contrasena (min. 8 caracteres): " password
                    echo ""
                    [ ${#password} -lt 8 ] && print_error "Contrasena muy corta" && continue
                    read -rsp "Confirmar contrasena: " password2
                    echo ""
                    [ "$password" == "$password2" ] && break
                    print_error "Las contrasenas no coinciden"
                done

                echo ""
                echo "A que grupo pertenece?"
                echo "  1) $GRUPO_REPROBADOS"
                echo "  2) $GRUPO_RECURSADORES"
                read -rp "Seleccione el grupo [1-2]: " grupo_opcion

                local grupo
                case $grupo_opcion in
                    1) grupo="$GRUPO_REPROBADOS" ;;
                    2) grupo="$GRUPO_RECURSADORES" ;;
                    *)
                        print_warning "Opcion invalida, asignando a '$GRUPO_REPROBADOS'"
                        grupo="$GRUPO_REPROBADOS"
                        ;;
                esac

                crearUsuarioFTP "$usuario" "$password" "$grupo"
            done

            echo ""
            print_info "Reiniciando vsftpd..."
            sudo systemctl restart vsftpd && print_success "Servicio reiniciado"
            ;;

        2)
            echo ""
            verEstadoServ
            echo ""
            read -rp "Usuario a cambiar de grupo: " usuario
            cambioGrupo "$usuario"
            sudo systemctl restart vsftpd && print_success "Servicio reiniciado"
            ;;

        3)
            echo ""
            verEstadoServ
            echo ""
            read -rp "Usuario a eliminar: " usuario

            if ! id "$usuario" &>/dev/null; then
                print_error "El usuario '$usuario' no existe"
                return 1
            fi

            if pgrep -u "$usuario" > /dev/null; then
                print_error "El usuario tiene procesos activos."
                read -rp "Forzar eliminacion? [s/N]: " force
                if [[ ! "$force" =~ ^[Ss]$ ]]; then
                    print_info "Operacion cancelada"
                    return 1
                fi
                pkill -u "$usuario" 2>/dev/null
            fi

            read -rp "Confirma eliminar '$usuario'? [s/N]: " confirmar
            if [[ "$confirmar" =~ ^[Ss]$ ]]; then
                destruirJaula "$usuario"
                sed -i "/^$usuario$/d" /etc/vsftpd.user_list
                sudo rm -rf "$FTP_ROOT/personal/$usuario"
                sudo userdel "$usuario" 2>/dev/null
                print_success "Usuario '$usuario' eliminado"
                sudo systemctl restart vsftpd && print_success "Servicio reiniciado"
            else
                print_info "Operacion cancelada"
            fi
            ;;

        4) return 0 ;;
        *) print_error "Opcion invalida" ;;
    esac
}

# -------------
# Estado y Diagnóstico
# -------------

verificarVSFTPD() {
    print_info "Verificando instalacion de vsftpd"

    if rpm -q $PAQUETE &>/dev/null; then
        local version
        version=$(rpm -q $PAQUETE --queryformat '%{VERSION}')
        print_success "vsftpd ya esta instalado (version: $version)"
        return 0
    fi

    if command -v vsftpd &>/dev/null; then
        local version
        version=$(vsftpd -v 2>&1 | head -1)
        print_success "vsftpd encontrado: $version"
        return 0
    fi

    print_error "vsftpd no esta instalado"
    return 1
}

verEstadoServ() {
    print_titulo "ESTADO DEL SERVIDOR FTP"
    sudo systemctl status vsftpd --no-pager
    echo ""
    print_info "Conexiones activas en :21"
    ss -tnp | grep :21 || echo "  Ninguna"
    echo ""
    local ip
    ip=$(ip addr show $INTERFAZ_RED 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    [ -n "$ip" ] && print_info "IP $INTERFAZ_RED: $ip" || \
        print_error "No se pudo obtener IP de $INTERFAZ_RED"

    echo ""
    print_info "Usuarios FTP configurados:"
    if [ ! -s /etc/vsftpd.user_list ]; then
        print_info "  No hay usuarios FTP configurados"
        return 0
    fi

    printf "  %-20s %-20s %-40s\n" "USUARIO" "GRUPO" "JAULA FTP"
    echo "  --------------------------------------------------------------------------------"
    while IFS= read -r u; do
        if id "$u" &>/dev/null; then
            local g
            g=$(id -gn "$u")
            printf "  %-20s %-20s %-40s\n" "$u" "$g" "$JAULAS_DIR/$u"
        fi
    done < /etc/vsftpd.user_list
    echo ""
}

mostrarEstructura() {
    print_titulo "Estructura del Servidor FTP"

    [ ! -d "$FTP_ROOT" ] && print_error "No existe: $FTP_ROOT" && return 1

    local ip
    ip=$(ip addr show $INTERFAZ_RED 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    print_info "Raiz : $FTP_ROOT"
    print_info "IP   : ${ip:-no disponible}"
    echo ""

    if command -v tree &>/dev/null; then
        sudo tree -L 3 -p -u -g "$FTP_ROOT"
    else
        sudo find "$FTP_ROOT" -maxdepth 3 -exec ls -ld {} \;
    fi
}

reiniciarFTP() {
    print_info "Reiniciando servidor FTP..."

    if systemctl is-active --quiet vsftpd; then
        sudo systemctl restart vsftpd
    else
        print_info "Servicio inactivo, iniciando..."
        sudo systemctl start vsftpd
    fi

    if systemctl is-active --quiet vsftpd; then
        print_success "vsftpd activo"
        sudo systemctl status vsftpd --no-pager
    else
        print_error "Error al reiniciar vsftpd"
        print_info "Revise: journalctl -xeu vsftpd.service"
    fi
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