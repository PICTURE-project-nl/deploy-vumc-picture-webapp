#!/bin/bash

# Function to check if a command is installed
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        echo "$cmd is not installed. Please install $cmd before running this script."
        exit 1
    fi
}

check_command docker
check_command docker compose

# Check if the required directories exist
cd ..
base_dir=$(pwd)
required_directories=("vumc-picture-webapp" "vumc-picture-filter" "vumc-picture-api" "reverse-proxy")
for directory in "${required_directories[@]}"; do
    if [ ! -d "$base_dir/$directory" ]; then
        echo "Directory $directory does not exist in the expected location ($base_dir). Please ensure the directory exists before running this script."
        exit 1
    fi
done

# Prompt the user for environment if not already set, with default option 1
if [ -z "$ENVIRONMENT" ]; then
    echo "Select the environment to run the container:"
    echo "1) localhost (default)"
    echo "2) server"
    read -p "Enter the number for your choice [1]: " choice
    choice=${choice:-1}

    case "$choice" in
        1) ENVIRONMENT="localhost" ;;
        2) ENVIRONMENT="server" ;;
        *) echo "Invalid choice. Defaulting to localhost."; ENVIRONMENT="localhost" ;;
    esac
    export ENVIRONMENT
fi

# Prompt for URL if "server" is selected
if [ "$ENVIRONMENT" == "server" ] && [ -z "$SERVER_URL" ]; then
    echo "Please enter the server URL (e.g., https://example.com):"
    read -r SERVER_URL
    export SERVER_URL
fi

echo "Environment set to: $ENVIRONMENT"
[ "$ENVIRONMENT" == "server" ] && echo "Server URL: $SERVER_URL"

# Generate .env file based on the selected environment
echo "Generating .env configuration for Nuxt project..."
cd "$base_dir/vumc-picture-webapp" || exit
python3 generate_env.py || { echo "Failed to generate .env configuration"; exit 1; }

echo "Checking presence of required commands and Docker networks..."

# Create Docker networks if they do not exist
create_docker_network() {
    local network="$1"
    if docker network ls | grep -q "$network"; then
        echo "Network $network already exists. Re-creating..."
        docker network rm "$network"
        sleep 3
    fi
    docker network create "$network"
}

# Define a function to handle Docker Compose Down
run_docker_compose_down() {
    network_prefix="$1"
    local directory="$2"
    local compose_file="$3"
    local env_file="$4"

    cd "$base_dir/$directory" || exit
    export NETWORK_PREFIX=${network_prefix}

    if [ -n "$env_file" ]; then
        docker compose --verbose -f "${compose_file}" --env-file "${env_file}" down -v
    else
        docker compose --verbose -f "${compose_file}" down -v
    fi
}

# Define a function to handle Docker Compose Up
run_docker_compose_up() {
    network_prefix="$1"
    local directory="$2"
    local compose_file="$3"
    local env_file="$4"

    cd "$base_dir/$directory" || exit
    export NETWORK_PREFIX=${network_prefix}
    export GPU_AVAILABLE=$(command -v nvidia-smi > /dev/null 2>&1 && echo 1 || echo 0)
    export TARGET_ARCH=$(uname -m)

    if [ -n "$env_file" ]; then
        docker compose --verbose -f "${compose_file}" --env-file "${env_file}" build
        docker compose --verbose -f "${compose_file}" --env-file "${env_file}" up -d
    else
        docker compose --verbose -f "${compose_file}" build
        docker compose --verbose -f "${compose_file}" up -d
    fi
}

# Generate hash for network prefix
SCRIPT_PATH=$(dirname "$(realpath "$0")")
HASHED_PATH=$(echo -n "$SCRIPT_PATH" | openssl dgst -sha256 | awk '{print $2}')
export NETWORK_PREFIX=${HASHED_PATH}
export GPU_AVAILABLE=$(command -v nvidia-smi > /dev/null 2>&1 && echo 1 || echo 0)

# Remove generated docker-compose file if it exists
rm -f "$base_dir/vumc-picture-api/docker-compose.generated.yml"

# Run Python scripts to generate Docker Compose configurations
cd "$base_dir/vumc-picture-api" || exit
python3 generate_docker_compose.py || { echo "Failed to generate docker-compose file for API."; exit 1; }

cd "$base_dir/reverse-proxy" || exit
python3 generate_docker_compose_and_nginx.py || { echo "Failed to generate docker-compose and nginx config for reverse-proxy."; exit 1; }

cd "$base_dir/vumc-picture-filter" || exit
python3 generate_docker_compose.py || { echo "Failed to generate docker-compose file for filter."; exit 1; }

# Check if dataset is present in filter
dataset_dir="$base_dir/vumc-picture-filter/data"
file_count=$(find "$dataset_dir" -type f | wc -l)

echo "Dataset files found: $file_count"
if [ "$file_count" -lt 2 ]; then
    echo "Only test dataset found in $dataset_dir"
    echo "Options:"
    echo "1) Pause and upload dataset, then restart script manually"
    echo "2) Continue without dataset"
    echo "3) Exit script"
    read -p "Choose an option [1]: " dataset_choice
    dataset_choice=${dataset_choice:-1}
    case "$dataset_choice" in
        1) echo "Please upload the dataset and re-run the script manually."; exit 0 ;;
        2) echo "Continuing without dataset." ;;
        3) echo "Exiting script."; exit 1 ;;
        *) echo "Invalid choice. Exiting."; exit 1 ;;
    esac
fi

# Stop any running containers
run_docker_compose_down "${HASHED_PATH}" "vumc-picture-webapp" "docker-compose.yml"
run_docker_compose_down "${HASHED_PATH}" "vumc-picture-filter" "docker-compose.generated.yml"
run_docker_compose_down "${HASHED_PATH}" "vumc-picture-api" "docker-compose.generated.yml" "secrets.env"
run_docker_compose_down "${HASHED_PATH}" "reverse-proxy" "docker-compose.generated.yml"

# Wait before re-creating networks
sleep 10
create_docker_network "${HASHED_PATH}_proxy"
sleep 5
create_docker_network "${HASHED_PATH}_filtering"
sleep 10

# Start services
run_docker_compose_up "${HASHED_PATH}" "vumc-picture-webapp" "docker-compose.yml"
run_docker_compose_up "${HASHED_PATH}" "vumc-picture-filter" "docker-compose.generated.yml"
run_docker_compose_up "${HASHED_PATH}" "vumc-picture-api" "docker-compose.generated.yml" "secrets.env"

echo "Waiting 20 seconds for API to initialize..."
sleep 20

# Aggregate dataset
cd "$base_dir/vumc-picture-api" || exit
docker exec -it vumc-picture-api-api-1 /bin/sh -c "cd /var/www/laravel/vumc-picture-api && php artisan dataset:update" || echo "Failed to update dataset."

# Restart reverse proxy
run_docker_compose_down "${HASHED_PATH}" "reverse-proxy" "docker-compose.generated.yml"
run_docker_compose_up "${HASHED_PATH}" "reverse-proxy" "docker-compose.generated.yml"

# Certbot if environment is 'server'
if [ "$ENVIRONMENT" == "server" ]; then
    DOMAIN=$(echo "$SERVER_URL" | sed -e 's~http[s]*://~~g')
    echo "Running Certbot for domain: $DOMAIN"
    docker exec reverse-proxy-nginx-1 certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m info@"$DOMAIN"
    sleep 20
fi

# Reload Nginx
docker exec reverse-proxy-nginx-1 nginx -s reload || echo "Failed to reload Nginx."

# Optional user creation
cd "$base_dir/vumc-picture-api" || exit
docker exec -it vumc-picture-api-api-1 /bin/sh -c "cd /var/www/laravel/vumc-picture-api && php artisan user:create --confirm" || echo "User creation failed."

echo "Installation and setup completed successfully!"