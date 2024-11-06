#!/bin/bash

# Check if the script is running on macOS or Linux
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macOS"
else
    OS="Linux"
fi

# Install Docker
if ! command -v docker &>/dev/null; then
    echo "Installing Docker..."
    if [ "$OS" == "macOS" ]; then
        brew install --cask docker
        open /Applications/Docker.app
    else
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh ./get-docker.sh
        sudo service docker start
    fi
else
    echo "Docker is already installed."
fi

# Install NVIDIA Docker toolkit (only on Linux)
if [ "$OS" == "Linux" ]; then
    if ! dpkg -l | grep -q nvidia-container-toolkit; then
        echo "Installing NVIDIA Docker toolkit..."
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID) \
            && curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
            && curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
                    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
                    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
        sudo apt-get update
        sudo apt-get install -y nvidia-container-toolkit
        sudo nvidia-ctk runtime configure --runtime=docker
        sudo systemctl restart docker
    else
        echo "NVIDIA Docker toolkit is already installed."
    fi
fi