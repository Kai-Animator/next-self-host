#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Env Vars
POSTGRES_USER="myuser"
POSTGRES_PASSWORD=$(openssl rand -base64 12) # Generate a random 12-character password
POSTGRES_DB="mydatabase"
POSTGRES_DB_DEVELOPMENT="mydevdatabase"
DOMAIN_NAME="nextselfhost.dev" # Replace with your own
EMAIL="your-email@example.com" # Replace with your own
NEW_USER="userName"            # Replace with your desired username
SWAP_SIZE="1G"                 # Swap size of 1GB

# **Add your own public SSH key here**
USER_PUBLIC_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC..." # Replace with your actual public key

# Script Vars
REPO_URL="git@github.com:Kai-Animator/next-self-host.git"
APP_DIR="/home/$NEW_USER/myApp" # Changed to new user's home directory

# Update package list and upgrade existing packages
sudo apt update && sudo apt upgrade -y

# 1.1 Create User and Password (User creation and setup)
echo "Creating new user and setting up SSH..."
sudo adduser $NEW_USER --disabled-password --gecos ""
USER_PASSWORD=$(openssl rand -base64 12)
echo "$NEW_USER:$USER_PASSWORD" | sudo chpasswd
sudo usermod -aG sudo $NEW_USER
sudo usermod -aG docker $NEW_USER

# Setup passwordless sudo for Docker and Docker Compose only
echo "$NEW_USER ALL=(ALL) NOPASSWD: /usr/bin/docker, /usr/local/bin/docker-compose, /usr/bin/systemctl" | sudo tee /etc/sudoers.d/$NEW_USER

# Setup SSH directory and keys for the new user
sudo mkdir -p /home/$NEW_USER/.ssh
sudo chmod 700 /home/$NEW_USER/.ssh

# **Add your own SSH public key to authorized_keys**
echo "$USER_PUBLIC_KEY" | sudo tee -a /home/$NEW_USER/.ssh/authorized_keys

# Generate SSH key pair for GitHub Actions
echo "Generating SSH key pair for GitHub Actions..."
sudo -u $NEW_USER ssh-keygen -t rsa -b 4096 -f /home/$NEW_USER/.ssh/id_rsa_github_actions -N ""

# Ensure correct permissions
sudo chmod 600 /home/$NEW_USER/.ssh/authorized_keys
sudo chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh

# Add Swap Space
echo "Adding swap space..."
sudo fallocate -l $SWAP_SIZE /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make swap permanent
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Install Docker
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" -y
sudo apt update
sudo apt install -y docker-ce

# Install Docker Compose
sudo rm -f /usr/local/bin/docker-compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-$(uname -m)" -o /usr/local/bin/docker-compose

# Wait for the file to be fully downloaded before proceeding
if [ ! -f /usr/local/bin/docker-compose ]; then
  echo "Docker Compose download failed. Exiting."
  exit 1
fi

sudo chmod +x /usr/local/bin/docker-compose

# Ensure Docker Compose is executable and in path
sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Verify Docker Compose installation
docker-compose --version
if [ $? -ne 0 ]; then
  echo "Docker Compose installation failed. Exiting."
  exit 1
fi

# Ensure Docker starts on boot and start Docker service
sudo systemctl enable docker
sudo systemctl start docker

# Clone the Git repository into the new user's home directory
echo "Cloning or updating the repository..."
sudo -u $NEW_USER bash -c "
if [ -d '$APP_DIR' ]; then
  echo 'Directory $APP_DIR already exists. Pulling latest changes...'
  cd '$APP_DIR' && git pull
else
  echo 'Cloning repository from $REPO_URL...'
  git clone $REPO_URL '$APP_DIR'
  cd '$APP_DIR' || exit 1
fi
"

# For Docker internal communication ("db" is the name of Postgres container)
DATABASE_URL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@db:5432/$POSTGRES_DB"
DEVELOPMENT_DATABASE_URL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@db-development:5433/$POSTGRES_DB_DEVELOPMENT"

# For external tools (like Drizzle Studio)
DATABASE_URL_EXTERNAL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:5432/$POSTGRES_DB"
DEVELOPMENT_DATABASE_URL_EXTERNAL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:5433/$POSTGRES_DB_DEVELOPMENT"

# Create the .env file inside the app directory
sudo -u $NEW_USER bash -c "
echo 'POSTGRES_USER=$POSTGRES_USER' > '$APP_DIR/.env'
echo 'POSTGRES_PASSWORD=$POSTGRES_PASSWORD' >> '$APP_DIR/.env'
echo 'POSTGRES_DB=$POSTGRES_DB' >> '$APP_DIR/.env'
echo 'POSTGRES_DB_DEVELOPMENT=$POSTGRES_DB_DEVELOPMENT' >> '$APP_DIR/.env'
echo 'DATABASE_URL=$DATABASE_URL' >> '$APP_DIR/.env'
echo 'DATABASE_URL_EXTERNAL=$DATABASE_URL_EXTERNAL' >> '$APP_DIR/.env'
echo 'DEVELOPMENT_DATABASE_URL=$DEVELOPMENT_DATABASE_URL' >> '$APP_DIR/.env'
echo 'DEVELOPMENT_DATABASE_URL_EXTERNAL=$DEVELOPMENT_DATABASE_URL_EXTERNAL' >> '$APP_DIR/.env'
"

# Install Caddy and Fail2Ban
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo apt-key add -
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install -y caddy fail2ban

# Remove old Caddy config (if it exists)
sudo rm -f /etc/caddy/Caddyfile

# Create a new Caddyfile with SSL and reverse proxy configuration
sudo tee /etc/caddy/Caddyfile >/dev/null <<EOL
$DOMAIN_NAME, www.$DOMAIN_NAME {
    reverse_proxy localhost:3000
    tls $EMAIL
}

http://$DOMAIN_NAME, http://www.$DOMAIN_NAME {
    redir https://$DOMAIN_NAME
}

test.$DOMAIN_NAME {
    reverse_proxy localhost:3001
    tls $EMAIL
}

http://test.$DOMAIN_NAME {
    redir https://test.$DOMAIN_NAME
}
EOL

# Restart Caddy to apply the new configuration
sudo systemctl restart caddy

# Build and run the Docker containers from the app directory
sudo -u $NEW_USER bash -c "
cd '$APP_DIR' || exit 1
sudo docker-compose up --build -d
"

# Check if Docker Compose started correctly
if ! sudo docker-compose ps | grep "Up"; then
  echo "Docker containers failed to start. Check logs with 'docker-compose logs'."
  exit 1
fi

# Output final message and necessary secrets
echo "Deployment complete.

Your Next.js app and PostgreSQL database are now running.
- Next.js is available at https://$DOMAIN_NAME
- Testing environment is available at https://test.$DOMAIN_NAME
- PostgreSQL database is accessible from the web service.

The .env file has been created with the necessary environment variables.

---

**Important:**

To enable GitHub Actions to SSH into your server for automated deployments, you need to add the following SSH private key to your GitHub repository secrets as 'SSH_PRIVATE_KEY':

---

"
sudo cat /home/$NEW_USER/.ssh/id_rsa_github_actions
echo "

---

**Note:** Keep this private key secure. Do not share it publicly.

You should also add the following to your GitHub repository secrets:
- SERVER_USER: $NEW_USER
- SERVER_HOST: [Your server's IP or hostname]
- APP_DIR: $APP_DIR

"
