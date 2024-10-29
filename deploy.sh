#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Env Vars
POSTGRES_USER="myuser"
POSTGRES_PASSWORD=$(openssl rand -base64 12)
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
APP_DIR="/home/$NEW_USER/myApp"

# Update package list and upgrade existing packages
apt update && apt upgrade -y

# 1.1 Create User and Password (User creation and setup)
echo "Creating new user and setting up SSH..."
adduser $NEW_USER --disabled-password --gecos ""
USER_PASSWORD=$(openssl rand -base64 12)
echo "$NEW_USER:$USER_PASSWORD" | chpasswd
usermod -aG sudo $NEW_USER
usermod -aG docker $NEW_USER

# Setup passwordless sudo for Docker and Docker Compose only
echo "$NEW_USER ALL=(ALL) NOPASSWD: /usr/bin/docker, /usr/local/bin/docker-compose, /usr/bin/systemctl" | tee /etc/sudoers.d/$NEW_USER

# Setup SSH directory and keys for the new user
mkdir -p /home/$NEW_USER/.ssh
chmod 700 /home/$NEW_USER/.ssh

# **Add your own SSH public key to authorized_keys**
echo "$USER_PUBLIC_KEY" | tee -a /home/$NEW_USER/.ssh/authorized_keys

# Generate SSH key pair for GitHub Actions
echo "Generating SSH key pair for GitHub Actions..."
su - $NEW_USER -c "ssh-keygen -t rsa -b 4096 -f /home/$NEW_USER/.ssh/id_rsa_github_actions -N ''"

# Add GitHub Actions public key to authorized_keys
cat /home/$NEW_USER/.ssh/id_rsa_github_actions.pub >>/home/$NEW_USER/.ssh/authorized_keys

# Ensure correct permissions
chmod 600 /home/$NEW_USER/.ssh/authorized_keys
chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh

# **Disable SSH Password Authentication**
echo "Disabling SSH password authentication..."
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^ChallengeResponseAuthentication yes/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config

# Restart SSH service to apply changes
systemctl restart sshd

# Add Swap Space
echo "Adding swap space..."
fallocate -l $SWAP_SIZE /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# Make swap permanent
echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab

# Install Docker
apt install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" -y
apt update
apt install -y docker-ce

# Install Docker Compose
rm -f /usr/local/bin/docker-compose
curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-$(uname -m)" -o /usr/local/bin/docker-compose

# Wait for the file to be fully downloaded before proceeding
if [ ! -f /usr/local/bin/docker-compose ]; then
  echo "Docker Compose download failed. Exiting."
  exit 1
fi

chmod +x /usr/local/bin/docker-compose

# Ensure Docker Compose is executable and in path
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Verify Docker Compose installation
docker-compose --version
if [ $? -ne 0 ]; then
  echo "Docker Compose installation failed. Exiting."
  exit 1
fi

# Ensure Docker starts on boot and start Docker service
systemctl enable docker
systemctl start docker

# Clone the Git repository into the new user's home directory
echo "Cloning or updating the repository..."
su - $NEW_USER -c "
if [ -d '$APP_DIR' ]; then
  echo 'Directory $APP_DIR already exists. Pulling latest changes...'
  cd '$APP_DIR' && git pull
else
  echo 'Cloning repository from $REPO_URL...'
  git clone $REPO_URL '$APP_DIR'
  cd '$APP_DIR' || exit 1
fi
"

# For Docker internal communication
DATABASE_URL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@db:5432/$POSTGRES_DB"
DEVELOPMENT_DATABASE_URL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@db-development:5433/$POSTGRES_DB_DEVELOPMENT"

# For external tools
DATABASE_URL_EXTERNAL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:5432/$POSTGRES_DB"
DEVELOPMENT_DATABASE_URL_EXTERNAL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:5433/$POSTGRES_DB_DEVELOPMENT"

# Create the .env file inside the app directory
su - $NEW_USER -c "
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
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | apt-key add -
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install -y caddy fail2ban

# Remove old Caddy config (if it exists)
rm -f /etc/caddy/Caddyfile

# Create a new Caddyfile with SSL and reverse proxy configuration
cat >/etc/caddy/Caddyfile <<EOL
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
systemctl restart caddy

# Build and run the Docker containers from the app directory
su - $NEW_USER -c "
cd '$APP_DIR' || exit 1
docker-compose up --build -d
"

# Check if Docker Compose started correctly
if ! docker-compose ps | grep "Up"; then
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
cat /home/$NEW_USER/.ssh/id_rsa_github_actions
echo "

---

**Note:** Keep this private key secure. Do not share it publicly.

You should also add the following to your GitHub repository secrets:
- SERVER_USER: $NEW_USER
- SERVER_HOST: [Your server's IP or hostname]
- APP_DIR: $APP_DIR

"
