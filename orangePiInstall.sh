#!/bin/bash
set -e

# Determine if kernel header .deb files are present in /opt
HEADER_DEBS=$(ls /opt/linux-headers-*.deb 2>/dev/null || true)
if [[ -n "$HEADER_DEBS" ]]; then
    echo "Found local kernel header packages in /opt. Installing headers..."
    sudo dpkg -i /opt/linux-headers-*.deb
    # After installing, ensure DKMS can find the kernel source
    KVER="$(uname -r)"
    if [[ -d "/usr/src/linux-headers-$KVER" ]]; then
        echo "Linking /usr/src/linux-headers-$KVER to /lib/modules/$KVER/build for DKMS."
        sudo ln -sf "/usr/src/linux-headers-$KVER" "/lib/modules/$KVER/build"
    fi
else
    echo "No local kernel headers found. Installing raspberrypi-kernel-headers from repositories..."
    sudo apt-get update
    sudo apt-get install -y raspberrypi-kernel-headers
fi

# [Insert your DKMS module build/installation steps here as before]
# For example: install_module "./" "wm8960-soundcard"

# Set up device tree overlay paths and configuration based on platform
OVERLAY_NAME="wm8960-soundcard"   # Actual overlay base name (without .dtbo extension)
DTBO_FILE="${OVERLAY_NAME}.dtbo"

# Determine the appropriate boot configuration file and overlay directory
if [[ -f "/boot/config.txt" || -f "/boot/firmware/config.txt" ]]; then
    # Raspberry Pi OS or Ubuntu on Raspberry Pi (uses config.txt and /boot overlays)
    if [[ -f "/boot/config.txt" ]]; then
        CONFIG_FILE="/boot/config.txt"
        OVERLAY_DIR="/boot/overlays"
    else
        CONFIG_FILE="/boot/firmware/config.txt"
        OVERLAY_DIR="/boot/firmware/overlays"
    fi
    echo "Raspberry Pi environment detected. Using $CONFIG_FILE for configuration."
    sudo install -Dm644 "$DTBO_FILE" "$OVERLAY_DIR/$DTBO_FILE"
    if ! grep -q "dtoverlay=${OVERLAY_NAME}" "$CONFIG_FILE"; then
        echo "Enabling dtoverlay=${OVERLAY_NAME} in $CONFIG_FILE."
        echo "dtoverlay=${OVERLAY_NAME}" | sudo tee -a "$CONFIG_FILE" >/dev/null
    fi

elif [[ -f "/boot/orangepiEnv.txt" ]]; then
    # Orange Pi specific config file detected
    CONFIG_FILE="/boot/orangepiEnv.txt"
    echo "Orange Pi environment detected via orangepiEnv.txt. Using $CONFIG_FILE for configuration."
    # Determine overlay directory: check for a standard location; adjust as needed.
    if [[ -d "/boot/dtb/allwinner/overlay" ]]; then
        OVERLAY_DIR="/boot/dtb/allwinner/overlay"
    elif [[ -d "/boot/overlay-user" ]]; then
        OVERLAY_DIR="/boot/overlay-user"
    else
        OVERLAY_DIR="/boot/dtb/allwinner/overlay"
        sudo mkdir -p "$OVERLAY_DIR"
    fi
    sudo install -Dm644 "$DTBO_FILE" "$OVERLAY_DIR/$DTBO_FILE"
    if ! grep -q "dtoverlay=${OVERLAY_NAME}" "$CONFIG_FILE"; then
        echo "Enabling dtoverlay=${OVERLAY_NAME} in $CONFIG_FILE."
        echo "dtoverlay=${OVERLAY_NAME}" | sudo tee -a "$CONFIG_FILE" >/dev/null
    fi

elif [[ -f "/boot/armbianEnv.txt" ]]; then
    echo "Armbian environment detected. Configuring /boot/armbianEnv.txt to load the overlay."
    CONFIG_FILE="/boot/armbianEnv.txt"
    # Choose the overlay directory
    if [[ -d "/boot/overlay-user" ]]; then
        OVERLAY_DIR="/boot/overlay-user"
    elif [[ -d "/boot/dtb/allwinner/overlay" ]]; then
        OVERLAY_DIR="/boot/dtb/allwinner/overlay"
    elif [[ -d "/boot/dtbs/allwinner/overlay" ]]; then
        OVERLAY_DIR="/boot/dtbs/allwinner/overlay"
    else
        OVERLAY_DIR="/boot/overlay-user"
        sudo mkdir -p "$OVERLAY_DIR"
    fi
    sudo install -Dm644 "$DTBO_FILE" "$OVERLAY_DIR/$DTBO_FILE"
    OVERLAY_CFG="user_overlays"
    if ! grep -q "^${OVERLAY_CFG}=" "$CONFIG_FILE"; then
        if grep -q "^overlays=" "$CONFIG_FILE"; then
            OVERLAY_CFG="overlays"
        fi
    fi
    if grep -q "^${OVERLAY_CFG}=" "$CONFIG_FILE"; then
        sudo sed -i -r "/^${OVERLAY_CFG}=/ s/$/ ${OVERLAY_NAME}/" "$CONFIG_FILE"
    else
        echo "${OVERLAY_CFG}=${OVERLAY_NAME}" | sudo tee -a "$CONFIG_FILE" >/dev/null
    fi

elif [[ -f "/boot/extlinux/extlinux.conf" ]]; then
    echo "Extlinux environment detected. Configuring /boot/extlinux/extlinux.conf to load the overlay."
    CONFIG_FILE="/boot/extlinux/extlinux.conf"
    if [[ -d "/boot/dtbs/allwinner/overlay" ]]; then
        OVERLAY_DIR="/boot/dtbs/allwinner/overlay"
    else
        OVERLAY_DIR="/boot/dtb/allwinner/overlay"
        sudo mkdir -p "$OVERLAY_DIR"
    fi
    sudo install -Dm644 "$DTBO_FILE" "$OVERLAY_DIR/$DTBO_FILE"
    if ! grep -qi "FDTOVERLAYS" "$CONFIG_FILE"; then
        sudo sed -i "/^[ ]*APPEND /i \\\n    FDTOVERLAYS /dtbs/allwinner/overlay/${DTBO_FILE}\\n" "$CONFIG_FILE"
    elif ! grep -q "${DTBO_FILE}" "$CONFIG_FILE"; then
        sudo sed -i "s#FDTOVERLAYS \(.*\)#FDTOVERLAYS \1 /dtbs/allwinner/overlay/${DTBO_FILE}#" "$CONFIG_FILE"
    fi

else
    echo "No recognized boot configuration file found (config.txt, firmware/config.txt, orangepiEnv.txt, armbianEnv.txt, or extlinux.conf)."
    echo "Please add ${DTBO_FILE} to your boot config manually."
fi

# [Continue with any remaining steps from the original script...]
echo "I just finished, I hope it was as good for you as it was for me. Please reboot for changes to take effect."
