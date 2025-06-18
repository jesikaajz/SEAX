#!/bin/bash

# Jesika Jimenez Prado
# Joaquin Tourón Morris

# Dependències i menú d'ajuda
dependencies=(iw awk grep mktemp awk sort uniq bc)

verbose=false
interface=""

show_help() {
	echo "Ús: $0 [OPCIONS]"
	echo ""
	echo "Aquest script localitza l'espai més probable en funció de les dades WiFi prèviament entrenades."
	echo ""
	echo "Opcions:"
	echo "	-h, --help	Mostra aquest missatge d'ajuda i surt"
	echo "	-v		Mode verbós (mostra informació addicional)"
	echo "	-i INTERFACE	(Obligatori) Especifica la interfície de xarxa a utilitzar"
	echo ""
	echo "Dependències necessàries: ${dependencies[*]}"
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
	show_help
	exit 0
fi

# Gestionar les opcions
while getopts ":vi:" opt; do
	case ${opt} in
	v)
		verbose=true
		;;
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

# Verificació de fitxer d'entrenament
TRAINING_FILE="dades.csv"

if [ ! -f "$TRAINING_FILE" ]; then
	echo "No s'ha trobat el fitxer d'entrenament $TRAINING_FILE. Executeu l'script d'entrenament primer."
	exit 1
fi

# Escanejar xarxes actuals
echo -e "Escanejant xarxes WiFi..."

TEMP_FILE=$(mktemp)
iw dev wlan0 scan | grep -E "^BSS|^\s*signal:" >"$TEMP_FILE"

declare -A current_signals
BSSID=""

while read -r line; do
	if echo "$line" | grep -q '^BSS'; then
		BSSID=$(echo "$line" | awk '{print $2}' | sed 's/(.*//')
	fi
	if echo "$line" | grep -q '^\s*signal:'; then
		SIGNAL=$(echo "$line" | awk '{print $2}')
		current_signals[$BSSID]=$SIGNAL
	fi
done <"$TEMP_FILE"

rm "$TEMP_FILE"

# Funció per calcular la distància
distance() {
	local space=$1
	local bssid
	local distance=0
	local count=0
	declare -A previous_signals

	while IFS=, read -r space_read bssid_read signal_read; do
		if [[ "$space_read" == "$space" ]]; then
			previous_signals[$bssid_read]=$signal_read
		fi
	done <"$TRAINING_FILE"

	for bssid in "${!current_signals[@]}"; do
		current_signal=${current_signals[$bssid]}
		if [[ -n "${previous_signals[$bssid]}" ]]; then
			((count++))
		fi
		previous_signal=${previous_signals[$bssid]:--100}
		diff=$(echo "$current_signal - $previous_signal" | bc | sed 's/-//')
		distance=$(echo "$distance + ($diff ^ 2)" | bc)
		unset previous_signals[$bssid]
	done

	for bssid in "${!previous_signals[@]}"; do
		previous_signal=${previous_signals[$bssid]}
		diff=$(echo "-100 - $previous_signal" | bc | sed 's/-//')
		distance=$(echo "$distance + ($diff ^ 2)" | bc)
	done

	if [[ $count -gt 0 ]]; then
		result=$(echo "scale=2; sqrt($distance)" | bc)
		echo "$count $result"
	else
		echo "$count 9999.00"
	fi
}

# Trobar l'espai més proper
best_space=""
best_distance=9999

spaces=$(awk -F, 'NR>1 {print $1}' "$TRAINING_FILE" | sort | uniq)

for space in $spaces; do
	res=$(distance "$space")
	count=$(echo "$res" | awk '{print $1}')
	dist=$(echo "$res" | awk '{print $2}')
	if [[ $verbose == true ]]; then
		echo -e "\n$space:\n\tBSSID Coincidències: $count\n\tDistància: $dist"
	fi
	if (($(echo "$dist < $best_distance" | bc -l))); then
		best_distance=$dist
		best_space=$space
	fi
done

if [[ $best_distance == 9999 ]]; then
	echo -e "\nNo s'ha pogut trobar l'espai més proper."
else
	echo -e "\nL'espai més probable és: $best_space (Distància: $best_distance)"
fi
