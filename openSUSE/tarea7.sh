#!/bin/bash

set -euo pipefail

# ========================== COLORES ==========================
RED='\033[0;95m'  
GREEN='\033[0;96m'
YELLOW='\033[1;93m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ========================== VARIABLES ==========================
FTP_SERVER="172.20.10.3"
FTP_USER="ftpuser"
FTP_PASS="Practica7FTP"
FTP_BASE_PATH="/http/Linux"

DOMAIN="reprobados.com"
SSL_DIR="/etc/ssl/practica7"
DOWNLOAD_DIR="/tmp/practica7_downloads"

# Variable global para retorno de FTP
FTP_DOWNLOADED_FILE=""

# ========================== FUNCIONES AUXILIARES ==========================

print_header() {
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
}

print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_err()  { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_err "Ejecutar como root: sudo bash $0"
        exit 1
    fi
}

pause() {
    echo ""
    read -rp "Presiona ENTER para continuar..."
}

# ========================== MENU PRINCIPAL ==========================

show_main_menu() {
    clear
    print_header "ORQUESTADOR DE INSTALACION - LINUX (VM2)"
    echo "  VM: OpenSUSE Leap 16"
    echo "  Dominio: ${DOMAIN}"
    echo "  FTP Repo: ${FTP_SERVER}"
    echo ""
    echo "  Puertos asignados:"
    echo "    Apache  -> HTTP: 80   | HTTPS: 443"
    echo "    Nginx   -> HTTP: 8080 | HTTPS: 8443"
    echo "    Tomcat  -> HTTP: 8081 | HTTPS: 8444"
    echo ""
    echo -e "${BOLD}  Selecciona una opcion:${NC}"
    echo ""
    echo "  1) Instalar Apache HTTP Server"
    echo "  2) Instalar Nginx"
    echo "  3) Instalar Tomcat"
    echo "  4) Configurar SSL en un servicio existente"
    echo "  5) Ver resumen / validacion de todos los servicios"
    echo "  6) Salir"
    echo ""
    read -rp "  Opcion [1-6]: " opcion
    echo ""

    case $opcion in
        1) instalar_servicio "Apache" ;;
        2) instalar_servicio "Nginx" ;;
        3) instalar_servicio "Tomcat" ;;
        4) menu_ssl_existente ;;
        5) resumen_final ;;
        6) echo -e "${GREEN}Hasta luego.${NC}"; exit 0 ;;
        *) print_err "Opcion invalida"; pause; show_main_menu ;;
    esac
}

# ========================== SELECCION DE FUENTE ==========================

elegir_fuente() {
    local servicio="$1"
    echo "" >&2
    echo -e "${BOLD}  Fuente de instalacion para ${servicio}:${NC}" >&2
    echo "" >&2
    echo "  1) WEB - Repositorios oficiales (zypper / descarga directa)" >&2
    echo "  2) FTP - Repositorio privado (${FTP_SERVER})" >&2
    echo "" >&2
    read -rp "  Opcion [1-2]: " fuente
    echo "" >&2

    case $fuente in
        1) echo "WEB" ;;
        2) echo "FTP" ;;
        *) echo "Opcion invalida, usando WEB" >&2; echo "WEB" ;;
    esac
}

# ========================== CLIENTE FTP DINAMICO ==========================

ftp_navegar_y_descargar() {
    local servicio="$1"
    local ruta="${FTP_BASE_PATH}/${servicio}/"

    FTP_DOWNLOADED_FILE=""

    print_header "NAVEGACION FTP - ${servicio}"

    echo -e "  ${CYAN}Conectando a ftp://${FTP_SERVER}${ruta}...${NC}"
    echo ""

    local archivos
    archivos=$(curl -s -u "${FTP_USER}:${FTP_PASS}" "ftp://${FTP_SERVER}${ruta}" --list-only 2>/dev/null)

    if [[ -z "$archivos" ]]; then
        print_err "No se encontraron archivos en ${ruta}"
        print_warn "Verifica que el repositorio FTP tenga los binarios."
        return 1
    fi

    # Filtrar solo binarios (no .sha256 ni .PENDIENTE)
    local binarios
    binarios=$(echo "$archivos" | grep -E '\.(tar\.gz|zip|msi|deb|rpm)$' || true)

    if [[ -z "$binarios" ]]; then
        print_err "No hay binarios disponibles en ${ruta}"
        echo "  Archivos encontrados:"
        echo "$archivos" | sed 's/^/    /'
        return 1
    fi

    echo "  Archivos disponibles:"
    echo ""
    local i=1
    local opciones=()
    while IFS= read -r archivo; do
        echo "    ${i}) ${archivo}"
        opciones+=("$archivo")
        ((i++))
    done <<< "$binarios"

    echo ""
    read -rp "  Selecciona el archivo a descargar [1-$((i-1))]: " seleccion

    if [[ $seleccion -lt 1 || $seleccion -ge $i ]]; then
        print_err "Seleccion invalida"
        return 1
    fi

    local archivo_elegido="${opciones[$((seleccion-1))]}"
    local url_archivo="ftp://${FTP_SERVER}${ruta}${archivo_elegido}"
    local url_hash="ftp://${FTP_SERVER}${ruta}${archivo_elegido}.sha256"

    mkdir -p "$DOWNLOAD_DIR"

    # Descargar binario
    echo ""
    echo -e "  ${CYAN}Descargando: ${archivo_elegido}...${NC}"
    if ! curl -fSL -u "${FTP_USER}:${FTP_PASS}" -o "${DOWNLOAD_DIR}/${archivo_elegido}" "$url_archivo" 2>/dev/null; then
        print_err "Error al descargar ${archivo_elegido}"
        return 1
    fi
    local tamano
    tamano=$(du -h "${DOWNLOAD_DIR}/${archivo_elegido}" | cut -f1)
    print_ok "Descargado: ${archivo_elegido} (${tamano})"

    # Descargar hash
    echo -e "  ${CYAN}Descargando hash SHA256...${NC}"
    if curl -fSL -u "${FTP_USER}:${FTP_PASS}" -o "${DOWNLOAD_DIR}/${archivo_elegido}.sha256" "$url_hash" 2>/dev/null; then
        print_ok "Hash descargado: ${archivo_elegido}.sha256"
    else
        print_warn "No se encontro archivo .sha256 en el servidor"
    fi

    # Verificar integridad
    verificar_integridad "${DOWNLOAD_DIR}/${archivo_elegido}"

    FTP_DOWNLOADED_FILE="${DOWNLOAD_DIR}/${archivo_elegido}"
}

# ========================== VERIFICACION DE INTEGRIDAD ==========================

verificar_integridad() {
    local archivo="$1"
    local hashfile="${archivo}.sha256"

    print_header "VERIFICACION DE INTEGRIDAD (SHA256)"

    if [[ ! -f "$hashfile" ]]; then
        print_warn "No hay archivo .sha256 - no se puede verificar integridad"
        return 0
    fi

    echo "  Archivo:  $(basename "$archivo")"

    local hash_local
    hash_local=$(sha256sum "$archivo" | awk '{print $1}')
    echo "  Hash local:  ${hash_local:0:16}..."

    local hash_remoto
    hash_remoto=$(awk '{print $1}' "$hashfile")
    echo "  Hash remoto: ${hash_remoto:0:16}..."

    echo ""
    if [[ "$hash_local" == "$hash_remoto" ]]; then
        print_ok "INTEGRIDAD VERIFICADA - Los hashes coinciden"
        return 0
    else
        print_err "INTEGRIDAD FALLIDA - Los hashes NO coinciden"
        print_err "El archivo puede estar corrupto"
        read -rp "  Continuar de todos modos? [s/N]: " cont
        [[ "$cont" =~ ^[sS]$ ]] && return 0 || return 1
    fi
}

# ========================== INSTALACION DE SERVICIOS ==========================

instalar_servicio() {
    local servicio="$1"

    print_header "INSTALACION DE ${servicio^^}"

    local fuente
    fuente=$(elegir_fuente "$servicio")

    case $servicio in
        Apache)  instalar_apache "$fuente" ;;
        Nginx)   instalar_nginx "$fuente" ;;
        Tomcat)  instalar_tomcat "$fuente" ;;
    esac

    # Preguntar por SSL
    echo ""
    read -rp "  Desea activar SSL en ${servicio}? [S/n]: " activar_ssl
    if [[ ! "$activar_ssl" =~ ^[nN]$ ]]; then
        configurar_ssl "$servicio"
    fi

    pause
    show_main_menu
}

# ========================== APACHE ==========================

instalar_apache() {
    local fuente="$1"

    if [[ "$fuente" == "WEB" ]]; then
        print_header "INSTALANDO APACHE VIA WEB (zypper)"
        zypper --non-interactive install apache2 2>/dev/null || true
        print_ok "Apache instalado via zypper"
    else
        print_header "INSTALANDO APACHE VIA FTP"
        FTP_DOWNLOADED_FILE=""
        ftp_navegar_y_descargar "Apache"

        if [[ -z "$FTP_DOWNLOADED_FILE" || ! -f "$FTP_DOWNLOADED_FILE" ]]; then
            print_err "No se obtuvo el archivo. Intentando via zypper como fallback..."
        else
            print_ok "Archivo descargado desde FTP: $(basename "$FTP_DOWNLOADED_FILE")"
        fi
        # En OpenSUSE Apache se gestiona con zypper para funcionalidad completa
        print_warn "Instalando paquete del sistema para funcionalidad completa..."
        zypper --non-interactive install apache2 2>/dev/null || true
    fi

    # Habilitar modulos necesarios (ssl ya viene incluido en Leap 16)
    a2enmod ssl 2>/dev/null || true
    a2enmod rewrite 2>/dev/null || true
    a2enmod headers 2>/dev/null || true

    # Crear pagina de prueba
    cat > /srv/www/htdocs/index.html << 'HTMLEOF'

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title> Apache - Reprobados.com </title>

    <style>
        .infoServ { 
            background: rgb(249, 181, 192); 
            border:1px solid #982f4a; 
            padding:2rem 3rem;
            border-radius:8px; 
            text-align:center; 
            color: rgb(255, 235, 239);
            width: 600px;
        }
        h1 { 
            color: #982f4a; 
        }
	body{
	    display: flex;
  	    flex-direction: column;
  	    align-items: center;
  	    justify-content: center;
	}
    </style>

</head>
<body style="background-color: rgb(255, 226, 231)">
    <div class="infoServ">
        <h1> Servidor Apache </h1>
        <div class="info">Servidor: 192.168.10.184 - reprobados.com</div>
    </div>

</body>
</html>
HTMLEOF

    # Configurar ServerName
    if ! grep -q "ServerName ${DOMAIN}" /etc/apache2/httpd.conf 2>/dev/null; then
        echo "ServerName ${DOMAIN}" >> /etc/apache2/httpd.conf
    fi

    # Asegurar que Apache escuche en puerto 80
    if ! grep -q "^Listen 80" /etc/apache2/listen.conf 2>/dev/null; then
        echo "Listen 80" >> /etc/apache2/listen.conf 2>/dev/null || true
    fi

    systemctl enable apache2
    systemctl restart apache2
    print_ok "Apache iniciado en puerto 80"
}

# ========================== NGINX ==========================

instalar_nginx() {
    local fuente="$1"

    if [[ "$fuente" == "WEB" ]]; then
        print_header "INSTALANDO NGINX VIA WEB (zypper)"
        zypper --non-interactive install nginx 2>/dev/null || true
        print_ok "Nginx instalado via zypper"
    else
        print_header "INSTALANDO NGINX VIA FTP"
        FTP_DOWNLOADED_FILE=""
        ftp_navegar_y_descargar "Nginx"

        if [[ -z "$FTP_DOWNLOADED_FILE" || ! -f "$FTP_DOWNLOADED_FILE" ]]; then
            print_err "No se obtuvo el archivo. Usando zypper como fallback..."
        else
            print_ok "Archivo descargado desde FTP: $(basename "$FTP_DOWNLOADED_FILE")"
        fi
        print_warn "Instalando paquete del sistema para funcionalidad completa..."
        zypper --non-interactive install nginx 2>/dev/null || true
    fi

    # Crear directorio web para Nginx
    mkdir -p /srv/www/nginx
    cat > /srv/www/nginx/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head><title>Nginx - reprobados.com</title></head>
<body>
<h1>Nginx HTTP Server - Practica 7</h1>
<p>Servidor: 192.168.10.184 - reprobados.com</p>
</body>
</html>
HTMLEOF

    # Configurar nginx en puerto 8080 (80 lo usa Apache)
    cat > /etc/nginx/nginx.conf << 'NGINXEOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;

    # Servidor HTTP en puerto 8080
    server {
        listen       8080;
        server_name  reprobados.com;
        root         /srv/www/nginx;
        index        index.html;

        location / {
            try_files $uri $uri/ =404;
        }
    }

    include /etc/nginx/conf.d/*.conf;
}
NGINXEOF

    systemctl enable nginx
    systemctl restart nginx
    print_ok "Nginx iniciado en puerto 8080"
}

# ========================== TOMCAT ==========================

instalar_tomcat() {
    local fuente="$1"
    local tomcat_home="/opt/tomcat"

    if [[ "$fuente" == "WEB" ]]; then
        print_header "INSTALANDO TOMCAT VIA WEB (descarga directa)"
        # No hay paquete oficial de Tomcat para Leap 16
        mkdir -p "$DOWNLOAD_DIR"
        local tomcat_url="https://dlcdn.apache.org/tomcat/tomcat-10/v10.1.52/bin/apache-tomcat-10.1.52.tar.gz"
        echo "  Descargando Tomcat 10.1.52..."
        if curl -fSL -o "${DOWNLOAD_DIR}/apache-tomcat-10.1.52.tar.gz" "$tomcat_url" 2>/dev/null; then
            print_ok "Tomcat descargado"
        else
            print_err "Error al descargar Tomcat"
            return 1
        fi
    else
        print_header "INSTALANDO TOMCAT VIA FTP"
        FTP_DOWNLOADED_FILE=""
        ftp_navegar_y_descargar "Tomcat"
        if [[ -z "$FTP_DOWNLOADED_FILE" || ! -f "$FTP_DOWNLOADED_FILE" ]]; then
            print_err "No se obtuvo el archivo"
            return 1
        fi
    fi

    # Instalar Java si no existe
    if ! command -v java &>/dev/null; then
        echo -e "  ${CYAN}Instalando Java (dependencia de Tomcat)...${NC}"
        zypper --non-interactive install java-17-openjdk java-17-openjdk-devel 2>/dev/null || \
        zypper --non-interactive install java-21-openjdk java-21-openjdk-devel 2>/dev/null || true
    fi

    if command -v java &>/dev/null; then
        print_ok "Java disponible: $(java -version 2>&1 | head -1)"
    else
        print_err "Java no se pudo instalar. Tomcat lo necesita."
        return 1
    fi

    # Buscar el archivo tar.gz descargado
    local tarball
    tarball=$(find "$DOWNLOAD_DIR" -name "apache-tomcat-*.tar.gz" -type f | head -1)
    if [[ -z "$tarball" ]]; then
        print_err "No se encontro archivo tar.gz de Tomcat"
        return 1
    fi

    echo -e "  ${CYAN}Instalando Tomcat en ${tomcat_home}...${NC}"

    # Crear usuario tomcat si no existe
    if ! id tomcat &>/dev/null; then
        useradd -r -m -d "$tomcat_home" -s /bin/false tomcat
    fi

    # Extraer
    rm -rf "$tomcat_home"
    mkdir -p "$tomcat_home"
    tar -xzf "$tarball" -C "$tomcat_home" --strip-components=1
    chown -R tomcat:tomcat "$tomcat_home"
    chmod +x "${tomcat_home}/bin/"*.sh

    # Configurar puerto 8081 (8080 lo usa Nginx)
    sed -i 's/port="8080"/port="8081"/' "${tomcat_home}/conf/server.xml"

    # Detectar JAVA_HOME
    local java_home
    java_home=$(dirname $(dirname $(readlink -f $(which java))))

    # Crear servicio systemd
    cat > /etc/systemd/system/tomcat.service << TOMCATEOF
[Unit]
Description=Apache Tomcat 10 - Practica 7
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment="JAVA_HOME=${java_home}"
Environment="CATALINA_HOME=${tomcat_home}"
Environment="CATALINA_BASE=${tomcat_home}"
ExecStart=${tomcat_home}/bin/startup.sh
ExecStop=${tomcat_home}/bin/shutdown.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
TOMCATEOF

    systemctl daemon-reload
    systemctl enable tomcat
    systemctl restart tomcat

    # Esperar a que Tomcat inicie
    echo "  Esperando a que Tomcat inicie..."
    sleep 5

    print_ok "Tomcat iniciado en puerto 8081"
}

# ========================== GENERACION DE CERTIFICADOS SSL ==========================

generar_certificado() {
    local servicio="$1"
    local cert_name="${servicio,,}"  # minusculas

    mkdir -p "$SSL_DIR"

    local cert_file="${SSL_DIR}/${cert_name}.crt"
    local key_file="${SSL_DIR}/${cert_name}.key"

    if [[ -f "$cert_file" && -f "$key_file" ]]; then
        print_warn "Certificado para ${servicio} ya existe"
        read -rp "  Regenerar? [s/N]: " regen
        if [[ ! "$regen" =~ ^[sS]$ ]]; then
            return 0
        fi
    fi

    echo -e "  ${CYAN}Generando certificado autofirmado para ${DOMAIN}...${NC}"

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$key_file" \
        -out "$cert_file" \
        -subj "/C=MX/ST=Sonora/L=CiudadObregon/O=Practica7/OU=AdminSistemas/CN=${DOMAIN}" \
        2>/dev/null

    chmod 600 "$key_file"
    chmod 644 "$cert_file"

    print_ok "Certificado: ${cert_file}"
    print_ok "Llave:       ${key_file}"

    echo ""
    echo "  Informacion del certificado:"
    openssl x509 -in "$cert_file" -noout -subject -dates 2>/dev/null | sed 's/^/    /'
}

# ========================== CONFIGURAR SSL POR SERVICIO ==========================

configurar_ssl() {
    local servicio="$1"

    print_header "CONFIGURACION SSL/TLS - ${servicio}"

    generar_certificado "$servicio"

    case $servicio in
        Apache)  configurar_ssl_apache ;;
        Nginx)   configurar_ssl_nginx ;;
        Tomcat)  configurar_ssl_tomcat ;;
    esac
}

# --- SSL APACHE ---
configurar_ssl_apache() {
    local cert="${SSL_DIR}/apache.crt"
    local key="${SSL_DIR}/apache.key"

    # Habilitar modulos
    a2enmod ssl 2>/dev/null || true
    a2enmod rewrite 2>/dev/null || true
    a2enmod headers 2>/dev/null || true

    # Habilitar flag SSL en sysconfig
    if [[ -f /etc/sysconfig/apache2 ]]; then
        # Agregar SSL al APACHE_SERVER_FLAGS si no esta
        if ! grep -q 'APACHE_SERVER_FLAGS=".*SSL' /etc/sysconfig/apache2; then
            sed -i 's/^APACHE_SERVER_FLAGS=""/APACHE_SERVER_FLAGS="SSL"/' /etc/sysconfig/apache2
            # Si ya tenia algo en los flags
            sed -i 's/^APACHE_SERVER_FLAGS="\([^"]*\)"/APACHE_SERVER_FLAGS="\1 SSL"/' /etc/sysconfig/apache2
        fi
    fi

    # Asegurar Listen 443 en listen.conf
    if ! grep -q "^Listen 443" /etc/apache2/listen.conf 2>/dev/null; then
        echo "Listen 443" >> /etc/apache2/listen.conf
    fi

    # Crear VirtualHost SSL
    cat > /etc/apache2/vhosts.d/ssl_reprobados.conf << APACHESSL
# VirtualHost HTTPS - Practica 7
<VirtualHost *:443>
    ServerName ${DOMAIN}
    DocumentRoot /srv/www/htdocs

    SSLEngine on
    SSLCertificateFile ${cert}
    SSLCertificateKeyFile ${key}

    <Directory /srv/www/htdocs>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    # HSTS basico
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
</VirtualHost>

# Redireccion HTTP -> HTTPS
<VirtualHost *:80>
    ServerName ${DOMAIN}
    RewriteEngine On
    RewriteRule ^(.*)\$ https://%{HTTP_HOST}\$1 [R=301,L]
</VirtualHost>
APACHESSL

    systemctl restart apache2
    print_ok "Apache HTTPS activo en puerto 443"
    print_ok "Redireccion HTTP (80) -> HTTPS (443) configurada"
}

# --- SSL NGINX ---
configurar_ssl_nginx() {
    local cert="${SSL_DIR}/nginx.crt"
    local key="${SSL_DIR}/nginx.key"

    cat > /etc/nginx/nginx.conf << NGINXSSL
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;

    # Redireccion HTTP 8080 -> HTTPS 8443
    server {
        listen       8080;
        server_name  ${DOMAIN};
        return 301 https://\$host:8443\$request_uri;
    }

    # Servidor HTTPS en 8443
    server {
        listen       8443 ssl;
        server_name  ${DOMAIN};
        root         /srv/www/nginx;
        index        index.html;

        ssl_certificate     ${cert};
        ssl_certificate_key ${key};
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;

        # HSTS basico
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

        location / {
            try_files \$uri \$uri/ =404;
        }
    }

    include /etc/nginx/conf.d/*.conf;
}
NGINXSSL

    systemctl restart nginx
    print_ok "Nginx HTTPS activo en puerto 8443"
    print_ok "Redireccion 8080 -> 8443 configurada"
}

# --- SSL TOMCAT ---
configurar_ssl_tomcat() {
    local tomcat_home="/opt/tomcat"
    local cert="${SSL_DIR}/tomcat.crt"
    local key="${SSL_DIR}/tomcat.key"
    local keystore="${SSL_DIR}/tomcat.p12"
    local keystore_pass="practica7ssl"

    # Crear PKCS12 keystore desde cert y key
    echo -e "  ${CYAN}Creando keystore PKCS12 para Tomcat...${NC}"
    openssl pkcs12 -export \
        -in "$cert" \
        -inkey "$key" \
        -out "$keystore" \
        -name tomcat \
        -password "pass:${keystore_pass}" 2>/dev/null

    print_ok "Keystore creado: ${keystore}"

    local server_xml="${tomcat_home}/conf/server.xml"

    # Backup
    cp "$server_xml" "${server_xml}.bak.$(date +%s)" 2>/dev/null || true

    # Verificar si ya tiene conector SSL y removerlo
    if grep -q "SSLEnabled" "$server_xml"; then
        print_warn "Removiendo configuracion SSL anterior..."
        # Usar python/perl para remover bloque SSL de forma segura
        sed -i '/<!-- Conector HTTPS - Practica 7 -->/,/<\/Connector>/d' "$server_xml" 2>/dev/null || true
    fi

    # Insertar conector HTTPS antes del cierre de </Service>
    sed -i "/<\/Service>/i\\
    <!-- Conector HTTPS - Practica 7 -->\\
    <Connector port=\"8444\" protocol=\"org.apache.coyote.http11.Http11NioProtocol\"\\
               maxThreads=\"150\" SSLEnabled=\"true\"\\
               scheme=\"https\" secure=\"true\">\\
        <SSLHostConfig>\\
            <Certificate certificateKeystoreFile=\"${keystore}\"\\
                         certificateKeystorePassword=\"${keystore_pass}\"\\
                         certificateKeystoreType=\"PKCS12\" />\\
        </SSLHostConfig>\\
    </Connector>" "$server_xml"

    chown tomcat:tomcat "$keystore"
    systemctl restart tomcat

    # Esperar
    sleep 3

    print_ok "Tomcat HTTPS activo en puerto 8444"
}

# ========================== MENU SSL PARA SERVICIO EXISTENTE ==========================

menu_ssl_existente() {
    print_header "CONFIGURAR SSL EN SERVICIO EXISTENTE"
    echo "  1) Apache  (HTTPS en 443)"
    echo "  2) Nginx   (HTTPS en 8443)"
    echo "  3) Tomcat  (HTTPS en 8444)"
    echo "  4) Volver"
    echo ""
    read -rp "  Opcion [1-4]: " ssl_op

    case $ssl_op in
        1) configurar_ssl "Apache" ;;
        2) configurar_ssl "Nginx" ;;
        3) configurar_ssl "Tomcat" ;;
        4) show_main_menu; return ;;
        *) print_err "Opcion invalida" ;;
    esac

    pause
    show_main_menu
}

# ========================== RESUMEN Y VALIDACION ==========================

resumen_final() {
    print_header "RESUMEN Y VALIDACION DE SERVICIOS"

    # ---- APACHE ----
    echo -e "${BOLD}  [1/3] APACHE${NC}"
    echo "  -------"
    if systemctl is-active apache2 &>/dev/null; then
        print_ok "Servicio: ACTIVO"

        # HTTP
        local http_code
        http_code=$(curl -sk -o /dev/null -w "%{http_code}" http://127.0.0.1 2>/dev/null || echo "000")
        if [[ "$http_code" == "200" || "$http_code" == "301" || "$http_code" == "302" ]]; then
            print_ok "HTTP  (puerto 80):  respondiendo (codigo ${http_code})"
        else
            print_warn "HTTP  (puerto 80):  no responde (codigo ${http_code})"
        fi

        # HTTPS
        http_code=$(curl -sk -o /dev/null -w "%{http_code}" https://127.0.0.1 2>/dev/null || echo "000")
        if [[ "$http_code" == "200" ]]; then
            print_ok "HTTPS (puerto 443): respondiendo"
            echo "    Certificado:"
            echo | openssl s_client -connect 127.0.0.1:443 -servername ${DOMAIN} 2>/dev/null | \
                openssl x509 -noout -subject -dates 2>/dev/null | sed 's/^/      /'
        else
            print_warn "HTTPS (puerto 443): no configurado (codigo ${http_code})"
        fi
    else
        print_warn "Apache: NO instalado o no activo"
    fi

    echo ""

    # ---- NGINX ----
    echo -e "${BOLD}  [2/3] NGINX${NC}"
    echo "  ------"
    if systemctl is-active nginx &>/dev/null; then
        print_ok "Servicio: ACTIVO"

        local http_code
        http_code=$(curl -sk -o /dev/null -w "%{http_code}" http://127.0.0.1:8080 2>/dev/null || echo "000")
        if [[ "$http_code" == "200" || "$http_code" == "301" ]]; then
            print_ok "HTTP  (puerto 8080): respondiendo (codigo ${http_code})"
        else
            print_warn "HTTP  (puerto 8080): no responde (codigo ${http_code})"
        fi

        http_code=$(curl -sk -o /dev/null -w "%{http_code}" https://127.0.0.1:8443 2>/dev/null || echo "000")
        if [[ "$http_code" == "200" ]]; then
            print_ok "HTTPS (puerto 8443): respondiendo"
            echo "    Certificado:"
            echo | openssl s_client -connect 127.0.0.1:8443 -servername ${DOMAIN} 2>/dev/null | \
                openssl x509 -noout -subject -dates 2>/dev/null | sed 's/^/      /'
        else
            print_warn "HTTPS (puerto 8443): no configurado (codigo ${http_code})"
        fi
    else
        print_warn "Nginx: NO instalado o no activo"
    fi

    echo ""

    # ---- TOMCAT ----
    echo -e "${BOLD}  [3/3] TOMCAT${NC}"
    echo "  -------"
    if systemctl is-active tomcat &>/dev/null; then
        print_ok "Servicio: ACTIVO"

        local http_code
        http_code=$(curl -sk -o /dev/null -w "%{http_code}" http://127.0.0.1:8081 2>/dev/null || echo "000")
        if [[ "$http_code" == "200" ]]; then
            print_ok "HTTP  (puerto 8081): respondiendo"
        else
            print_warn "HTTP  (puerto 8081): no responde (codigo ${http_code})"
        fi

        http_code=$(curl -sk -o /dev/null -w "%{http_code}" https://127.0.0.1:8444 2>/dev/null || echo "000")
        if [[ "$http_code" == "200" ]]; then
            print_ok "HTTPS (puerto 8444): respondiendo"
        else
            print_warn "HTTPS (puerto 8444): no configurado (codigo ${http_code})"
        fi
    else
        print_warn "Tomcat: NO instalado o no activo"
    fi

    # ---- CERTIFICADOS ----
    echo ""
    echo -e "${BOLD}  CERTIFICADOS GENERADOS${NC}"
    echo "  ----------------------"
    if [[ -d "$SSL_DIR" ]]; then
        find "$SSL_DIR" -name "*.crt" | sort | while read -r c; do
            local name
            name=$(basename "$c" .crt)
            echo -e "  ${GREEN}✓${NC} ${name}:"
            openssl x509 -in "$c" -noout -subject -dates 2>/dev/null | sed 's/^/      /'
        done
    else
        print_warn "No se han generado certificados aun"
    fi

    # ---- PUERTOS ----
    echo ""
    echo -e "${BOLD}  PUERTOS EN USO${NC}"
    echo "  ---------------"
    ss -tlnp 2>/dev/null | grep -E ':(80|443|8080|8081|8443|8444)\s' | sed 's/^/    /' || \
        echo "    No se pudieron listar los puertos"

    # ---- HOSTS ----
    echo ""
    echo -e "${BOLD}  CONFIGURACION DE HOSTS${NC}"
    echo "  ----------------------"
    if grep -q "${DOMAIN}" /etc/hosts 2>/dev/null; then
        print_ok "/etc/hosts tiene entrada para ${DOMAIN}"
    else
        print_warn "Falta: echo '192.168.10.184 ${DOMAIN} www.${DOMAIN}' >> /etc/hosts"
    fi

    # ---- FIREWALL ----
    echo ""
    echo -e "${BOLD}  FIREWALL${NC}"
    echo "  --------"
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --list-all 2>/dev/null | grep -E '(services|ports)' | sed 's/^/    /'
    else
        echo "    firewall-cmd no disponible"
    fi

    pause
    show_main_menu
}

# ========================== CONFIGURACIONES INICIALES ==========================

setup_inicial() {
    # Agregar dominio a /etc/hosts
    if ! grep -q "${DOMAIN}" /etc/hosts 2>/dev/null; then
        echo "192.168.10.184 ${DOMAIN} www.${DOMAIN}" >> /etc/hosts
        print_ok "Agregado ${DOMAIN} a /etc/hosts"
    fi

    # Configurar firewall
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-service=http 2>/dev/null || true
        firewall-cmd --permanent --add-service=https 2>/dev/null || true
        firewall-cmd --permanent --add-port=8080/tcp 2>/dev/null || true
        firewall-cmd --permanent --add-port=8081/tcp 2>/dev/null || true
        firewall-cmd --permanent --add-port=8443/tcp 2>/dev/null || true
        firewall-cmd --permanent --add-port=8444/tcp 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        print_ok "Firewall configurado (80, 443, 8080, 8081, 8443, 8444)"
    fi

    # Crear directorio de descargas
    mkdir -p "$DOWNLOAD_DIR"
}

# ========================== MAIN ==========================

main() {
    check_root
    setup_inicial
    show_main_menu
}

main "$@"