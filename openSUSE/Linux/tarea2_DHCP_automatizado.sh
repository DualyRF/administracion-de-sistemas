#Tarea 2 - Automatizacion y gestion del servidor DHCP
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/validaciones.sh"

ayuda() {
    # Todas las opciones
    echo "Uso del script: $0"
    echo "Opciones:"
    echo -e "  ${azul}-v, --verify       ${nc}Verifica si esta instalada la paqueteria DHCP"
    echo -e "  ${azul}-i, --install      ${nc}Instala la paqueteria DHCP"
    echo -e "  ${azul}-m, --monitor      ${nc}Monitorear clientes DHCP"
    echo -e "  ${azul}-r, --restart      ${nc}Reiniciar servidor DHCP"
	echo -e "  ${azul}-s, --status		 ${nc}Status del servidor DHCP"
    echo -e "  ${azul}-c, --configurar   ${nc}Configurar servidor DHCP"
	echo -e "  ${azul}-sh, --showConfig  ${nc}Ver configuración actual"
    echo -e "  ${azul}-?, --help         ${nc}Muestra esta ayuda/menu"
}

calcular_Rango(){
	local ip1=$1
	local ip2=$2
	local n=0
	local rango1=0
	local rango2=0
	local rangof=0
	local pot=0

	IFS='.' read -ra octetosIni <<< "$ip1"
	IFS='.' read -ra octetosFin <<< "$ip2"

	for ((i=3; i>=0; i--)); do
		pot=$(( 255 ** n ))
		rango1=$(( (${octetosIni[i]} * pot) + rango1))
		rango2=$(( (${octetosFin[i]} * pot) + rango2))
		n=$(( n + 1 ))
	done

	echo $(( rango2 - rango1 ))
}

calcular_Bits(){
	local masc="$1"
	count=0
	IFS='.' read -r a b c d <<< "$masc"
	for octeto in $d $c $b $a; do
		n=255
		if [ $octeto -eq 0 ]; then
			count=$(( count + 8 ))
			continue
		elif [ $octeto -eq 255 ]; then
			echo $count
			return 0
		else
		for i in {0..7}; do
			n=$(( n - (2 ** i) ))
			count=$(( count + 1 ))
			if [[ $n -eq $octeto ]]; then
				echo $count
				return 0
			fi
		done
		fi
	done
	return 0
}

validar_IP_Masc(){
	local comp=""
	local mascRang="$3"
	local n=255
	local count=0

	local rango=$(calcular_Rango "$1" "$2")
	mascRang=$(calcular_Bits "$mascRang")
	mascRang=$(( (2 ** mascRang) - 2 ))
	if [ $rango -gt $mascRang ]; then
		print_warning "La mascara $3 no es suficiente para el rango de IPs que desea asginar"
		return 1
	fi
	return 0
}

crear_Mascara(){
	local rango=$(calcular_Rango "$1" "$2")
	local n=0
	local bits=0
    local p=0
	local masc=255.255.255.255
    local octeto=0
	
	for i in {1..32}; do
		if [[ $n -ge $(( rango + 2 )) ]]; then
			break;
		else
			n=$(( 2 ** i ))
			bits=$(( bits + 1 ))
		fi
	done
	IFS='.' read -r -a a_masc <<< "$masc"
	for ((i=${#a_masc[@]}-1; i>=0; i--)); do
		octeto=${a_masc[i]}
        p=0
        until [ $octeto -eq 0 ] || [ $p -eq $bits ]; do
            octeto=$(( octeto - (2 ** p )))
            p=$(( p + 1 ))
        done
        if [ $p -eq $bits ]; then
            a_masc[i]=$octeto
            break;
        fi
        
        bits=$(( bits - 8))
		a_masc[i]=$octeto
	done
    IFS=" "
    octeto="${a_masc[*]}"
    octeto=${octeto// /.}
    echo "$octeto"
}

monitorear_Clientes(){
    local archivo_leases="/var/lib/dhcp/db/dhcpd.leases"
    local opc=""
    
    # Verificar si existe el archivo de leases
    if [ ! -f "$archivo_leases" ]; then
        print_warning "Error: No se encontró el archivo de leases"
        print_info "Asegúrate de que el servidor DHCP esté funcionando"
        return 1
    fi
    
    # Verificar si el servicio está activo
    if ! systemctl is-active --quiet dhcpd; then
        print_warning "El servicio DHCP no está activo"
        read -p "¿Desea iniciarlo? (y/n): " opc
        if [[ "$opc" = "y" ]]; then
            sudo systemctl start dhcpd
        else
            return 1
        fi
    fi
    
    print_menu "\n--- Monitoreo Del DHCP ---\n"
    
    # Menú de opciones
    print_info "Seleccione una opción:"
    echo -e "  ${verde}1.${nc} Ver todos los leases (histórico)"
    echo -e "  ${verde}2.${nc} Ver solo leases activos"
    echo -e "  ${verde}3.${nc} Monitoreo en tiempo real"
    echo -e "  ${verde}4.${nc} Ver estadísticas del servidor"
    echo -e "  ${verde}5.${nc} Exportar reporte a archivo"
    read -p "Opción: " opc
    
    case $opc in
        1)
            echo -e "\n--- Todos Los Leases ---\n"
            cat "$archivo_leases"
            ;;
        2)
            print_menu "\n--- Leases Activos\n"
            print_success "IP Address\t\tMAC Address\t\tHostname\t\tExpira"
            echo -e "-------------------------------------------------------------------------------------"
            
            awk '
            /^lease/ {ip=$2; active=0}
            /hardware ethernet/ {mac=$3; gsub(";","",mac)}
            /client-hostname/ {host=$2; gsub(/[";]/,"",host)}
            /binding state active/ {active=1}
            /ends/ {
                if (active) {
                    expires=$3" "$4
                    gsub(";","",expires)
                    printf "%-20s %-20s %-20s %s\n", ip, mac, host, expires
                }
            }
            ' "$archivo_leases" | sort -u
            ;;
        3)
            print_menu "\n--- Monitoreo En Tiempo Real ---\n"
            tail -f "$archivo_leases"
            ;;
        4)
            print_menu "\n--- Estadiscias Del Servidor ---\n"
            
            total=$(grep -c "^lease" "$archivo_leases")
            activos=$(grep -c "binding state active" "$archivo_leases")
            
            print_success "Total de leases registrados:${nc} $total"
            print_success "Leases activos:${nc} $activos"
            print_info "\nEstado del servicio:"
            sudo systemctl status dhcpd --no-pager
            ;;
        5)
            local archivo_salida="reporte_dhcp_$(date +%Y%m%d_%H%M%S).txt"
            print_menu "\n--- Generando Reporte ---\n"
            
            {
                echo "REPORTE DHCP - $(date)"
                echo "================================"
                echo ""
                echo "CLIENTES ACTIVOS:"
                echo "IP Address          MAC Address          Hostname             Expira"
                echo "-------------------------------------------------------------------------------------"
                
                awk '
                /^lease/ {ip=$2; active=0}
                /hardware ethernet/ {mac=$3; gsub(";","",mac)}
                /client-hostname/ {host=$2; gsub(/[";]/,"",host)}
                /binding state active/ {active=1}
                /ends/ {
                    if (active) {
                        expires=$3" "$4
                        gsub(";","",expires)
                        printf "%-20s %-20s %-20s %s\n", ip, mac, host, expires
                    }
                }
                ' "$archivo_leases" | sort -u
                
                echo ""
                echo "================================"
                echo "ESTADÍSTICAS:"
                echo "Total leases: $(grep -c "^lease" "$archivo_leases")"
                echo "Leases activos: $(grep -c "binding state active" "$archivo_leases")"
            } > "$archivo_salida"
            
            print_success "Reporte guardado en: $archivo_salida"
            cat "$archivo_salida"
            ;;
        *)
            print_warning "Opción inválida"
            ;;
    esac
    
    print_menu "\n¿===============================================\n"
}

reiniciar_DHCP(){
    print_info "Reiniciando servidor DHCP..."
    
    if ! systemctl is-active --quiet dhcpd; then
        print_warning "El servicio DHCP no está activo"
        read -p "¿Desea iniciarlo en lugar de reiniciarlo? (y/n): " opc
        if [[ "$opc" = "y" ]]; then
            sudo systemctl start dhcpd
        else
            return 1
        fi
    else
        sudo systemctl restart dhcpd
    fi
    
    if systemctl is-active --quiet dhcpd; then
        print_success "Servidor DHCP reiniciado correctamente"
        sudo systemctl status dhcpd --no-pager
    else
        print_warning "Error al reiniciar el servidor DHCP"
        print_info "Ejecute: sudo journalctl -xeu dhcpd.service"
    fi
}

ver_Configuracion(){
    local config_file="/etc/dhcpd.conf"
    local sysconfig="/etc/sysconfig/dhcpd"
    
    if [ ! -f "$config_file" ]; then
        print_warning "No se encontró el archivo de configuración"
        print_info "Parece que el servidor DHCP no está configurado aún"
        return 1
    fi
    
    print_menu "\n--- Configuracion Actual Del Servidor DHCP ---$\n"
    
    print_success "Archivo de configuración principal: " echo "$config_file"
    print_info "-----------------------------------------------------------"
    cat "$config_file"
	print_info "-----------------------------------------------------------$\n"
    
    if [ -f "$sysconfig" ]; then
        print_success "Interfaz configurada:"
        cat "$sysconfig"
        echo ""
    fi
    
    print_success "Estado del servicio:"
    sudo systemctl status dhcpd --no-pager | head -n 5
    
    print_menu "\n============================================================\n"
}

ver_Estado(){
	print_menu "--- Estado del servidor DHCP ---\n"
    sudo systemctl status dhcpd --no-pager
}

verificar_Instalacion(){
	# Comprobar si esta instalada la paqueteria de DHCP
	local opc

	print_info "Verificando paqueteria DHCP..."
	if ! zypper search --installed-only | grep -q dhcp; then
		print_warning "DHCP no esta instalado"
		read -p "Desea instalarlo? (y/n): " opc
		if [[ $opc = "y" ]]; then
            instalar_DHCP
			exit
		fi
	else
		print_success "DHCP esta instalado"
	fi
}

instalar_DHCP(){
    print_menu "--- Instalación y Configuración de DHCP Server ---"
    echo ""
    
    # 1. Verificar si DHCP ya está instalado
	if rpm -q dhcp-server &>/dev/null; then
		print_success "DHCP server ya está instalado"
	else
		print_info "DHCP server no está instalado, iniciando instalación..."
		
		# Ejecutar instalación en segundo plano
		sudo zypper --non-interactive --quiet install dhcp-server > /dev/null 2>&1 &
		pid=$!
		
		print_info "DHCP se está instalando..."
		
		# Esperar a que termine la instalación
		wait $pid
		
		# Verificar si se instaló correctamente
		if [ $? -eq 0 ]; then
			print_success "DHCP server instalado correctamente"
		else
			print_warning "Error en la instalación de DHCP"
			return 1
		fi
	fi
    
    echo ""
    
    # 2. Verificar si existe configuración previa
    if [ -f /etc/dhcpd.conf ] && [ -s /etc/dhcpd.conf ]; then
        print_info "Se detectó una configuración previa de DHCP"
        echo ""
        read -p "¿Deseas sobreescribir la configuración existente? (y/n): " sobreescribir
        
        if [[ "$sobreescribir" =~ ^[Yy]$ ]]; then
            print_info "Continuando con el script..."
			configurar_DHCP
            return 0
        else
			print_info "Volviendo..."
			return 0
		fi
    fi
    
    echo ""
}

configurar_DHCP(){
	local ip_Valida=""
    local uso_Mas=""
    local comp=""

	print_menu "\nConfiguracion Dinamica\n"

	read -p "Nombre descriptivo del Ambito: " scope
	until [ "$masc_valida" = "si" ]; do
		read -p "Mascara (En blanco para asignar automaticamente): " mascara
		if [ "$mascara" != "" ]; then
			if validar_Mascara "$mascara"; then
                uso_Mas="si"
				masc_valida="si"
			fi
		else
			masc_valida="si"
		fi
	done

	until [ "$ip_Valida" = "si" ]; do
		read -p "Rango inicial de la IP (La primera IP se usara para asignarla al servidor): " ip_Inicial
		ip_Res=$(echo "$ip_Inicial" | cut -d'.' -f4)
		if [ $ip_Res -ne 255 ]; then
			ip_Servidor="$ip_Inicial"
			ip_Res=$(( ip_Res + 1 ))
			ip_Inicial=$(echo "$ip_Inicial" | cut -d'.' -f1-3)
			ip_Inicial="$ip_Inicial.$ip_Res"
			if validar_IP "$ip_Inicial"; then
				ip_Valida="si"
			fi
		else
			print_warning "No use X.X.X.255 como ultimo octeto por temas de rendimiento"
			print_info "Intentando nuevamente..."	
		fi
	done

	ip_Valida="no"

	until [ "$ip_Valida" = "si" ]; do
		read -p "Rango final de la IP: " ip_Final
		if validar_IP "$ip_Final"; then
			if [ $(calcular_Rango "$ip_Inicial" "$ip_Final") -gt 2 ]; then
    			if [ "$uso_Mas" = "si" ]; then
					if validar_IP_Masc "$ip_Inicial" "$ip_Final" "$mascara"; then
						ip_Valida="si"
					fi
				else
					mascara=$(crear_Mascara "$ip_Inicial" "$ip_Final")
					ip_Valida="si"
				fi
			else
    			print_warning "La IP no concuerda con el rango inicial"
			fi   
		fi
		
		if [ "$ip_Valida" = "no" ]; then
			print_info "Intendo nuevamente..."
		fi
	done

	read -p "Tiempo de la sesion (segundos): " lease_Time

	comp="no"
	until [[ "$comp" = "si" ]]; do
		read -p "Gateway (puede quedar vacio para red aislada): " gateway
		if [ "$gateway" = "" ]; then
			comp="si"
			print_info "Sin gateway - los clientes no tendran acceso a internet"
		elif validar_IP "$gateway"; then
			comp="si"
		fi
		if [ "$comp" = "no" ]; then
			print_info "Intentando nuevamente..."
		fi
	done

	comp="no"
	until [[ "$comp" = "si" ]]; do
		read -p "DNS principal (puede quedar vacio): " dns
		if [ "$dns" = "" ]; then
			comp="si"
			dns_Alt=""
		elif validar_IP "$dns"; then
			comp="si"
		fi
		if [ "$comp" = "no" ]; then
			print_info "Intentando nuevamente..."
		fi
	done

	if [ -n "$dns" ]; then
		comp="no"
		until [[ "$comp" = "si" ]]; do
			read -p "DNS alternativo (puede quedar vacio): " dns_Alt
			if [ "$dns_Alt" = "" ]; then
				comp="si"
			elif validar_IP "$dns_Alt"; then
				comp="si"
			fi
			if [ "$comp" = "no" ]; then
				print_info "Intentando nuevamente..."
			fi
		done
	else
		dns_Alt=""  # Asegurar que esté vacío si no hay DNS principal
	fi

	# Detectar interfaz de red automáticamente o pedir al usuario
	print_info "\nInterfaces de red disponibles:"
	ip -br link show | grep -v "lo" | awk '{print $1}'
	read -p "Ingrese la interfaz de red a usar (ej: enp0s8): " interfaz

    print_menu "\nLa configuracion final es:"
	echo -e "Nombre del ambito: ${verde}$scope${nc}"
	echo -e "Mascara: ${verde}$mascara${nc}"
	echo -e "IP inicial: ${verde}$ip_Inicial${nc}"
	echo -e "IP final: ${verde}$ip_Final${nc}"
	echo -e "Tiempo de consesion: ${verde}$lease_Time${nc}"
	echo -e "Gateway: ${verde}$gateway${nc}"
	echo -e "DNS primario: ${verde}$dns${nc}"
	echo -e "DNS alternativo: ${verde}$dns_Alt${nc}"
	echo -e "Interfaz: ${verde}$interfaz${nc}\n"
	
	read -p "Acepta esta configuracion? (y/n): " opc
    if [ "$opc" = "y" ]; then
		# Calcular la dirección de red correctamente
		IFS='.' read -r a b c d <<< "$ip_Inicial"
		IFS='.' read -r ma mb mc md <<< "$mascara"
		
		# AND bit a bit entre IP y máscara para obtener la red
		red="$((a & ma)).$((b & mb)).$((c & mc)).$((d & md))"
		
		# Calcular broadcast
		broadcast="$((a | (255 - ma))).$((b | (255 - mb))).$((c | (255 - mc))).$((d | (255 - md)))"
		
		print_info "Red calculada: ${nc}$red"
		print_info "Broadcast calculado: ${nc}$broadcast"
	
	# Crear configuración DHCP
	print_info "Creando configuración DHCP..."
sudo bash -c "cat > /etc/dhcpd.conf" << EOF
# Configuracion DHCP - $scope
default-lease-time $lease_Time;
max-lease-time $((lease_Time * 2));
authoritative;

subnet $red netmask $mascara {
    range $ip_Inicial $ip_Final;
$(if [ -n "$gateway" ]; then
    echo "    option routers $gateway;"
fi)
    option subnet-mask $mascara;
$(if [ -n "$dns" ] && [ -n "$dns_Alt" ]; then
    echo "    option domain-name-servers $dns, $dns_Alt;"
elif [ -n "$dns" ]; then
    echo "    option domain-name-servers $dns;"
fi)
    option broadcast-address $broadcast;
}
EOF

		# Configurar interfaz
		interfaz="enp0s8"
# 1. Crear config permanente
sudo bash -c "cat > /etc/sysconfig/network/ifcfg-$interfaz" << EOF
BOOTPROTO='static'
STARTMODE='auto'
IPADDR='$ip_Servidor'
NETMASK='$mascara'
EOF

		print_info "Configurando interfaz de red..."
		sudo bash -c "echo 'DHCPD_INTERFACE=\"$interfaz\"' > /etc/sysconfig/dhcpd"

		sudo wicked ifdown $interfaz
		sudo wicked ifup $interfaz

		print_info "Reiniciando servicio DHCP..."
		sudo systemctl restart dhcpd

		print_info "Configurando DNS en resolv.conf..."

		# Limpiar nameservers anteriores
		sudo sed -i '/^nameserver/d' /etc/resolv.conf

		# Agregar DNS principal (siempre es el servidor mismo)
		sudo sed -i "1s/^/nameserver $ip_Servidor\n/" /etc/resolv.conf

		# Agregar DNS adicionales si fueron proporcionados
		if [ -n "$dns" ]; then
			sudo sed -i "2s/^/nameserver $dns\n/" /etc/resolv.conf
		fi

		if [ -n "$dns_Alt" ]; then
			sudo sed -i "3s/^/nameserver $dns_Alt\n/" /etc/resolv.conf
		fi
		
		print_success "IP estática $ip_Servidor configurada en $interfaz"

		# Verificar estado
		if sudo systemctl is-active --quiet dhcpd; then
			print_success "Servidor DHCP configurado y funcionando correctamente"
			sudo systemctl status dhcpd --no-pager
		else
			print_warning "Error al iniciar el servicio DHCP"
			print_info "Ejecute: sudo journalctl -xeu dhcpd.service para ver mas detalles sobre el error"
		fi
    else
        print_info "Volviendo a configurar..."
        configurar_DHCP
    fi
}

# ---------- Main ----------
case $1 in
    -v | --verify) verificar_Instalacion ;;
    -i | --install) instalar_DHCP ;;
    -m | --monitor) monitorear_Clientes ;;
    -r | --restart) reiniciar_DHCP ;;
	-s | --status) ver_Estado ;;
    -c | --config) configurar_DHCP ;;
	-sc | --showConfig) ver_Configuracion ;;
    -? | --help) ayuda ;;
esac