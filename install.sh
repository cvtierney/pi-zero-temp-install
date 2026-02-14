#!/bin/bash

set -e

echo "=== Enabling 1-Wire interface ==="
if ! grep -q "dtoverlay=w1-gpio" /boot/config.txt; then
    echo "dtoverlay=w1-gpio" | sudo tee -a /boot/config.txt
    echo "1-Wire enabled. Reboot required after installation."
else
    echo "1-Wire already enabled."
fi

echo "=== Updating system and installing Flask ==="
sudo apt update
sudo apt install -y python3 python3-pip python3-flask

echo "=== Creating temperature sensor API script ==="

cat << 'EOF' | sudo tee /home/chris/tempsensor.py > /dev/null
import os
from flask import Flask, jsonify

app = Flask(__name__)

base_dir = '/sys/bus/w1/devices/'
device_folder = None

# Find DS18B20 device
for d in os.listdir(base_dir):
    if d.startswith('28-'):
        device_folder = d
        break

if device_folder:
    device_file = f"{base_dir}{device_folder}/w1_slave"
else:
    device_file = None

def read_temp():
    if not device_file:
        return None

    with open(device_file, 'r') as f:
        lines = f.readlines()

    if "YES" not in lines[0]:
        return None

    temp_output = lines[1].split("t=")[-1]
    temp_c = float(temp_output) / 1000.0
    temp_f = temp_c * 9.0 / 5.0 + 32.0

    return {"celsius": temp_c, "fahrenheit": temp_f}

@app.route('/temp')
def temp():
    data = read_temp()
    if data is None:
        return jsonify({"error": "Sensor read error"}), 500
    return jsonify(data)

@app.route('/')
def home():
    return jsonify({"status": "online", "endpoint": "/temp"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

sudo chmod +x /home/chris/tempsensor.py
sudo chown chris:chris /home/chris/tempsensor.py

echo "=== Creating systemd service ==="

cat << 'EOF' | sudo tee /etc/systemd/system/tempsensor.service > /dev/null
[Unit]
Description=Temperature Sensor Web API
After=network.target

[Service]
ExecStart=/usr/bin/python3 /home/chris/tempsensor.py
WorkingDirectory=/home/chris
Restart=always
User=chris

[Install]
WantedBy=multi-user.target
EOF

echo "=== Enabling and starting service ==="
sudo systemctl daemon-reload
sudo systemctl enable tempsensor
sudo systemctl start tempsensor

echo "=== Installation complete ==="
echo "Reboot recommended if 1-Wire was newly enabled."
echo "Access your sensor at: http://<pi-ip>:8080/temp"
