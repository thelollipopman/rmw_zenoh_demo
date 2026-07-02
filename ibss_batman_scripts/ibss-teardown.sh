#!/bin/bash
set -e

IFACE="wlan0"

echo "[*] Flushing IP addresses from $IFACE..."
sudo ip addr flush dev "$IFACE" 2>/dev/null || true

echo "[*] Bringing $IFACE down..."
sudo ip link set "$IFACE" down 2>/dev/null || true

echo "[*] Returning $IFACE to managed Wi-Fi mode..."
sudo iw dev "$IFACE" set type managed 2>/dev/null || true

echo "[*] Bringing $IFACE up..."
sudo ip link set "$IFACE" up 2>/dev/null || true

echo "[*] Restarting normal network services..."
sudo systemctl start wpa_supplicant 2>/dev/null || true
sudo systemctl start NetworkManager 2>/dev/null || true

echo "[*] Returning $IFACE to NetworkManager control..."
sudo nmcli dev set "$IFACE" managed yes 2>/dev/null || true

echo "[+] IBSS teardown complete."