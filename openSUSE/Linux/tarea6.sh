#!/bin/bash
# =============================================================================
# main.sh — Script principal de aprovisionamiento web
# Proyecto : Aprovisionamiento Web Automatizado
# SO       : OpenSUSE Leap
# Uso      : sudo bash main.sh [-i|-v|-r]
# =============================================================================

source ./lib/utils.sh
source ./lib/http_functions.sh

# -----------------------------------------------------------------------------
# MENÚ PRINCIPAL
# -----------------------------------------------------------------------------
menu_principal() {
    while true; do
        print_title "Aprovisionamiento Web Automatizado"
        print_menu "  [1] Instalar servidor HTTP"
        print_menu "  [2] Ver estado de servidores"
        print_menu "  [3] Revisar respuesta HTTP (curl)"
        print_menu "  [0] Salir"
        echo ""
        echo -ne "${cyan}Selecciona una opción: ${nc}"
        read -r opcion

        case "$opcion" in
            1) menu_instalacion ;;
            2) verificar_HTTP   ;;
            3) revisar_HTTP     ;;
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
# SUBMENÚ INSTALACIÓN
# -----------------------------------------------------------------------------
menu_instalacion() {
    print_title "Instalar Servidor HTTP"
    print_menu "  [1] Apache2"
    print_menu "  [2] Nginx"
    print_menu "  [3] Tomcat"
    print_menu "  [0] Volver"
    echo ""
    echo -ne "${cyan}Selecciona un servidor: ${nc}"
    read -r opcion

    case "$opcion" in
        1) setup_apache  ;;
        2) setup_nginx   ;;
        3) setup_tomcat  ;;
        0) return        ;;
        *) print_warning "[ERROR] Opción inválida." ;;
    esac
}

# -----------------------------------------------------------------------------
# INICIO — soporta flags o menú interactivo
# -----------------------------------------------------------------------------
verificar_root

case "$1" in
    -i|--instalar)  menu_instalacion ;;
    -v|--verificar) verificar_HTTP   ;;
    -r|--revisar)   revisar_HTTP     ;;
    "")             menu_principal   ;;
    *)
        echo ""
        print_menu "  -i / --instalar   Instalar servidor HTTP"
        print_menu "  -v / --verificar  Ver estado de servidores"
        print_menu "  -r / --revisar    Revisar respuesta HTTP (curl)"
        echo ""
        ;;
esac