#!/bin/bash
# =============================================================================
# http_functions.sh — Funciones para Apache2
# Proyecto : Aprovisionamiento Web Automatizado
# SO       : OpenSUSE Leap
# Uso      : source ./http_functions.sh  (no ejecutar directamente)
# Requiere : source ./utils.sh
# =============================================================================

# -----------------------------------------------------------------------------
# CONSULTAR VERSIONES DISPONIBLES DE APACHE2
# Usa zypper para obtener versiones del repositorio (sin hardcodear)
# Exporta: VERSION_ESTABLE, VERSION_LATEST, VERSION_ELEGIDA
# -----------------------------------------------------------------------------
obtener_versiones_apache() {
    print_title "Versiones disponibles de Apache2"

    if ! requiere_comando "zypper"; then return 1; fi

    print_info "[INFO] Consultando repositorio, espera..."

    # Obtener lista de versiones disponibles desde zypper
    # Formato de columnas: S | Name | Type | Version | Arch | Repository
    local versiones
    versiones=$(zypper search -s apache2 2>/dev/null \
        | awk -F'|' '$2 ~ /^ apache2 *$/ {print $4}' \
        | tr -d ' ' \
        | sort -V \
        | uniq)

    if [[ -z "$versiones" ]]; then
        print_warning "[ERROR] No se encontraron versiones de Apache2 en el repositorio."
        return 1
    fi

    # Convertir a array para indexar
    local -a lista_versiones
    mapfile -t lista_versiones <<< "$versiones"
    local total=${#lista_versiones[@]}

    # Mostrar todas las versiones numeradas
    local i=1
    for v in "${lista_versiones[@]}"; do
        print_menu "  [$i] $v"
        (( i++ ))
    done
    echo ""

    local intentos=0
    while (( intentos < 3 )); do
        echo -ne "${cyan}Selecciona una versión [1-$total]: ${nc}"
        read -r opcion

        if [[ "$opcion" =~ ^[0-9]+$ ]] && (( opcion >= 1 && opcion <= total )); then
            export VERSION_ELEGIDA="${lista_versiones[$((opcion - 1))]}"
            break
        fi

        print_warning "[ERROR] Opción inválida. Ingresa un número entre 1 y $total."
        (( intentos++ ))
    done

    if [[ -z "$VERSION_ELEGIDA" ]]; then
        print_warning "[ERROR] No se seleccionó ninguna versión."
        return 1
    fi

    print_success "[OK] Versión seleccionada: $VERSION_ELEGIDA"
}

# -----------------------------------------------------------------------------
# INSTALAR APACHE2 (silencioso)
# Uso: instalar_apache
# Requiere: VERSION_ELEGIDA exportada por obtener_versiones_apache()
# -----------------------------------------------------------------------------
instalar_apache() {
    print_title "Instalando Apache2"

    if [[ -z "$VERSION_ELEGIDA" ]]; then
        print_warning "[ERROR] No hay versión elegida. Ejecuta obtener_versiones_apache primero."
        return 1
    fi

    # Verificar si ya está instalado
    if rpm -q apache2 &>/dev/null; then
        print_info "[INFO] Apache2 ya está instalado. Omitiendo instalación."
        return 0
    fi

    print_info "[INFO] Instalando apache2-$VERSION_ELEGIDA ..."

    # Instalación silenciosa con zypper (-n = no interactivo, -y = aceptar todo)
    if ! zypper install -n -y "apache2=$VERSION_ELEGIDA" &>/dev/null; then
        # Si la versión exacta falla, instalar la disponible por defecto
        print_info "[WARN] Versión exacta no disponible, instalando versión del repositorio..."
        if ! zypper install -n -y apache2 &>/dev/null; then
            print_warning "[ERROR] Falló la instalación de Apache2."
            return 1
        fi
    fi

    print_success "[OK] Apache2 instalado correctamente."
}

# -----------------------------------------------------------------------------
# CONFIGURAR PUERTO DE APACHE2
# Uso: configurar_puerto_apache "8080"
# Edita: /etc/apache2/listen.conf  (en OpenSUSE, NO ports.conf)
# -----------------------------------------------------------------------------
configurar_puerto_apache() {
    local puerto="$1"
    local listen_conf="/etc/apache2/listen.conf"

    print_title "Configurando puerto Apache2"

    if [[ ! -f "$listen_conf" ]]; then
        print_warning "[ERROR] No se encontró $listen_conf"
        return 1
    fi

    # Backup antes de editar
    cp "$listen_conf" "${listen_conf}.bak"
    print_info "[INFO] Backup creado: ${listen_conf}.bak"

    # Reemplazar cualquier puerto Listen existente por el nuevo
    sed -i "s/^Listen .*/Listen $puerto/" "$listen_conf"

    # Verificar que el cambio se aplicó
    if grep -q "Listen $puerto" "$listen_conf"; then
        print_success "[OK] Puerto configurado a $puerto en $listen_conf"
    else
        print_warning "[ERROR] No se pudo aplicar el cambio de puerto."
        cp "${listen_conf}.bak" "$listen_conf"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# APLICAR HARDENING DE SEGURIDAD EN APACHE2
# - Oculta versión del servidor (ServerTokens / ServerSignature)
# - Deshabilita métodos peligrosos (TRACE, TRACK)
# - Agrega headers de seguridad (X-Frame-Options, X-Content-Type-Options)
# -----------------------------------------------------------------------------
aplicar_seguridad_apache() {
    print_title "Aplicando configuración de seguridad"

    local security_conf="/etc/apache2/conf.d/security.conf"

    # --- 1. Ocultar versión del servidor ---
    if [[ -f "$security_conf" ]]; then
        sed -i "s/^ServerTokens .*/ServerTokens Prod/"      "$security_conf"
        sed -i "s/^ServerSignature .*/ServerSignature Off/"  "$security_conf"
        print_success "[OK] ServerTokens y ServerSignature configurados."
    else
        # Crear el archivo si no existe
        cat >> "$security_conf" <<'EOF'
ServerTokens Prod
ServerSignature Off
EOF
        print_success "[OK] security.conf creado con ServerTokens Prod."
    fi

    # --- 2. Bloquear métodos peligrosos y agregar security headers ---
    local hardening_conf="/etc/apache2/conf.d/hardening.conf"

    cat > "$hardening_conf" <<'EOF'
# Bloquear métodos HTTP peligrosos
<Directory "/">
    <LimitExcept GET POST HEAD>
        Require all denied
    </LimitExcept>
</Directory>

# Cabeceras de seguridad
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
EOF

    # Asegurarse de que mod_headers esté habilitado
    if ! apache2ctl -M 2>/dev/null | grep -q "headers_module"; then
        a2enmod headers &>/dev/null
        print_info "[INFO] Módulo headers habilitado."
    fi

    print_success "[OK] Hardening aplicado: métodos restringidos y headers de seguridad añadidos."
}

# -----------------------------------------------------------------------------
# HABILITAR Y ARRANCAR APACHE2
# -----------------------------------------------------------------------------
iniciar_apache() {
    print_title "Iniciando servicio Apache2"

    systemctl enable apache2 &>/dev/null
    systemctl restart apache2

    if systemctl is-active --quiet apache2; then
        print_success "[OK] Apache2 activo y corriendo."
    else
        print_warning "[ERROR] Apache2 no pudo iniciar. Revisa: journalctl -xe"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# FLUJO COMPLETO DE APACHE2
# Llamada única desde main.sh
# -----------------------------------------------------------------------------
setup_apache() {
    obtener_versiones_apache || return 1
    pedir_puerto             || return 1
    instalar_apache          || return 1
    configurar_puerto_apache   "$PUERTO_ELEGIDO" || return 1
    aplicar_seguridad_apache || return 1
    abrir_puerto_firewall      "$PUERTO_ELEGIDO" || return 1
    crear_usuario_servicio   "wwwrun" "/srv/www" || return 1
    crear_index "Apache2" "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO" "/srv/www/htdocs" || return 1
    iniciar_apache           || return 1

    echo ""
    print_success "================================================"
    print_success "  Apache2 desplegado exitosamente"
    print_success "  URL : http://localhost:$PUERTO_ELEGIDO"
    print_success "  Ver.: $VERSION_ELEGIDA"
    print_success "================================================"
}

# =============================================================================
# NGINX
# =============================================================================

# -----------------------------------------------------------------------------
# CONSULTAR VERSIONES DISPONIBLES DE NGINX
# Exporta: VERSION_ELEGIDA
# -----------------------------------------------------------------------------
obtener_versiones_nginx() {
    print_title "Versiones disponibles de Nginx"

    if ! requiere_comando "zypper"; then return 1; fi

    print_info "[INFO] Consultando repositorio, espera..."

    local versiones
    versiones=$(zypper search -s nginx 2>/dev/null \
        | awk -F'|' '$2 ~ /^ nginx *$/ {print $4}' \
        | tr -d ' ' \
        | sort -V \
        | uniq)

    if [[ -z "$versiones" ]]; then
        print_warning "[ERROR] No se encontraron versiones de Nginx en el repositorio."
        return 1
    fi

    local -a lista_versiones
    mapfile -t lista_versiones <<< "$versiones"
    local total=${#lista_versiones[@]}

    local i=1
    for v in "${lista_versiones[@]}"; do
        print_menu "  [$i] $v"
        (( i++ ))
    done
    echo ""

    local intentos=0
    while (( intentos < 3 )); do
        echo -ne "${cyan}Selecciona una versión [1-$total]: ${nc}"
        read -r opcion

        if [[ "$opcion" =~ ^[0-9]+$ ]] && (( opcion >= 1 && opcion <= total )); then
            export VERSION_ELEGIDA="${lista_versiones[$((opcion - 1))]}"
            break
        fi

        print_warning "[ERROR] Opción inválida. Ingresa un número entre 1 y $total."
        (( intentos++ ))
    done

    if [[ -z "$VERSION_ELEGIDA" ]]; then
        print_warning "[ERROR] No se seleccionó ninguna versión."
        return 1
    fi

    print_success "[OK] Versión seleccionada: $VERSION_ELEGIDA"
}

# -----------------------------------------------------------------------------
# INSTALAR NGINX (silencioso)
# -----------------------------------------------------------------------------
instalar_nginx() {
    print_title "Instalando Nginx"

    if [[ -z "$VERSION_ELEGIDA" ]]; then
        print_warning "[ERROR] No hay versión elegida. Ejecuta obtener_versiones_nginx primero."
        return 1
    fi

    if rpm -q nginx &>/dev/null; then
        print_info "[INFO] Nginx ya está instalado. Omitiendo instalación."
        return 0
    fi

    print_info "[INFO] Instalando nginx-$VERSION_ELEGIDA ..."

    if ! zypper install -n -y "nginx=$VERSION_ELEGIDA" &>/dev/null; then
        print_info "[WARN] Versión exacta no disponible, instalando versión del repositorio..."
        if ! zypper install -n -y nginx &>/dev/null; then
            print_warning "[ERROR] Falló la instalación de Nginx."
            return 1
        fi
    fi

    print_success "[OK] Nginx instalado correctamente."
}

# -----------------------------------------------------------------------------
# CONFIGURAR PUERTO DE NGINX
# Edita: /etc/nginx/nginx.conf  —  bloque server { listen PORT; }
# -----------------------------------------------------------------------------
configurar_puerto_nginx() {
    local puerto="$1"
    local nginx_conf="/etc/nginx/nginx.conf"

    print_title "Configurando puerto Nginx"

    if [[ ! -f "$nginx_conf" ]]; then
        print_warning "[ERROR] No se encontró $nginx_conf"
        return 1
    fi

    cp "$nginx_conf" "${nginx_conf}.bak"
    print_info "[INFO] Backup creado: ${nginx_conf}.bak"

    sed -i "s/listen\s\+[0-9]\+;/listen $puerto;/g" "$nginx_conf"

    if grep -q "listen $puerto;" "$nginx_conf"; then
        print_success "[OK] Puerto configurado a $puerto en $nginx_conf"
    else
        print_warning "[ERROR] No se pudo aplicar el cambio de puerto."
        cp "${nginx_conf}.bak" "$nginx_conf"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# APLICAR HARDENING DE SEGURIDAD EN NGINX
# - Oculta versión (server_tokens off)
# - Deshabilita métodos peligrosos
# - Agrega headers de seguridad
# -----------------------------------------------------------------------------
aplicar_seguridad_nginx() {
    print_title "Aplicando configuración de seguridad Nginx"

    local nginx_conf="/etc/nginx/nginx.conf"
    local puerto="$PUERTO_ELEGIDO"

    # Eliminar cualquier archivo previo en conf.d que pueda causar conflictos
    rm -f /etc/nginx/conf.d/hardening.conf
    rm -f /etc/nginx/conf.d/*.conf 2>/dev/null

    # Reescribir nginx.conf completo con todas las directivas correctas
    cat > "$nginx_conf" << NGINXEOF
user wwwrun;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout 65;

    # Ocultar version del servidor
    server_tokens off;

    server {
        listen $puerto;
        server_name localhost;

        root /srv/www/nginx;
        index index.html;

        # Cabeceras de seguridad
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;

        # Bloquear metodos peligrosos
        location / {
            limit_except GET POST HEAD {
                deny all;
            }
        }
    }
}
NGINXEOF

    print_success "[OK] server_tokens off aplicado."
    print_success "[OK] Headers de seguridad añadidos."
    print_success "[OK] Métodos peligrosos bloqueados en location /."
    print_success "[OK] Hardening aplicado."
}

# -----------------------------------------------------------------------------
# HABILITAR Y ARRANCAR NGINX
# -----------------------------------------------------------------------------
iniciar_nginx() {
    print_title "Iniciando servicio Nginx"

    # Crear directorio para el pid si no existe
    if [[ ! -d /run/nginx ]]; then
        mkdir -p /run/nginx
        chown wwwrun:www /run/nginx
        chmod 755 /run/nginx
        print_info "[INFO] Directorio /run/nginx creado."
    fi

    # Aplicar override de systemd para deshabilitar restricciones SELinux del unit
    local override_dir="/etc/systemd/system/nginx.service.d"
    mkdir -p "$override_dir"
    cat > "${override_dir}/override.conf" <<'EOF'
[Service]
ProtectSystem=false
PrivateTmp=false
RuntimeDirectory=nginx
RuntimeDirectoryMode=0755
PIDFile=/run/nginx/nginx.pid
EOF
    systemctl daemon-reload &>/dev/null
    print_info "[INFO] Override de systemd aplicado."

    # Cambiar pid a ubicacion que nginx puede escribir
    sed -i "s|pid /run/nginx.pid;|pid /run/nginx/nginx.pid;|g" /etc/nginx/nginx.conf

    if ! nginx -t &>/dev/null; then
        print_warning "[ERROR] Configuración de Nginx inválida:"
        nginx -t
        return 1
    fi

    systemctl enable nginx &>/dev/null
    systemctl restart nginx

    if systemctl is-active --quiet nginx; then
        print_success "[OK] Nginx activo y corriendo."
    else
        print_warning "[ERROR] Nginx no pudo iniciar. Revisa: journalctl -xe"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# FLUJO COMPLETO DE NGINX
# Llamada única desde main.sh
# -----------------------------------------------------------------------------
setup_nginx() {
    obtener_versiones_nginx                                                    || return 1
    pedir_puerto                                                               || return 1
    instalar_nginx                                                             || return 1
    configurar_puerto_nginx      "$PUERTO_ELEGIDO"                            || return 1
    aplicar_seguridad_nginx                                                    || return 1
    abrir_puerto_firewall        "$PUERTO_ELEGIDO"                            || return 1
    crear_usuario_servicio       "wwwrun" "/srv/www/nginx"                     || return 1
    crear_index "Nginx" "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO" "/srv/www/nginx" || return 1
    iniciar_nginx                                                              || return 1

    echo ""
    print_success "================================================"
    print_success "  Nginx desplegado exitosamente"
    print_success "  URL : http://localhost:$PUERTO_ELEGIDO"
    print_success "  Ver.: $VERSION_ELEGIDA"
    print_success "================================================"
}

# =============================================================================
# TOMCAT
# =============================================================================

# -----------------------------------------------------------------------------
# CONSULTAR VERSIONES DISPONIBLES DE TOMCAT
# Consulta dlcdn.apache.org para obtener versiones reales (9.x, 10.x, 11.x)
# Exporta: VERSION_ELEGIDA
# -----------------------------------------------------------------------------
obtener_versiones_tomcat() {
    print_title "Versiones disponibles de Tomcat"

    local base_url="https://dlcdn.apache.org/tomcat/"
    local ramas

    print_info "[INFO] Consultando versiones en dlcdn.apache.org..."

    ramas=$(curl -s --max-time 8 "$base_url" 2>/dev/null \
        | grep -oP 'tomcat-\K[0-9]+(?=/)' \
        | sort -uV)

    if [[ -z "$ramas" ]]; then
        print_info "[INFO] Sin acceso a internet. Usando versiones de referencia."
        ramas="9\n10\n11"
    fi

    local -a lista_versiones=()
    while IFS= read -r rama; do
        local latest
        latest=$(curl -s --max-time 8 "${base_url}tomcat-${rama}/" 2>/dev/null \
            | grep -oP "v\K[0-9]+\.[0-9]+\.[0-9]+" \
            | sort -V | tail -1)
        [[ -n "$latest" ]] && lista_versiones+=("$latest")
    done <<< "$ramas"

    if [[ ${#lista_versiones[@]} -eq 0 ]]; then
        print_warning "[ERROR] No se encontraron versiones de Tomcat."
        return 1
    fi

    local total=${#lista_versiones[@]}
    local i=1
    for v in "${lista_versiones[@]}"; do
        print_menu "  [$i] $v"
        (( i++ ))
    done
    echo ""

    local intentos=0
    while (( intentos < 3 )); do
        echo -ne "${cyan}Selecciona una versión [1-$total]: ${nc}"
        read -r opcion

        if [[ "$opcion" =~ ^[0-9]+$ ]] && (( opcion >= 1 && opcion <= total )); then
            export VERSION_ELEGIDA="${lista_versiones[$((opcion - 1))]}"
            break
        fi

        print_warning "[ERROR] Opción inválida. Ingresa un número entre 1 y $total."
        (( intentos++ ))
    done

    if [[ -z "$VERSION_ELEGIDA" ]]; then
        print_warning "[ERROR] No se seleccionó ninguna versión."
        return 1
    fi

    print_success "[OK] Versión seleccionada: $VERSION_ELEGIDA"
}

# -----------------------------------------------------------------------------
# INSTALAR TOMCAT (descarga directa desde dlcdn.apache.org)
# -----------------------------------------------------------------------------
instalar_tomcat() {
    print_title "Instalando Apache Tomcat $VERSION_ELEGIDA"

    # Verificar Java
    if ! command -v java &>/dev/null; then
        print_info "[INFO] Java no encontrado. Instalando OpenJDK 21..."
        if ! zypper --non-interactive install java-21-openjdk java-21-openjdk-headless &>/dev/null; then
            print_warning "[ERROR] No se pudo instalar Java."
            return 1
        fi
        print_success "[OK] Java instalado."
    else
        print_info "[INFO] Java: $(java -version 2>&1 | head -1)"
    fi

    # Si ya está instalado en /opt/tomcat, saltar descarga
    if [[ -f /opt/tomcat/bin/startup.sh ]]; then
        print_info "[INFO] Tomcat ya está instalado en /opt/tomcat. Omitiendo descarga."
        return 0
    fi

    local rama="${VERSION_ELEGIDA%%.*}"
    local url="https://dlcdn.apache.org/tomcat/tomcat-${rama}/v${VERSION_ELEGIDA}/bin/apache-tomcat-${VERSION_ELEGIDA}.tar.gz"
    local tarball="/tmp/apache-tomcat-${VERSION_ELEGIDA}.tar.gz"

    print_info "[INFO] Descargando Tomcat $VERSION_ELEGIDA..."
    if ! curl -L --progress-bar -o "$tarball" "$url" 2>&1; then
        print_warning "[ERROR] Falló la descarga desde $url"
        return 1
    fi

    print_info "[INFO] Extrayendo en /opt/tomcat..."
    mkdir -p /opt/tomcat
    if ! tar xzf "$tarball" -C /opt/tomcat --strip-components=1; then
        print_warning "[ERROR] Falló la extracción."
        rm -f "$tarball"
        return 1
    fi
    rm -f "$tarball"
    print_success "[OK] Tomcat extraído en /opt/tomcat"
}

# -----------------------------------------------------------------------------
# CONFIGURAR PUERTO DE TOMCAT
# Edita /opt/tomcat/conf/server.xml
# -----------------------------------------------------------------------------
configurar_puerto_tomcat() {
    local puerto="$1"
    local server_xml="/opt/tomcat/conf/server.xml"

    print_title "Configurando puerto Tomcat"

    if [[ ! -f "$server_xml" ]]; then
        print_warning "[ERROR] No se encontró $server_xml"
        return 1
    fi

    cp "$server_xml" "${server_xml}.bak"
    print_info "[INFO] Backup creado: ${server_xml}.bak"

    # Cambiar puerto HTTP y deshabilitar AJP
    sed -i "s/port=\"8080\"/port=\"${puerto}\"/" "$server_xml"
    sed -i 's/port="8009"/port="-1"/'               "$server_xml"

    if grep -q "port=\"${puerto}\"" "$server_xml"; then
        print_success "[OK] Puerto configurado a $puerto en $server_xml"
        print_success "[OK] Conector AJP deshabilitado."
    else
        print_warning "[ERROR] No se pudo aplicar el cambio de puerto."
        cp "${server_xml}.bak" "$server_xml"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# APLICAR HARDENING DE SEGURIDAD EN TOMCAT
# -----------------------------------------------------------------------------
aplicar_seguridad_tomcat() {
    print_title "Aplicando configuración de seguridad Tomcat"

    local server_xml="/opt/tomcat/conf/server.xml"
    local web_xml="/opt/tomcat/conf/web.xml"

    # --- 1. Ocultar versión via ErrorReportValve ---
    if ! grep -q "showServerInfo" "$server_xml"; then
        sed -i "s|</Host>|    <Valve className=\"org.apache.catalina.valves.ErrorReportValve\" showReport=\"false\" showServerInfo=\"false\" />\n        </Host>|" "$server_xml"
    fi
    print_success "[OK] Versión del servidor ocultada."

    # --- 2. Headers de seguridad en web.xml ---
    if ! grep -q "httpHeaderSecurity" "$web_xml"; then
        sed -i 's|</web-app>||' "$web_xml"
        cat >> "$web_xml" << 'WEBEOF'
    <filter>
        <filter-name>httpHeaderSecurity</filter-name>
        <filter-class>org.apache.catalina.filters.HttpHeaderSecurityFilter</filter-class>
        <init-param>
            <param-name>antiClickJackingOption</param-name>
            <param-value>SAMEORIGIN</param-value>
        </init-param>
        <init-param>
            <param-name>blockContentTypeSniffingEnabled</param-name>
            <param-value>true</param-value>
        </init-param>
    </filter>
    <filter-mapping>
        <filter-name>httpHeaderSecurity</filter-name>
        <url-pattern>/*</url-pattern>
    </filter-mapping>
</web-app>
WEBEOF
    fi
    print_success "[OK] Headers de seguridad configurados en web.xml."
    print_success "[OK] Hardening de Tomcat aplicado."
}

# -----------------------------------------------------------------------------
# CREAR INDEX.HTML PARA TOMCAT
# -----------------------------------------------------------------------------
crear_index_tomcat() {
    local version="$1"
    local puerto="$2"
    local ruta_web="/opt/tomcat/webapps/ROOT"

    mkdir -p "$ruta_web"

    # Eliminar index.jsp por defecto si existe
    rm -f "${ruta_web}/index.jsp"

    cat > "${ruta_web}/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title> Servidor HTTP UwU </title>

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
        span { 
            color: #f44462; 
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
        <h1>Servidor Activo!!</h1>
        <div class="info">Servidor: <span>$Tomcat</span></div>
        <div class="info">Version: <span>$version</span></div>
        <div class="info">Puerto: <span>$puerto</span></div>
    </div>

</body>
</html>
EOF
    print_success "[OK] index.html creado en $ruta_web"
}

# -----------------------------------------------------------------------------
# CREAR USUARIO Y SERVICIO SYSTEMD PARA TOMCAT
# -----------------------------------------------------------------------------
iniciar_tomcat() {
    print_title "Iniciando servicio Tomcat"

    # Crear usuario tomcat si no existe
    if ! id "tomcat" &>/dev/null; then
        useradd -r -s /sbin/nologin -d /opt/tomcat -M tomcat
        print_success "[OK] Usuario tomcat creado."
    else
        print_info "[INFO] Usuario tomcat ya existe."
    fi

    # Permisos
    chown -R tomcat:tomcat /opt/tomcat
    chmod 750 /opt/tomcat
    chmod 750 /opt/tomcat/conf
    print_success "[OK] Permisos aplicados -> tomcat:tomcat (chmod 750)."

    # Detectar JAVA_HOME
    local java_home
    java_home=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")

    # Crear unit de systemd
    cat > /etc/systemd/system/tomcat.service << SVCEOF
[Unit]
Description=Apache Tomcat ${VERSION_ELEGIDA}
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment="JAVA_HOME=${java_home}"
Environment="CATALINA_HOME=/opt/tomcat"
Environment="CATALINA_BASE=/opt/tomcat"
Environment="CATALINA_PID=/opt/tomcat/temp/tomcat.pid"
Environment="CATALINA_OPTS=-Xms256M -Xmx512M"
ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload
    systemctl enable tomcat &>/dev/null
    systemctl restart tomcat &>/dev/null

    print_info "[INFO] Esperando que Tomcat inicie (15s)..."
    sleep 15

    if systemctl is-active --quiet tomcat; then
        print_success "[OK] Tomcat activo y corriendo."
    else
        print_warning "[ERROR] Tomcat no pudo iniciar. Revisa: journalctl -u tomcat -n 20"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# FLUJO COMPLETO DE TOMCAT
# Llamada única desde main.sh
# -----------------------------------------------------------------------------
setup_tomcat() {
    obtener_versiones_tomcat                                          || return 1
    pedir_puerto                                                      || return 1
    instalar_tomcat                                                   || return 1
    configurar_puerto_tomcat   "$PUERTO_ELEGIDO"                     || return 1
    aplicar_seguridad_tomcat                                          || return 1
    abrir_puerto_firewall      "$PUERTO_ELEGIDO"                     || return 1
    crear_index_tomcat         "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO"  || return 1
    iniciar_tomcat                                                    || return 1

    echo ""
    print_success "================================================"
    print_success "  Tomcat desplegado exitosamente"
    print_success "  URL : http://localhost:$PUERTO_ELEGIDO"
    print_success "  Ver.: $VERSION_ELEGIDA"
    print_success "================================================"
}

# =============================================================================
# VERIFICAR ESTADO DE SERVIDORES
# =============================================================================
verificar_HTTP() {
    print_title "Estado de Servidores HTTP"

    # --- Apache2 ---
    echo -ne "  ${amarillo}Apache2  :${nc} "
    if rpm -q apache2 &>/dev/null; then
        local ver_apache
        ver_apache=$(rpm -q apache2 --queryformat '%{VERSION}')
        if systemctl is-active --quiet apache2; then
            local puerto_apache
            puerto_apache=$(/usr/bin/ss -tulnp | grep -E 'httpd|apache2' | grep -oP ':\K[0-9]+' | head -1)
            echo -e "${verde}Instalado y activo${nc} — version: $ver_apache — puerto: ${puerto_apache:-?}"
        else
            echo -e "${amarillo}Instalado pero detenido${nc} — version: $ver_apache"
        fi
    else
        echo -e "${rojo}No instalado${nc}"
    fi

    # --- Nginx ---
    echo -ne "  ${amarillo}Nginx    :${nc} "
    if rpm -q nginx &>/dev/null; then
        local ver_nginx
        ver_nginx=$(rpm -q nginx --queryformat '%{VERSION}')
        if systemctl is-active --quiet nginx; then
            local puerto_nginx
            puerto_nginx=$(/usr/bin/ss -tulnp | grep nginx | grep -oP ':\K[0-9]+' | head -1)
            echo -e "${verde}Instalado y activo${nc} — version: $ver_nginx — puerto: ${puerto_nginx:-?}"
        else
            echo -e "${amarillo}Instalado pero detenido${nc} — version: $ver_nginx"
        fi
    else
        echo -e "${rojo}No instalado${nc}"
    fi

    # --- Tomcat ---
    echo -ne "  ${amarillo}Tomcat   :${nc} "
    if [[ -f /opt/tomcat/bin/startup.sh ]]; then
        local ver_tomcat
        ver_tomcat=$(/opt/tomcat/bin/version.sh 2>/dev/null | grep "Server version" | grep -oP 'Tomcat/\K[0-9]+\.[0-9]+\.[0-9]+')
        if systemctl is-active --quiet tomcat 2>/dev/null; then
            local puerto_tomcat
            puerto_tomcat=$(/usr/bin/ss -tulnp | grep java | grep -oP '\*:\K[0-9]+' | head -1)
            echo -e "${verde}Instalado y activo${nc} — version: ${ver_tomcat:-?} — puerto: ${puerto_tomcat:-?}"
        else
            echo -e "${amarillo}Instalado pero detenido${nc} — version: ${ver_tomcat:-?}"
        fi
    else
        echo -e "${rojo}No instalado${nc}"
    fi

    echo ""
}

# =============================================================================
# REVISAR RESPUESTA HTTP (curl -I)
# =============================================================================
_curl_servidor() {
    local nombre="$1"
    local puerto="$2"

    print_title "$nombre (puerto $puerto)"
    echo -e "${amarillo}Headers:${nc}"
    curl -sI "http://localhost:${puerto}"
    echo ""
    echo -e "${amarillo}Index:${nc}"
    curl -s "http://localhost:${puerto}"
    echo ""
}

revisar_HTTP() {
    print_title "Revisión de Servidores HTTP"
    print_menu "  [1] Apache2"
    print_menu "  [2] Nginx"
    print_menu "  [3] Tomcat"
    print_menu "  [4] Todos"
    echo ""

    local opcion
    while true; do
        echo -ne "${cyan}Selecciona [1-4]: ${nc}"
        read -r opcion
        opcion="${opcion//[^0-9]/}"
        [[ "$opcion" =~ ^[1234]$ ]] && break
        print_warning "[ERROR] Opción inválida."
    done

    echo ""

    local puerto_apache puerto_nginx puerto_tomcat
    puerto_apache=$(/usr/bin/ss -tulnp | grep -E 'httpd|apache2' | grep -oP ':\K[0-9]+' | head -1)
    puerto_nginx=$(/usr/bin/ss -tulnp  | grep nginx               | grep -oP ':\K[0-9]+' | head -1)
    puerto_tomcat=$(/usr/bin/ss -tulnp | grep java                | grep -oP '\*:\K[0-9]+' | head -1)

    case "$opcion" in
        1) _curl_servidor "Apache2" "${puerto_apache:-80}"   ;;
        2) _curl_servidor "Nginx"   "${puerto_nginx:-8080}"  ;;
        3) _curl_servidor "Tomcat"  "${puerto_tomcat:-8888}" ;;
        4)
            _curl_servidor "Apache2" "${puerto_apache:-80}"
            _curl_servidor "Nginx"   "${puerto_nginx:-8080}"
            _curl_servidor "Tomcat"  "${puerto_tomcat:-8888}"
            ;;
    esac
}