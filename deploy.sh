#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e
ssh -T git@github.com

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
USER_PUBLIC_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCWFvVPZM4Np1QmxNv+dOUaN/J83tOU/VkOno/zODbjin9o62zonn1uhBG1Jmfv8EaJBE"

# Script Vars
REPO_URL="git@github.com:Kai-Animator/next-self-host.git"
APP_DIR="/home/$NEW_USER/myApp" # Changed to new user's home directory

# Script Vars
REPO_URL="git@github.com:Kai-Animator/next-self-host.git"
APP_DIR="/home/$NEW_USER/ldj-website"

# Function to check if a user exists
user_exists() {
  id "$1" &>/dev/null
}

# Function to check if a group exists
group_exists() {
  getent group "$1" &>/dev/null
}

# Update package list and upgrade existing packages
echo "Updating package list and upgrading existing packages..."
apt update && apt upgrade -y

# 1.1 Create User and Password (User creation and setup)
echo "Creating new user and setting up SSH..."

if user_exists "$NEW_USER"; then
  echo "User '$NEW_USER' already exists. Skipping user creation."
else
  adduser "$NEW_USER" --disabled-password --gecos ""
  USER_PASSWORD=$(openssl rand -base64 12)
  echo "$NEW_USER:$USER_PASSWORD" | chpasswd
  echo "User '$NEW_USER' created with a random password."
fi

# Add user to sudo group if not already a member
if id -nG "$NEW_USER" | grep -qw "sudo"; then
  echo "User '$NEW_USER' is already in the sudo group."
else
  usermod -aG sudo "$NEW_USER"
  echo "User '$NEW_USER' added to the sudo group."
fi

# Install Docker if not installed
if ! command -v docker &>/dev/null; then
  echo "Docker not found. Installing Docker..."
  apt install -y apt-transport-https ca-certificates curl software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" -y
  apt update
  apt install -y docker-ce
  echo "Docker installed successfully."
else
  echo "Docker is already installed. Skipping Docker installation."
fi

# Create docker group if it doesn't exist
if group_exists "docker"; then
  echo "Group 'docker' already exists."
else
  groupadd docker
  echo "Group 'docker' created."
fi

# Add the user to the docker group if not already a member
if id -nG "$NEW_USER" | grep -qw "docker"; then
  echo "User '$NEW_USER' is already in the docker group."
else
  usermod -aG docker "$NEW_USER"
  echo "User '$NEW_USER' added to the docker group."
fi

# Install Docker Compose if not already installed
if ! command -v docker-compose &>/dev/null; then
  echo "Docker Compose not found. Installing Docker Compose..."
  curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
  echo "Docker Compose installed successfully."
else
  echo "Docker Compose is already installed. Skipping Docker Compose installation."
fi

# Ensure Docker starts on boot and start Docker service
echo "Enabling and starting Docker service..."
systemctl enable docker
systemctl start docker

# Setup passwordless sudo for Docker, Docker Compose, and systemctl
# Only if not already set
SUDOERS_FILE="/etc/sudoers.d/$NEW_USER"
if [ -f "$SUDOERS_FILE" ]; then
  echo "Passwordless sudo already configured for '$NEW_USER'."
else
  echo "$NEW_USER ALL=(ALL) NOPASSWD: /usr/bin/docker, /usr/local/bin/docker-compose, /usr/bin/systemctl" | tee "$SUDOERS_FILE"
  echo "Passwordless sudo configured for '$NEW_USER'."
fi

# Setup SSH directory and keys for the new user
echo "Setting up SSH for '$NEW_USER'..."
sudo -u "$NEW_USER" mkdir -p "/home/$NEW_USER/.ssh"
chmod 700 "/home/$NEW_USER/.ssh"

# **Add your own SSH public key to authorized_keys**
AUTHORIZED_KEYS="/home/$NEW_USER/.ssh/authorized_keys"

# Avoid duplicating your SSH key
grep -qxF "$USER_PUBLIC_KEY" "$AUTHORIZED_KEYS" || echo "$USER_PUBLIC_KEY" >>"$AUTHORIZED_KEYS"

# Generate SSH key pair for GitHub Actions if not already present
GITHUB_SSH_PRIVATE_KEY="/home/$NEW_USER/.ssh/id_rsa_github_actions"
GITHUB_SSH_PUBLIC_KEY="${GITHUB_SSH_PRIVATE_KEY}.pub"

if [ -f "$GITHUB_SSH_PRIVATE_KEY" ] && [ -f "$GITHUB_SSH_PUBLIC_KEY" ]; then
  echo "GitHub Actions SSH key pair already exists."
else
  echo "Generating SSH key pair for GitHub Actions..."
  sudo -u "$NEW_USER" ssh-keygen -t rsa -b 4096 -f "$GITHUB_SSH_PRIVATE_KEY" -N ""
  # Add GitHub Actions public key to authorized_keys without duplication
  grep -qxF "$(cat "$GITHUB_SSH_PUBLIC_KEY")" "$AUTHORIZED_KEYS" || cat "$GITHUB_SSH_PUBLIC_KEY" >>"$AUTHORIZED_KEYS"
  echo "GitHub Actions SSH key pair generated and public key added to authorized_keys."
fi

# Ensure correct permissions
chmod 600 "$AUTHORIZED_KEYS"
chown -R "$NEW_USER":"$NEW_USER" "/home/$NEW_USER/.ssh"

# **Disable SSH Password Authentication**
echo "Disabling SSH password authentication..."

SSHD_CONFIG="/etc/ssh/sshd_config"

# Backup the original sshd_config if not already backed up
if [ ! -f "${SSHD_CONFIG}.bak" ]; then
  cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"
  echo "Backup of sshd_config created at ${SSHD_CONFIG}.bak"
fi

# Update sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' "$SSHD_CONFIG"
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' "$SSHD_CONFIG"
sed -i 's/^#ChallengeResponseAuthentication yes/ChallengeResponseAuthentication no/' "$SSHD_CONFIG"
sed -i 's/^ChallengeResponseAuthentication yes/ChallengeResponseAuthentication no/' "$SSHD_CONFIG"

# Restart SSH service to apply changes
systemctl restart sshd
echo "SSH password authentication disabled."

# Add Swap Space if not already present
echo "Configuring swap space..."
if swapon --show | grep -q "/swapfile"; then
  echo "Swap file already exists. Skipping swap configuration."
else
  fallocate -l "$SWAP_SIZE" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
  echo "Swap space configured."
fi

# Generate SSH key pair for Repository Access
REPO_SSH_PRIVATE_KEY="/home/$NEW_USER/.ssh/id_ed25519_repo"
REPO_SSH_PUBLIC_KEY="${REPO_SSH_PRIVATE_KEY}.pub"

if [ -f "$REPO_SSH_PRIVATE_KEY" ] && [ -f "$REPO_SSH_PUBLIC_KEY" ]; then
  echo "Repository SSH key pair already exists."
else
  echo "Generating ed25519 SSH key pair for repository access..."
  sudo -u "$NEW_USER" ssh-keygen -t ed25519 -f "$REPO_SSH_PRIVATE_KEY" -N ""
  echo "Repository SSH key pair generated."
fi

# Output the Repository SSH Public Key for GitHub
echo ""
echo "============================================="
echo "### Repository SSH Public Key for GitHub ###"
echo "============================================="
echo "Please add the following public key to your GitHub repository's Deploy Keys (read access) or to your GitHub account SSH keys (with appropriate access):"
echo ""
# Ensure the key is displayed as a single line without line breaks
awk '{printf "%s", $0} END {print ""}' "$REPO_SSH_PUBLIC_KEY"
echo ""
echo "After adding the SSH key to GitHub, press Enter to continue..."
read -p "Press Enter to continue after adding the SSH key to GitHub: "

# Start the SSH agent and add the repository SSH key
echo "Starting SSH agent and adding repository SSH key..."
eval "$(ssh-agent -s)"
ssh-add "$REPO_SSH_PRIVATE_KEY"

sudo -u livredojogo bash -c "cat > /home/$NEW_USER/.ssh/config <<EOL
Host github.com
    HostName github.com
    User git
    IdentityFile /home/$NEW_USER/.ssh/id_ed25519_repo
EOL"

# Set correct permissions
chmod 600 /home/$NEW_USER/.ssh/config
chown $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh/config

# Clone the Git repository into the new user's home directory using the Repository SSH Key
echo "Cloning or updating the repository..."
if sudo -u "$NEW_USER" [ -d "$APP_DIR" ]; then
  echo "Directory '$APP_DIR' already exists. Pulling latest changes..."
  sudo -u "$NEW_USER" git -C "$APP_DIR" pull
else
  echo "Cloning repository from $REPO_URL..."
  sudo -u "$NEW_USER" git clone "$REPO_URL" "$APP_DIR"
fi

# Define Database URLs
DATABASE_URL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@db:5432/$POSTGRES_DB"
DEVELOPMENT_DATABASE_URL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@db-development:5433/$POSTGRES_DB_DEVELOPMENT"

# For external tools (like Drizzle Studio)
DATABASE_URL_EXTERNAL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:5432/$POSTGRES_DB"
DEVELOPMENT_DATABASE_URL_EXTERNAL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:5433/$POSTGRES_DB_DEVELOPMENT"

# Create or update the .env file inside the app directory
echo "Creating or updating the .env file..."
cat >"$APP_DIR/.env" <<EOL
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=$POSTGRES_DB
POSTGRES_DB_DEVELOPMENT=$POSTGRES_DB_DEVELOPMENT
DATABASE_URL=$DATABASE_URL
DATABASE_URL_EXTERNAL=$DATABASE_URL_EXTERNAL
DEVELOPMENT_DATABASE_URL=$DEVELOPMENT_DATABASE_URL
DEVELOPMENT_DATABASE_URL_EXTERNAL=$DEVELOPMENT_DATABASE_URL_EXTERNAL
EOL

# Ensure .env has correct ownership and permissions
chown "$NEW_USER":"$NEW_USER" "$APP_DIR/.env"
chmod 600 "$APP_DIR/.env"
echo ".env file created or updated."

# Install Caddy and Fail2Ban if not already installed
echo "Installing Caddy and Fail2Ban..."
if ! command -v caddy &>/dev/null; then
  echo "Installing dependencies for Caddy..."
  apt install -y debian-keyring debian-archive-keyring apt-transport-https ca-certificates curl software-properties-common

  echo "Downloading and adding Caddy GPG key..."
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

  echo "Adding Caddy repository..."
  echo "deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" | tee /etc/apt/sources.list.d/caddy-stable.list
  echo "deb-src [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" | tee -a /etc/apt/sources.list.d/caddy-stable.list

  echo "Updating package lists..."
  apt update

  echo "Installing Caddy and Fail2Ban..."
  apt install -y caddy fail2ban
  echo "Caddy and Fail2Ban installed successfully."
else
  echo "Caddy is already installed. Skipping Caddy installation."
  if ! dpkg -l | grep -qw "fail2ban"; then
    apt install -y fail2ban
    echo "Fail2Ban installed successfully."
  else
    echo "Fail2Ban is already installed. Skipping Fail2Ban installation."
  fi
fi

# Remove old Caddy config if it exists
if [ -f "/etc/caddy/Caddyfile" ]; then
  echo "Removing old Caddyfile..."
  rm -f /etc/caddy/Caddyfile
  echo "Old Caddyfile removed."
fi

# Create a new Caddyfile with SSL and reverse proxy configuration
echo "Creating a new Caddyfile..."
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
echo "Restarting Caddy to apply the new configuration..."
systemctl restart caddy
echo "Caddy restarted."

# Build and run the Docker containers from the app directory
echo "Building and running Docker containers..."
sudo -u "$NEW_USER" bash -c "
    cd '$APP_DIR' || exit 1
    docker-compose up --build -d
"

# Check if Docker Compose started correctly
echo "Verifying Docker containers are running..."
if docker-compose ps | grep -q "Up"; then
  echo "Docker containers are up and running."
else
  echo "Docker containers failed to start. Check logs with 'docker-compose logs'."
  exit 1
fi

# Output final message and necessary secrets
cat <<EOL
Deployment complete.

Your Next.js app and PostgreSQL database are now running.
- Next.js is available at https://$DOMAIN_NAME
- Testing environment is available at https://test.$DOMAIN_NAME
- PostgreSQL database is accessible from the web service.

The .env file has been created with the necessary environment variables.

---

**Important:**

To enable GitHub Actions to SSH into your server for automated deployments, you need to add the following SSH private key to your GitHub repository secrets as 'SSH_PRIVATE_KEY':

---
$(cat "/home/$NEW_USER/.ssh/id_rsa_github_actions")
---

**Note:**

- **Repository SSH Key:** The script has generated a separate SSH key pair for repository access (\`id_rsa_repo\` and \`id_rsa_repo.pub\`). **Please add the public key (\`id_rsa_repo.pub\`) to your GitHub repository's Deploy Keys** with **read access**.
  
  - **Adding as a Deploy Key:**
    1. Go to your GitHub repository.
    2. Navigate to **Settings** > **Deploy Keys**.
    3. Click **Add deploy key**.
    4. Provide a title (e.g., "Server Deploy Key").
    5. Paste the contents of \`/home/$NEW_USER/.ssh/id_rsa_repo.pub\`.
    6. Check **Allow write access** if your deployment requires pushing to the repository.
    7. Click **Add key**.

- **GitHub Actions SSH Key:** Ensure you've added the **GitHub Actions private key** to your GitHub repository secrets as \`SSH_PRIVATE_KEY\`.

- **Server SSH Key for Cloning:** After adding the **Repository Deploy Key**, the server should be able to clone the repository without issues.

You should also add the following to your GitHub repository secrets:
- \`SERVER_USER\`: \`$NEW_USER\`
- \`SERVER_HOST\`: \`[Your server's IP or hostname]\`
- \`APP_DIR\`: \ $APP_DIR
---
EOL
