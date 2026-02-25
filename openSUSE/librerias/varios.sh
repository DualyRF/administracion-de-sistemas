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
