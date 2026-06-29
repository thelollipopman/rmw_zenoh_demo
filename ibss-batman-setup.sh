#!/bin/bash
set -e

IFACE="wlan0"
SSID="testibss"
FREQ="2437"

# Different for every Pi
IPADDR="192.168.100.1/24"

echo "[*] Stopping NetworkManager and wpa_supplicant..."
sudo systemctl stop NetworkManager || true
sudo systemctl stop wpa_supplicant || true

echo "[*] Loading batman-adv..."
sudo modprobe batman-adv

echo "[*] Cleaning old config..."
sudo ip link set bat0 down 2>/dev/null || true
sudo batctl if del "$IFACE" 2>/dev/null || true
sudo ip addr flush dev "$IFACE" 2>/dev/null || true
sudo ip addr flush dev bat0 2>/dev/null || true

echo "[*] Bringing $IFACE down..."
sudo ip link set "$IFACE" down

echo "[*] Switching $IFACE to IBSS mode..."
sudo iw "$IFACE" set type ibss

echo "[*] Bringing $IFACE up..."
sudo ip link set "$IFACE" up

echo "[*] Joining IBSS network \"$SSID\" on $FREQ MHz..."
sudo iw "$IFACE" ibss join "$SSID" "$FREQ"

echo "[*] Adding $IFACE to BATMAN-adv..."
sudo batctl if add "$IFACE"

echo "[*] Bringing bat0 up..."
sudo ip link set up dev bat0

echo "[*] Assigning IP address $IPADDR to bat0..."
sudo ip addr add "$IPADDR" dev bat0

echo "[+] IBSS + BATMAN configured!"
