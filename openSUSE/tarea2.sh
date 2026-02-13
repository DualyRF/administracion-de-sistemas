#Tarea 2 - Automatizacion y gestion del servidor DHCP'

# ----------Colores para que sea mas intuitivo ----------
rojo='\033[0;95m'  
amarillo='\033[1;93m'
verde='\033[0;96m'
azul='\033[1;34m'
nc='\033[0m'

# ---------- Variables globales ----------

# ---------- Funciones ----------

ayuda() {
    # Todas las opciones
    echo "Uso del script: $0"
    echo "Opciones:"
    echo -e "  ${azul}-vr, --verify       ${nc}Verifica si esta instalada la paqueteria DHCP"
    echo -e "  ${azul}-is, --install      ${nc}Instala la paqueteria DHCP"
    echo -e "  ${azul}-cf, --configurar   ${nc}Configurar servidor DHCP"
    echo -e "  ${azul}-mt, --monitor      ${nc}Monitorear clientes DHCP"
    echo -e "  ${azul}-rt, --restart      ${nc}Reiniciar servidor DHCP"
	echo -e "  ${azul}-st, --status		 ${nc}Status del servidor DHCP"
	echo -e "  ${azul}-sc, --showConfig  ${nc}Ver configuración actual"
    echo -e "  ${azul}-help, --help         ${nc}Muestra esta ayuda/menu"
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
	local count=0¿

	local rango=$(calcular_Rango "$1" "$2")
	mascRang=$(calcular_Bits "$mascRang")
	mascRang=$(( (2 ** mascRang) - 2 ))
	if [ $rango -gt $mascRang ]; then
		echo -e "${rojo}La mascara $3 no es suficiente para el rango de IPs que desea asginar${nc}"
		return 1
	fi
	return 0
}

validar_IP(){
	# Variable
	local ip="$1"
	echo -en "${rojo}"

	# Validar formato X.X.X.X solo con numeros
	if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		echo -e "Direccion IP invalida, tiene que contener un formato X.X.X.X unicamente con numeros positivos${nc}"
    	return 1
   	fi
	
	# Validar cada octeto entre 0 y 255
    	IFS='.' read -r a b c d <<< "$ip"
	if [[ "$a" -eq 0  || "$d" -eq 0 ]]; then
		echo -e "Direccion IP invalida, no puede ser 0.X.X.X ni X.X.X.0${nc}"
		return 1
	fi
	
	# Validar que no tenga 0 al izquierda y que no pasen los rangos de 8 bits
	for octeto in $a $b $c $d; do
	if [[ "$octeto" =~ ^0[0-9]+ ]]; then
		echo -e "Direccion IP invalida, no se pueden poner 0 a la izquierda a menos que sea 0${nc}"
		return 1
	fi
		if [[ "$octeto" -lt 0 || "$octeto" -gt 255 ]]; then
				echo -e "Direccion IP invalida, no puede ser mayor a 255 ni menor a 0${nc}"
				return 1
		fi
	done

	# Validar que no sea 0.0.0.0 ni 255.255.255.255
	if [[ "$ip" = "0.0.0.0" || "$ip" = "255.255.255.255" ]]; then
		echo -e "Direccion IP invalida, no puede ser 0.0.0.0 ni 255.255.255.255${nc}"
		return 1
	fi

    # Validar los espacios reservados para uso experimental (127.0.0.1-127.255.255.255)
	if [[ "$a" -eq 127 ]]; then
		echo -e "Direccion IP invalida! las direcciones del rango 127.0.0.1 al 127.255.255.255 estan reservadas para el host local${nc}"
		return 1
	fi

	# Validar los espacios reservados para uso experimental (240.0.0.0-255.255.255.254)
	if [[ "$a" -gt 240 && "$a" -lt 255 ]]; then
		echo -e "Direccion IP invalida! las direcciones del rango 240.0.0.0 al 255.255.255.254 estan reservadas${nc}"
		return 1
	fi

	# Validar los espacios reservados para multicast (224.0.0.0-239.255.255.255)
	if [[ "$a" -gt 224 && "$a" -lt 239 ]]; then
		echo -e "Direccion IP invalida! las direcciones del rango 224.0.0.0 al 239.255.255.255 estan reservadas para multicast${nc}"
		return 1
	fi

	echo -en "${nc}"
    	return 0
}

validar_Mascara(){
	local masc="$1"
	echo -en "${rojo}"
	
	# Validar formato X.X.X.X solo con numeros
	if ! [[ "$masc" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		echo -e "Mascara invalida, tiene que contener un formato X.X.X.X ${nc}"
		return 1
	fi

	# Validar cada octeto entre 0 y 255
	IFS='.' read -r a b c d <<< "$masc"
	if [ "$a" -eq 0 ]; then
		echo -e "Mascara invalida, no puede iniciar con 0, ej: 0.X.X.X${nc}"
		return 1
	fi
	
	# Validar que sean 255, 252, 248, 240, 224, 192, 128 y 0
	# for octeto in $a $b $c $d; do
		
	# done
	
	# Validar que no tenga 0 al izquierda y que no pasen los rangos de 8 bits
	for octeto in $a $b $c $d; do
		if [[ "$octeto" =~ ^0[0-9]+ ]]; then
			echo -e "Mascara invalida, no se pueden poner 0 a la izquierda a menos que sea 0${nc}"
			return 1
		fi
		if [[ "$octeto" -lt 0 || "$octeto" -gt 255 ]]; then
				echo -e "Mascara invalida, no puede ser mayor a 255 ni menor a 0${nc}"
				return 1
		fi
	done

	# Validar los bits de la mascara
	if [ "$a" -lt 255 ]; then
		for octeto in $b $c $d; do
			if [ "$octeto" -gt 0 ]; then
				echo -e "Mascara invalida, ocupas acabar los bits del primer octeto (255.X.X.X)${nc}"
				return 1
			fi
		done
	elif [ "$b" -lt 255 ]; then
		for octeto in $c $d; do
			if [ "$octeto" -gt 0 ]; then
				echo -e "Mascara invalida, ocupas acabar los bits del segundo octeto (255.255.X.X)${nc}"
				return 1
			fi
		done
	elif [ "$c" -lt 255 ]; then
		for octeto in $d; do
			if [ "$octeto" -gt 0 ]; then
				echo -e "Mascara invalida, ocupas acabar los bits del tercer octeto (255.255.255.X)${nc}"
				return 1
			fi
		done
	elif [ "$d" -gt 252 ]; then
		echo -e "Mascara invalida, no puede superar 255.255.255.252${nc}"
		return 1
	fi

	echo -en "${nc}"
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
        echo -e "${rojo}Error: No se encontró el archivo de leases${nc}"
        echo -e "${amarillo}Asegúrate de que el servidor DHCP esté funcionando${nc}"
        return 1
    fi
    
    # Verificar si el servicio está activo
    if ! systemctl is-active --quiet dhcpd; then
        echo -e "${rojo}El servicio DHCP no está activo${nc}"
        read -p "¿Desea iniciarlo? (y/n): " opc
        if [[ "$opc" = "y" ]]; then
            sudo systemctl start dhcpd
        else
            return 1
        fi
    fi
    
    echo -e "\n${azul}========== MONITOREO DE CLIENTES DHCP ==========${nc}\n"
    
    # Menú de opciones
    echo -e "${amarillo}Seleccione una opción:${nc}"
    echo -e "  ${verde}1.${nc} Ver todos los leases (histórico)"
    echo -e "  ${verde}2.${nc} Ver solo leases activos"
    echo -e "  ${verde}3.${nc} Monitoreo en tiempo real"
    echo -e "  ${verde}4.${nc} Ver estadísticas del servidor"
    echo -e "  ${verde}5.${nc} Exportar reporte a archivo"
    read -p "Opción: " opc
    
    case $opc in
        1)
            echo -e "\n${azul}=== TODOS LOS LEASES ===${nc}\n"
            cat "$archivo_leases"
            ;;
        2)
            echo -e "\n${azul}=== LEASES ACTIVOS ===${nc}\n"
            echo -e "${verde}IP Address\t\tMAC Address\t\tHostname\t\tExpira${nc}"
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
            echo -e "\n${azul}=== MONITOREO EN TIEMPO REAL (Ctrl+C para salir) ===${nc}\n"
            tail -f "$archivo_leases"
            ;;
        4)
            echo -e "\n${azul}=== ESTADÍSTICAS DEL SERVIDOR ===${nc}\n"
            
            total=$(grep -c "^lease" "$archivo_leases")
            activos=$(grep -c "binding state active" "$archivo_leases")
            
            echo -e "${verde}Total de leases registrados:${nc} $total"
            echo -e "${verde}Leases activos:${nc} $activos"
            echo -e "\n${amarillo}Estado del servicio:${nc}"
            sudo systemctl status dhcpd --no-pager
            ;;
        5)
            local archivo_salida="reporte_dhcp_$(date +%Y%m%d_%H%M%S).txt"
            echo -e "\n${azul}=== GENERANDO REPORTE ===${nc}\n"
            
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
            
            echo -e "${verde}Reporte guardado en: $archivo_salida${nc}"
            cat "$archivo_salida"
            ;;
        *)
            echo -e "${rojo}Opción inválida${nc}"
            ;;
    esac
    
    echo -e "\n${azul}===============================================${nc}\n"
}

reiniciar_DHCP(){
    echo -e "${amarillo}Reiniciando servidor DHCP...${nc}"
    
    if ! systemctl is-active --quiet dhcpd; then
        echo -e "${rojo}El servicio DHCP no está activo${nc}"
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
        echo -e "${verde}Servidor DHCP reiniciado correctamente${nc}"
        sudo systemctl status dhcpd --no-pager
    else
        echo -e "${rojo}Error al reiniciar el servidor DHCP${nc}"
        echo -e "${amarillo}Ejecute: sudo journalctl -xeu dhcpd.service${nc}"
    fi
}

ver_Configuracion(){
    local config_file="/etc/dhcpd.conf"
    local sysconfig="/etc/sysconfig/dhcpd"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${rojo}No se encontró el archivo de configuración${nc}"
        echo -e "${amarillo}Parece que el servidor DHCP no está configurado aún${nc}"
        return 1
    fi
    
    echo -e "\n${azul}========== CONFIGURACIÓN ACTUAL DEL SERVIDOR DHCP ==========${nc}\n"
    
    echo -e "${verde}Archivo de configuración principal:${nc} $config_file"
    echo -e "${amarillo}-----------------------------------------------------------${nc}"
    cat "$config_file"
    echo -e "${amarillo}-----------------------------------------------------------${nc}\n"
    
    if [ -f "$sysconfig" ]; then
        echo -e "${verde}Interfaz configurada:${nc}"
        cat "$sysconfig"
        echo ""
    fi
    
    echo -e "${verde}Estado del servicio:${nc}"
    sudo systemctl status dhcpd --no-pager | head -n 5
    
    echo -e "\n${azul}============================================================${nc}\n"
}

ver_Estado(){
    echo -e "${azul}ESTADO DEL SERVIDOR DHCP ${nc}\n"
    sudo systemctl status dhcpd --no-pager
}

verificar_Instalacion(){
	# Comprobar si esta instalada la paqueteria de DHCP
	local opc

	echo -e "${amarillo}Verificando paqueteria DHCP...${nc}"
	if ! zypper search --installed-only | grep -q dhcp; then
		echo -e "${rojo}DHCP no esta instalado${nc}"
		read -p "Desea instalarlo? (y/n): " opc
		if [[ $opc = "y" ]]; then
            instalar_DHCP
			exit
		fi
	else
		echo -e "${verde}DHCP esta instalado${nc}"
	fi
}

instalar_DHCP(){
    # Instalar DHCP
	sudo zypper --non-interactive install dhcp-server
	echo -e "${verde}DHCP ya esta instalado, continuando con la configuracion...${nc}"
}

configurar_DHCP(){
	local ip_Valida=""
    local uso_Mas=""
    local comp=""

	echo -e "\nConfiguracion Dinamica\n"

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
			echo -e "No use X.X.X.255 como ultimo octeto por temas de rendimiento"
			echo -e "Intentando nuevamente..."	
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
    			echo -e "${rojo}La IP no concuerda con el rango inicial${nc}"
			fi   
		fi
		
		if [ "$ip_Valida" = "no" ]; then
			echo -e "Intendo nuevamente..."
		fi
	done

	read -p "Tiempo de la sesion (segundos): " lease_Time

	until
		read -p "Gateway: " gateway
		validar_IP "$gateway" 
	do
		echo -e "Intentado nuevamente..."
	done

	comp="no"
	until [[ "$comp" = "si" ]]; do
		read -p "DNS principal (puede quedar vacio): " dns
		if [ "$dns" = "" ]; then
			comp="si"
		elif validar_IP "$dns"; then
			comp="si"
		fi
		if [ "$comp" = "no" ]; then
			echo -e "Intentado nuevamente..."
		fi
	done

	comp="no"
	until [[ "$comp" = "si" ]]; do
		read -p "DNS alternativo (puede quedar vacio): " dns_Alt
		if [ "$dns_Alt" = "" ]; then
			comp="si"
		elif validar_IP "$dns_Alt"; then
			comp="si"
		fi
		if [ "$comp" = "no" ]; then
			echo -e "Intentado nuevamente..."
		fi
	done

	# Detectar interfaz de red automáticamente o pedir al usuario
	echo -e "\n${amarillo}Interfaces de red disponibles:${nc}"
	ip -br link show | grep -v "lo" | awk '{print $1}'
	read -p "Ingrese la interfaz de red a usar (ej: enp0s8): " interfaz

    echo -e "\n${azul}La configuracion final es:${nc}"
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
	
	echo -e "${amarillo}Red calculada: $red${nc}"
	echo -e "${amarillo}Broadcast calculado: $broadcast${nc}"
	
	# Crear configuración DHCP
	echo -e "${amarillo}Creando configuración DHCP...${nc}"
	sudo bash -c "cat > /etc/dhcpd.conf" << EOF
# Configuracion DHCP - $scope
default-lease-time $lease_Time;
max-lease-time $((lease_Time * 2));
authoritative;

subnet $red netmask $mascara {
    range $ip_Inicial $ip_Final;
    option routers $gateway;
    option subnet-mask $mascara;
$(if [ "$dns" != "" ] && [ "$dns_Alt" != "" ]; then
    echo "    option domain-name-servers $dns, $dns_Alt;"
elif [ "$dns" != "" ]; then
    echo "    option domain-name-servers $dns;"
fi)
    option broadcast-address $broadcast;
}
EOF

		# Configurar interfaz
		interfaz="enp0s8"
		echo -e "${amarillo}Configurando interfaz de red...${nc}"
		sudo bash -c "echo 'DHCPD_INTERFACE=\"$interfaz\"' > /etc/sysconfig/dhcpd"
		
		echo -e "${amarillo}Configurando IP estática $ip_Servidor en la interfaz $interfaz...${nc}"
		sudo ip addr flush dev $interfaz
		sudo ip addr add $ip_Servidor/$( calcular_Bits "$mascara" ) dev $interfaz
		sudo ip link set $interfaz up

sudo bash -c "cat > /etc/sysconfig/network/ifcfg-$interfaz" << EOF
BOOTPROTO='static'
STARTMODE='auto'
IPADDR='$ip_Servidor'
NETMASK='$mascara'
EOF

		# Reiniciar servicio
		echo -e "${amarillo}Reiniciando servicio DHCP...${nc}"
		sudo systemctl restart dhcpd
		
		echo -e "${verde}IP estática $ip_Servidor configurada en $interfaz${nc}"

		# Verificar estado
		if sudo systemctl is-active --quiet dhcpd; then
			echo -e "${verde}¡Servidor DHCP configurado y funcionando correctamente!${nc}"
			sudo systemctl status dhcpd --no-pager
		else
			echo -e "${rojo}Error al iniciar el servicio DHCP${nc}"
			echo -e "${amarillo}Ejecute: sudo journalctl -xeu dhcpd.service${nc}"
		fi
    else
        echo -e "${amarillo}Volviendo a configurar...${nc}"
        configurar_DHCP
    fi
}

# ---------- Main ----------
case $1 in
    -help | --help) ayuda ;;
    -mt | --monitor) monitorear_Clientes ;;
    -rt | --restart) reiniciar_DHCP ;;
	-st | --status) ver_Estado ;;
	-sc | --showConfig) ver_Configuracion ;;
    -vr | --verify) verificar_Instalacion ;;
    -is | --install) instalar_DHCP ;;
    -cf | --config) configurar_DHCP ;;
esac
