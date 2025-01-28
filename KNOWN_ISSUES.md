### Issue: 401 Unauthorized Error when Pulling NVIDIA PyTorch Docker Container

#### Problem
Occasionally, we received a 401 unauthorized error when pulling the Docker asset `nvcr.io/nvidia/pytorch:21.12-py3`, indicating that authentication is required.

#### Solution
To resolve this:

1. **Create an NVIDIA NGC Account**:
   - Visit [NVIDIA NGC](https://ngc.nvidia.com/) and log in.

2. **Generate an API Key**:
   - Go to your profile, select "API Key", and generate a new key.

3. **Authenticate with Docker**:
   - Run:
     ```bash
     docker login nvcr.io
     ```
   - Use `$oauthtoken` as the username and your NGC API Key as the password.

4. **Optional: Persistent Login**:
   - Add the following to `~/.docker/config.json`:
     ```json
     {
       "auths": {
         "nvcr.io": {
           "auth": "BASE64_ENCODED_CREDENTIALS"
         }
       }
     }
     ```
   - Generate the base64 encoded credentials with:
     ```bash
     echo -n '$oauthtoken:YOUR_NGC_API_KEY' | base64
     ```

Following these steps ensures you can consistently pull the NVIDIA PyTorch Docker container without authentication errors.


### Issue: Apache Occupying Port 80 Instead of Reverse-Proxy Nginx

#### Problem
Sometimes, Apache is running on port 80, preventing the reverse-proxy Nginx container from binding to the port.

#### Solution
To ensure Nginx runs on port 80:

1. **Check Which Service is Active on Port 80**:
   - Run:
     ```bash
     sudo netstat -tuln | grep :80
     ```
     This will display the service currently using port 80.

2. **Stop Apache Service**:
   - Run:
     ```bash
     sudo systemctl stop apache2
     ```
     This stops Apache from occupying port 80.

3. **Start the Nginx Container**:
   - Run:
     ```bash
     docker start reverse-proxy-nginx-1
     ```
     This starts the Nginx container, allowing it to bind to port 80.
