# /bin/bash.sh
cd ..
cd vumc-picture-webapp
docker compose down
cd ../vumc-picture-filter
docker compose -f docker-compose.generated.yml down
cd ../vumc-picture-api
docker compose -f docker-compose.yml down
docker rm -f vumc-picture-api-flower-1
docker rm -f vumc-picture-api-flower_seg-1
cd ../reverse-proxy
docker compose down
cd ../deploy-vumc-picture-webapp
