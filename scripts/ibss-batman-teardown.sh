# 1. Stop BATMAN virtual interface
sudo ip link set bat0 down 2>/dev/null || true

# 2. Detach wlan0 from BATMAN
sudo batctl if del wlan0 2>/dev/null || true

# 3. Clear IPs from BATMAN and Wi-Fi interfaces
sudo ip addr flush dev bat0 2>/dev/null || true
sudo ip addr flush dev wlan0 2>/dev/null || true

# 4. Return wlan0 to normal Wi-Fi client mode
sudo ip link set wlan0 down
sudo iw dev wlan0 set type managed
sudo ip link set wlan0 up

# 5. Give control back to normal networking services
sudo systemctl start NetworkManager
sudo systemctl start wpa_supplicant
sudo nmcli dev set wlan0 managed yes