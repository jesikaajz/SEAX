#!/bin/bash

# Jesika Jimenez Prado
# Joaquin Tourón Morris

# Dependències i menú d'ajuda
dependencies=(ip awk grep ping curl)

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
	echo "Ús: $0 [OPCIONS]"
	echo ""
	echo "Aquest script mostra informació en temps real sobre les interfícies Ethernet disponibles."
	echo "Inclou dades com l'adreça IP, tipus de connexió, NAT, IP pública, latència i tràfic de baixada i de pujada."
	echo ""
	echo "Opcions:"
	echo "	-h, --help		Mostra aquest missatge d'ajuda i surt"
	echo ""
	echo "Dependències necessàries: ${dependencies[*]}"
	echo ""
	echo "Com aturar el programa:"
	echo "	• Premeu qualsevol tecla per sortir."
	echo "	• També podeu utilitzar Ctrl + C per forçar la sortida."
	exit 0
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

# Funció per obtenir informació d'una interfície Ethernet
get_interface_info() {
	local interface=$1
	local ip_priv
	local default_gateway
	local nat
	local connection_type
	local ip_public
	local rtt
	local download
	local upload
	local download_rate
	local upload_rate
	local download_rate_new
	local upload_rate_new

	# Comprovar si la interfície està habilitada
	if ip link show "$interface" | grep -q 'state DOWN'; then
		echo "$interface: (cable desconnectat)"
		return
	fi

	# Obtenir l'adreça IP privada
	ip_priv=$(ip -4 addr show "$interface" | awk '/inet / {print $2}' | cut -d'/' -f1)

	if [[ -z "$ip_priv" ]]; then
		ip_priv="Sense IP assignada"
	fi

	# Comprovar si un servidor DHCP ha donat una IP a la interfície (IP dinàmica o estàtica)
	if grep -q "dhcp" "/var/lib/dhcp/dhclient.$interface.leases" 2>/dev/null; then
		connection_type="DHCP"
	else
		connection_type="estàtica"
	fi

	# Comprovar si el router per defecte té una adreça IP privada (detectar NAT)
	default_gateway=$(ip route show default | grep "$interface" | grep via | awk '{print $3}')

	if [[ "$default_gateway" =~ ^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]]; then
		nat="NAT detectat"
	fi

	# Obtenir l'adreça ip pública si la interfície té accés a l'exterior
	ip_public=$(curl --connect-timeout 0.5 --interface "$interface" -s ifconfig.me)

	# Obtenir la latència fent ping a Cloudflare
	rtt=$(ping -I "$interface" -c 1 -W 0.5 1.1.1.1 | grep 'time=' | cut -d'=' -f4)

	# Obtenir el tràfic de baixada i de pujada
	download_rate=$(cat /sys/class/net/$interface/statistics/rx_bytes)
	upload_rate=$(cat /sys/class/net/$interface/statistics/tx_bytes)

	sleep 1

	download_rate_new=$(cat /sys/class/net/$interface/statistics/rx_bytes)
	upload_rate_new=$(cat /sys/class/net/$interface/statistics/tx_bytes)

	download=$(((download_rate_new - download_rate) * 8 / 1000))
	upload=$(((upload_rate_new - upload_rate) * 8 / 1000))

	# Mostrar la informació
	local first_line="$interface: $ip_priv: $connection_type"
	if [ -n "$nat" ] && [ -n "$ip_public" ]; then
		first_line="$first_line ($nat, adreça pública: $ip_public)"
	elif [ -n "$ip_public" ]; then
		first_line="$first_line (adreça pública: $ip_public)"
	elif [ -n "$nat" ]; then
		first_line="$first_line ($nat)"
	fi
	echo "$first_line"
	echo "	RTT (1.1.1.1): ${rtt:-"-"}"
	echo "	Tràfic cursat de baixada: $download kbps"
	echo "	Tràfic cursat de pujada: $upload kbps"
}

# Bucle principal amb 5s d'interval
main_loop() {
	first=true
	while true; do
		if [ "$first" = true ]; then
			clear
			echo "Carregant informació..."
			first=false
		fi

		output=""
		first_interface=true
		for interface in $(ip -o link show | awk -F': ' '{print $2}' | grep '^en'); do
			if [ "$first_interface" = false ]; then
				output+="\n\n"
			fi
			first_interface=false
			info=$(get_interface_info "$interface")
			output+="$info"
		done
		clear
		echo -e "\e[7m ‹ Pressiona qualsevol tecla per sortir, interval d'actualització: 5s › \e[27m\n"
		echo -e "$output"
		sleep 5
	done
}

main_loop &
pid=$!

# Acabar el programa en prémer una tecla
while read -n 1 -s -r; do
	kill "$pid"
	kill -SIGINT $$
done
