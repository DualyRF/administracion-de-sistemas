source ./lib/varios.sh
source ./lib/funcionesHTTP.sh

# -----------------------------------------------------------------------------
# MENÚ PRINCIPAL
# -----------------------------------------------------------------------------
menu_principal() {
    while true; do
        print_title "Aprovisionamiento Web Automatizado"
        print_menu "  [1] Apache2"
        print_menu "  [2] Nginx"
        print_menu "  [3] Tomcat"
        print_menu "  [0] Salir"
        echo ""
        echo -ne "${cyan}Selecciona un servidor: ${nc}"
        read -r opcion

        case "$opcion" in
            1) setup_apache  ;;
            2) setup_nginx  ;;
            3) setup_tomcat ;;
            0) print_success "Saliendo..."; exit 0 ;;
            *) print_warning "[ERROR] Opción inválida." ;;
        esac

        echo ""
        echo -ne "${cyan}¿Volver al menú? [s/n]: ${nc}"
        read -r respuesta
        [[ "$respuesta" != "s" ]] && break
    done
}

# -----------------------------------------------------------------------------
# INICIO
# -----------------------------------------------------------------------------
verificar_root
menu_principal