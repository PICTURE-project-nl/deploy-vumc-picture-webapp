#!/bin/bash

# Check the operating system
OS="$(uname)"

# Function to check if a command is installed and install it if not
check_and_install() {
    local cmd="$1"
    local install_cmd="$2"

    if ! command -v "$cmd" &>/dev/null; then
        echo "$cmd is not installed. Attempting to install..."
        eval "$install_cmd"
    fi
}

# Check if Git is installed, if not install it
if [ "$OS" == "Darwin" ]; then # macOS
    check_and_install git "brew install git"
    check_and_install wget "brew install wget"
    check_and_install gzip "brew install gzip"
elif [ "$OS" == "Linux" ]; then # Linux
    check_and_install git "sudo apt-get install -y git"
    check_and_install wget "sudo apt-get install -y wget"
    check_and_install gzip "sudo apt-get install -y gzip"
else
    echo "Unsupported operating system. Please install the necessary tools manually."
    exit 1
fi

# Clone repositories if they do not exist, or update if they do
clone_or_update_repo() {
    local repo_url="$1"
    local repo_dir="$(basename "$repo_url" .git)"

    if [ ! -d "$repo_dir" ]; then
        echo "Cloning $repo_dir..."
        git clone "$repo_url"
    else
        echo "Directory '$repo_dir' already exists. Pulling latest changes."
        cd "$repo_dir" && git pull origin && cd ..
    fi
}

cd ..
clone_or_update_repo git@github.com:PICTURE-project-nl/vumc-picture-filter.git
clone_or_update_repo git@github.com:PICTURE-project-nl/vumc-picture-webapp.git
clone_or_update_repo git@github.com:PICTURE-project-nl/reverse-proxy.git
clone_or_update_repo git@github.com:PICTURE-project-nl/vumc-picture-api.git

# Move secrets and copy dummy data if necessary
if [ -d "vumc-picture-api" ] && [ -f "vumc-picture-api/sample.secrets.env" ]; then
    cp ./vumc-picture-api/sample.secrets.env ./vumc-picture-api/secrets.env
fi
if [ -d "vumc-picture-webapp" ] && [ -f "vumc-picture-webapp/.env-sample" ]; then
    cp ./vumc-picture-webapp/.env-sample ./vumc-picture-webapp/.env
fi
if [ -d "vumc-picture-webapp/src/assets" ]; then
    cp -n ./vumc-picture-webapp/src/assets/dummyGSIData.json ./vumc-picture-webapp/src/assets/dummyFilterPatientData.json
fi

# Create directory for brain volume files if necessary
mkdir -p ./vumc-picture-webapp/src/static/brain-volumes/1/

# Copy the existing standard.nii file if present
if [ -f ./vumc-picture-filter/data/MNI152_T1_1mm.nii ]; then
    cp ./vumc-picture-filter/data/MNI152_T1_1mm.nii ./vumc-picture-webapp/src/static/brain-volumes/1/standard.nii
    echo "MNI152_T1_1mm.nii copied successfully."
else
    echo "Warning: MNI152_T1_1mm.nii not found in vumc-picture-filter/data/. Please ensure it exists."
fi

# Final message to user
echo "Cloning and setup complete! You can now run the restart.sh script to create the network and containers."