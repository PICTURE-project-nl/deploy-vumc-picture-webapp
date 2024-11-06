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
fi

echo "Environment set to: $ENVIRONMENT"
if [ "$ENVIRONMENT" == "server" ]; then
    echo "Server URL: $SERVER_URL"
fi

# Generate .env file based on the selected environment
echo "Generating .env configuration for Nuxt project..."
# shellcheck disable=SC2164
# run generate_docker_compose.py in vumc-picture-api
cd "$base_dir/vumc-picture-webapp"
python3 generate_env.py

echo "Testing presence of required commands"


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
        docker compose --verbose -f "${compose_file}" --env-file "${env_file}" build # --no-cache
        docker compose --verbose -f "${compose_file}" --env-file "${env_file}" up -d
    else
        docker compose --verbose -f "${compose_file}" build # --no-cache
        docker compose --verbose -f "${compose_file}" up -d
    fi
}


# Get the absolute path of the script
SCRIPT_PATH=$(dirname "$(realpath "$0")")

echo "$SCRIPT_PATH"
# Hash the script path using sha256sum
HASHED_PATH=$(echo -n "$SCRIPT_PATH" | openssl dgst -sha256 | awk '{print $2}')
export NETWORK_PREFIX=${HASHED_PATH}
# shellcheck disable=SC2155
export GPU_AVAILABLE=$(command -v nvidia-smi > /dev/null 2>&1 && echo 1 || echo 0)

# remove docker-compose.generated.yml if it exists
rm -f "$base_dir/vumc-picture-api/docker-compose.generated.yml"

# shellcheck disable=SC2164
cd "$base_dir/vumc-picture-api"
python3 generate_docker_compose.py

# shellcheck disable=SC2164
cd "$base_dir/reverse-proxy"
python3 generate_docker_compose_and_nginx.py

# shellcheck disable=SC2164
cd "$base_dir/vumc-picture-filter"
python3 generate_docker_compose.py

# check if docker-compose.generated.yml was created
if [ ! -f "$base_dir/vumc-picture-api/docker-compose.generated.yml" ]; then
    echo "Error: docker-compose.generated.yml was not created. Please check generate_docker_compose.py."
    exit 1
fi

# check if dataset is present in filter
# shellcheck disable=SC2012
file_count=$(ls -1 "$base_dir/vumc-picture-filter/data" | wc -l)
echo "Dataset files found:" $file_count

if [ "$file_count" -lt 2 ]; then
  echo "Only test data set file found"
  echo "Please add dataset to $base_dir/vumc-picture-filter/data"
  echo "Before executing this script again"
  exit 1
fi

# stop running containers
echo "Stopping webapp service"
run_docker_compose_down "${HASHED_PATH}" "vumc-picture-webapp" "docker-compose.yml"
echo "Stopping filter service"
run_docker_compose_down "${HASHED_PATH}" "vumc-picture-filter" "docker-compose.generated.yml"
echo "Stopping API service"
run_docker_compose_down "${HASHED_PATH}" "vumc-picture-api" "docker-compose.generated.yml" "secrets.env"
echo "Stopping reverse proxy"
run_docker_compose_down "${HASHED_PATH}" "reverse-proxy" "docker-compose.generated.yml"

# Sleep
echo "Waiting 10 seconds before removing networks"
sleep 10

echo "Creating network ${HASHED_PATH}_proxy"
create_docker_network ${HASHED_PATH}_proxy
sleep 5

echo "Creating network ${HASHED_PATH}_filtering"
create_docker_network ${HASHED_PATH}_filtering

echo "Wait 10 seconds for networks to be up"
sleep 10

# shellcheck disable=SC2164
cd "$base_dir"
echo "Starting webapp service"
run_docker_compose_up "${HASHED_PATH}" "vumc-picture-webapp" "docker-compose.yml"
echo "Starting filter service"
run_docker_compose_up "${HASHED_PATH}" "vumc-picture-filter" "docker-compose.generated.yml"
echo "Starting API service"
run_docker_compose_up "${HASHED_PATH}" "vumc-picture-api" "docker-compose.generated.yml" "secrets.env"

echo "Wait 20 seconds for API to be up"
sleep 20

# shellcheck disable=SC2164
cd "$base_dir/vumc-picture-api"
echo "Aggregating dataset. This may take a few minutes depending on architecture"
docker exec -it vumc-picture-api-api-1 /bin/sh -c "cd /var/www/laravel/vumc-picture-api && php artisan dataset:update"
# shellcheck disable=SC2164
cd "$base_dir"

echo "Restarting reverse proxy"
run_docker_compose_down "${HASHED_PATH}" "reverse-proxy" "docker-compose.generated.yml"
run_docker_compose_up "${HASHED_PATH}" "reverse-proxy" "docker-compose.generated.yml"

sleep 20

# Certbot when ENVIRONMENT is 'server'
if [ "$ENVIRONMENT" == "server" ]; then
    # Strip protocol of SERVER_URL for Certbot
    # shellcheck disable=SC2001
    DOMAIN=$(echo "$SERVER_URL" | sed -e 's~http[s]*://~~g')
    echo "Running Certbot for SSL certificate generation for domain: $DOMAIN"

    docker exec reverse-proxy-nginx-1 certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m info@"$DOMAIN"

    sleep 20
fi

# Nginx herstarten om wijzigingen toe te passen
echo "Reloading Nginx to apply SSL configuration"
docker exec reverse-proxy-nginx-1 nginx -s reload

# shellcheck disable=SC2164
cd "$base_dir/vumc-picture-api"
echo "Optional account creation. Do not skip if you don't have an account yet"
docker exec -it vumc-picture-api-api-1 /bin/sh -c "cd /var/www/laravel/vumc-picture-api && php artisan user:create --confirm"
# shellcheck disable=SC2164
cd "$base_dir"

echo "Installation completed!"
