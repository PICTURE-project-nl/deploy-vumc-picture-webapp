# deploy-vumc-picture-webapp

<!-- TOC -->
* [deploy-vumc-picture-webapp](#deploy-vumc-picture-webapp)
  * [Overview](#overview)
    * [Project Components](#project-components)
      * [vumc-picture-filter](#vumc-picture-filter)
      * [vumc-picture-webapp](#vumc-picture-webapp)
      * [vumc-picture-api](#vumc-picture-api)
      * [reverse-proxy](#reverse-proxy)
    * [Setup and Run the Project](#setup-and-run-the-project)
    * [Hardware and Operating System Requirements](#hardware-and-operating-system-requirements)
  * [License](#license)
  * [Disclaimer](#disclaimer)
<!-- TOC -->

## Overview

The PICTURE Project is designed to facilitate the processing, analysis, and visualization of medical imaging data for improved tumor resection planning and patient outcomes. The project consists of the following main components:

- **vumc-picture-filter**: Handles image filtering and segmentation based on clinical variables. Provides HTTP POST endpoints for filtering tasks and includes caching mechanisms.
- **vumc-picture-webapp**: The frontend interface built with Vue.js and Nuxt.js, enabling users to interact with the system, upload data, and visualize results.
- **vumc-picture-api**: Backend API built with Node.js, providing endpoints for image filtering and querying filter options. It handles the core data processing and server-side logic.
- **reverse-proxy**: Manages routing requests to appropriate services, built with Docker to ensure seamless communication between components.
- **Dependencies Information**: Separate LICENSES.md details licenses for all third-party libraries and dependencies used within the project.

### Project Components

#### vumc-picture-filter
- **Function**: Filters and segments medical image data based on clinical variables.
- **Technology**: Python, Flask, Celery, Redis.
- **Usage**: Accepts base64 encoded MHA volumes and returns filtered probability maps via HTTP POST requests.

#### vumc-picture-webapp
- **Function**: User interface for interacting with the system.
- **Technology**: Vue.js, Nuxt.js, Webpack.
- **Usage**: Enables data upload, visualization of results, and interaction with various features.

#### vumc-picture-api
- **Function**: Backend API for processing data.
- **Technology**: Node.js, Composer.
- **Usage**: Provides endpoints for filtering images, querying filter options, and data management.

#### reverse-proxy
- **Function**: Routes requests to appropriate services.
- **Technology**: Docker.
- **Usage**: Ensures effective communication between frontend, backend, and filtering services.

### Setup and Run the Project

Follow these steps to set up and run the project:

1. **Set up SSH for GitHub**:
    - Ensure SSH access to all picture-ac repositories.
    - Open a terminal on mac or Git bash on windows.
    - Example commands to add an SSH key:
      ```bash
      ssh-keygen -f ~/.ssh/github
      eval $(ssh-agent -s)
      ssh-add ~/.ssh/github
      cat ~/.ssh/github.pub
      ```
    - Add the SSH key to your GitHub account: <https://github.com/settings/keys>. **Do not change usage type and expiration date**
    - Make sure you check in which environment the SSH key was added and proceed with that environment
    - Test the connection to confirm SSH is set up correctly:
      ```bash
      ssh -T git@github.com
      ```
      If the connection is successful, you should see a message like:
      ```
      Hi <your-username>! You've successfully authenticated, but GitHub does not provide shell access.
      ```

2. **Create and navigate to your empty project folder**:
    - On Mac/Linux: `mkdir picture-project && cd picture-project`
    - On Windows: `mkdir picture-project;cd picture-project`

3. **Install Git**:
    - On Linux: `sudo apt-get install git`
    - On macOS: `brew install git`
    - Ensure Git is installed before proceeding.

4. **Clone this repository**:
    - Use the following command: `git clone git@github.com:PICTURE-project-nl/deploy-vumc-picture-webapp.git`

5. **Clone other repositories**:
    - Command: `./clone.sh` to clone necessary repositories and move files. _Note: make sure that the VPN connection has been made before building vumc-picture-webapp_

6. **Install Docker and Nvidia-Docker**:
    - If needed, install by using the following commands:
      ```bash
      chmod +x install_docker.sh
      ./install_docker.sh
      ```

7. **(Optional) Update domain names**:
    - Replace 'pictureproject.nl' with 'segment-picture.nl' or 'localhost' in relevant files if necessary.

8. **(Optional) Set up SMTP Mailtrap**:
    - If you would like to receive reminders that the tool provides, configure in `vumc-picture-api/laravel/src/vumc-picture-api/.env`.

9. **Build and deploy all services**:
    - To build and deploy all services, use the following command: `./restart.sh`. _Note:  Increase the disk image size if necessary for (faster) container building_

10. **Using the tool**:
    - You can use the tool by typing `localhost` in your preferred browser.

11. **Making an user**:

Now create a user so that you can log in to the PICTURE tool, by following these steps:

_If you don't have Docker installed and you would like to use the terminal:_
- Open a terminal
- Navigate to your repository
- Run the following command to get inside of the vumc-picture-api-api-1 container: docker exec -it <container ID>. You can know the container ID by running the command: docker ps.

_If you have Docker installed:_
- Open Docker
- Navigate to vumc-picture-api-api-1
- Navigate to the Exec tab

Proceed with the following steps:
- Navigate to vumc-picture-api with cd var/www/laravel/vumc-picture-api
- Now run the command: php artisan tinker
- Now you will create a user with the following commands:
    - $user = new App\User;
    - $user->institute = 'enter the name of your institute here';
    - $user->name = 'enter your name here';
    - $user->email = 'enter your email address here';
    - $user->email_verified_at = now();
    - $user->password = bcrypt('enter your password here ');
    - $user->super_user = true;
    - $user->active = true;
    - $user->activation_token = 'token1';
    - $user->save();

OR 

- Sign up and log in with your credentials on your browser.

12. Troubleshooting
- If you have trouble signing in/up, try removing :8000 from your browser link if it isn't done already.
- For more questions you can always contact the PICTURE team. 

### Hardware and Operating System Requirements

- **Tested on**: Ubuntu, macOS 14.4.1 and Microsoft Windows.
- **GPU Support**: Requires a GPU with CUDA support for running the filter (tested on NVIDIA).

## License

This project is licensed under the GNU Affero General Public License v3.0 (AGPL-3.0). See the [LICENSE](./LICENSE.md) file for details. For information regarding third-party licenses, see [LICENSES](./LICENSES.md).

## Disclaimer

The Project PICTURE software is provided "as is", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement. In no event shall the authors, Active Collective, or the research group be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
