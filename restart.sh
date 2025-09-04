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
        1)
            ENVIRONMENT="localhost"
            ;;
        2)
            ENVIRONMENT="server"
            ;;
        *)
            echo "Invalid choice. Defaulting to localhost."
            ENVIRONMENT="localhost"
            ;;
    esac
    export ENVIRONMENT
fi

# Prompt for URL if "server" is selected
if [ "$ENVIRONMENT" == "server" ] && [ -z "$SERVER_URL" ]; then
    echo "Please enter the server URL (e.g., https://example.com):"
    read -r SERVER_URL
    export SERVER_URL

    echo "Please enter the letsencrypt directory (Leave empty for default (/etc/letsencrypt)):"
    read -r LETSENCRYPT_DIR
    if [ -z "$LETSENCRYPT_DIRECTORY" ]; then
        LETSENCRYPT_DIRECTORY="/etc/letsencrypt"
    fi
    export LETSENCRYPT_DIRECTORY

    echo "Please enter the letsencrypt key directory (Leave empty for default (/etc/letsencrypt/live/tool.pictureproject.nl/)):"
    read -r LETSENCRYPT_KEY_DIRECTORY
    if [ -z "$LETSENCRYPT_KEY_DIRECTORY" ]; then
        LETSENCRYPT_KEY_DIRECTORY="/etc/letsencrypt/live/tool.pictureproject.nl/"
    fi
    export LETSENCRYPT_KEY_DIRECTORY
fi

echo "Environment set to: $ENVIRONMENT"
if [ "$ENVIRONMENT" == "server" ]; then
    echo "Server URL: $SERVER_URL"
fi

# Remove docker-compose.generated.yml if it exists
rm -f "$base_dir/vumc-picture-api/docker-compose.generated.yml"

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

    # shellcheck disable=SC2164
    cd "$base_dir/$directory"
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

    # shellcheck disable=SC2164
    cd "$base_dir/$directory"
    export NETWORK_PREFIX=${network_prefix}
    # shellcheck disable=SC2155
    export GPU_AVAILABLE=$(command -v nvidia-smi > /dev/null 2>&1 && echo 1 || echo 0)
    # shellcheck disable=SC2155
    export TARGET_ARCH=$(uname -m)

    if [ -n "$env_file" ]; then
        docker compose --verbose -f "${compose_file}" --env-file "${env_file}" build
        docker compose --verbose -f "${compose_file}" --env-file "${env_file}" up -d
    else
        docker compose --verbose -f "${compose_file}" build
        docker compose --verbose -f "${compose_file}" up -d
    fi
}

# Get the absolute path of the script
SCRIPT_PATH=$(dirname "$(realpath "$0")")

echo "$SCRIPT_PATH"
# Hash the script path using sha256sum
HASHED_PATH=$(echo -n "$SCRIPT_PATH" | openssl dgst -sha256 | awk '{print $2}')
export NETWORK_PREFIX=${HASHED_PATH}

# Stop running containers
echo "Stopping webapp service"
run_docker_compose_down "${HASHED_PATH}" "vumc-picture-webapp" "docker-compose.yml"
echo "Stopping filter service"
run_docker_compose_down "${HASHED_PATH}" "vumc-picture-filter" "docker-compose.generated.yml"
echo "Stopping API service"
run_docker_compose_down "${HASHED_PATH}" "vumc-picture-api" "docker-compose.yml" "secrets.env"
echo "Stopping reverse proxy"
run_docker_compose_down "${HASHED_PATH}" "reverse-proxy" "docker-compose.generated.yml"

# Create networks
echo "Creating network ${HASHED_PATH}_proxy"
create_docker_network ${HASHED_PATH}_proxy
sleep 5

echo "Creating network ${HASHED_PATH}_filtering"
create_docker_network ${HASHED_PATH}_filtering

echo "Wait 10 seconds for networks to be up"
sleep 10

# Start containers
echo "Starting webapp service"
run_docker_compose_up "${HASHED_PATH}" "vumc-picture-webapp" "docker-compose.yml"
echo "Starting filter service"
run_docker_compose_up "${HASHED_PATH}" "vumc-picture-filter" "docker-compose.generated.yml"
echo "Starting API service"
run_docker_compose_up "${HASHED_PATH}" "vumc-picture-api" "docker-compose.yml" "secrets.env"

echo "Wait 20 seconds for API to be up"
sleep 20

echo "Restarting reverse proxy"
run_docker_compose_down "${HASHED_PATH}" "reverse-proxy" "docker-compose.generated.yml"
run_docker_compose_up "${HASHED_PATH}" "reverse-proxy" "docker-compose.generated.yml"

# Certbot for server environment
if [ "$ENVIRONMENT" == "server" ]; then
    DOMAIN=$(echo "$SERVER_URL" | sed -e 's~http[s]*://~~g')
    echo "Running Certbot for SSL certificate generation for domain: $DOMAIN"

    docker exec reverse-proxy-nginx-1 certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m info@"$DOMAIN"

    sleep 20
fi

# Reload Nginx
echo "Reloading Nginx to apply SSL configuration"
docker exec reverse-proxy-nginx-1 nginx -s reload

# Migrate and setup API
echo "Running migrations..."
docker exec -it vumc-picture-api-api-1 /bin/sh -c "cd /var/www/laravel/vumc-picture-api && php artisan migrate --force"
echo "Optional account creation. Do not skip if you don't have an account yet"
docker exec -it vumc-picture-api-api-1 /bin/sh -c "cd /var/www/laravel/vumc-picture-api && php artisan user:create --confirm"
echo "Create passport client"
docker exec -it vumc-picture-api-api-1 /bin/sh -c "cd /var/www/laravel/vumc-picture-api && php artisan passport:install --force"

echo "Installation completed!"
