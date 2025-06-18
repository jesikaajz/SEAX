#!/bin/bash

# Jesika Jimenez Prado
# Joaquin Tourón Morris

# Dependències i menú d'ajuda
dependencies=(iw awk grep mktemp)

interface=""

show_help() {
	echo "Ús: $0 [OPCIONS]"
	echo ""
	echo "Aquest script escaneja les xarxes WiFi disponibles i desa les dades en un fitxer CSV."
	echo "Guarda la següent informació: el nom de l'espai, BSSIDs i nivells de senyal."
	echo ""
	echo "Opcions:"
	echo "	-h, --help	Mostra aquest missatge d'ajuda i surt"
	echo "	-i INTERFACE	(Obligatori) Especifica la interfície de xarxa a utilitzar"
	echo ""
	echo "Dependències necessàries: ${dependencies[*]}"
	exit 0
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
	show_help
fi

# Gestionar les opcions
while getopts ":i:" opt; do
	case ${opt} in
	i)
		interface="$OPTARG"
		;;
	\?)
		echo -e "Opció invàlida: -$OPTARG\n" >&2
		show_help
		exit 1
		;;
	:)
		echo -e "Opció -$OPTARG requereix un argument.\n" >&2
		show_help
		exit 1
		;;
	esac
done
shift $((OPTIND - 1))

# Verificació de la interfície
if [ -z "$interface" ]; then
	echo -e "Error: Es requereix una interfície (-i)\n" >&2
	show_help
	exit 1
fi

if ! ip link show "$interface" &>/dev/null; then
	echo -e "Error: La interfície $interface no existeix.\n" >&2
	show_help
	exit 1
fi

# Verificació de privilegis d'usuari
if [[ $EUID -ne 0 ]]; then
	echo "Aquest script necessita permisos d'administrador. Executeu-lo com a root o amb sudo."
	exit 1
fi

# Verificació de dependències
missing=()

for cmd in "${dependencies[@]}"; do
	if ! command -v "$cmd" &>/dev/null; then
		missing+=("$cmd")
	fi
done

if [ ${#missing[@]} -gt 0 ]; then
	echo "Falten les següents eines: ${missing[*]}"
	echo "Instal·leu-les abans d'executar aquest script."
	exit 1
fi

# Crear el CSV si no existeix
OUTPUT_FILE="dades.csv"

if [ ! -f "$OUTPUT_FILE" ]; then
	echo "space,bbsid,signal" >"$OUTPUT_FILE"
fi

# Preguntar pel nom de l'espai
read -p "Escriu el nom de l'espai que vols escanejar (ex: cuina, dormitori1, jardí): " SPACE_NAME

# Escanejar les xarxes WiFi
echo "Escanejant xarxes WiFi..."

TEMP_FILE=$(mktemp)
iw dev wlan0 scan | grep -E "^BSS|^\s*signal:" >"$TEMP_FILE"

BSSID=""
SIGNAL=""

# Guardar les dades en el CSV
while read -r line; do
	if echo "$line" | grep -q '^BSS'; then
		BSSID=$(echo "$line" | awk '{print $2}' | sed 's/(.*//')
	fi
	if echo "$line" | grep -q '^\s*signal:'; then
		SIGNAL=$(echo "$line" | awk '{print $2}')
		echo "$SPACE_NAME,$BSSID,$SIGNAL" >>"$OUTPUT_FILE"
	fi
done <"$TEMP_FILE"

rm "$TEMP_FILE"

echo "Dades guardades en: $OUTPUT_FILE"
