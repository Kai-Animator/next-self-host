# Next.js Self Hosting Example

This repo shows how to deploy a Next.js app and a PostgreSQL database on a Ubuntu Linux server using Docker and Nginx. It showcases using several features of Next.js like caching, ISR, environment variables, and more.

[**🗄️ Original Project**](https://github.com/leerob/next-self-host/tree/main)

## Prerequisites

1. Purchase a domain name
2. Purchase a Linux Ubuntu server (e.g. [droplet](https://www.digitalocean.com/products/droplets))
3. Create an `A` DNS record pointing to your server IPv4 address

## Quickstart

1. **SSH into your server**:

   ```bash
   ssh root@your_server_ip
   ```

2. **Download the deployment script**:

   ```bash
   curl -o ~/deploy.sh https://raw.githubusercontent.com/Kai-Animator/next-self-host/refs/heads/main/deploy.sh
   ```

   You can then modify the email and domain name variables inside of the script to use your own.

3. **Run the deployment script**:

   ```bash
   chmod +x ~/deploy.sh
   ./deploy.sh
   ```

## Deploy Script

Both the Next.js app and PostgreSQL database will be up and running in Docker containers. To set up your database, you could install `npm` inside your Postgres container and use the Drizzle scripts, or you can use `psql`:

```bash
docker exec -it myapp-db-1 sh
apk add --no-cache postgresql-client
psql -U myuser -d mydatabase -c '
CREATE TABLE IF NOT EXISTS "todos" (
  "id" serial PRIMARY KEY NOT NULL,
  "content" varchar(255) NOT NULL,
  "completed" boolean DEFAULT false,
  "created_at" timestamp DEFAULT now()
);'
```

## Running Locally

If you want to run this setup locally using Docker, you can follow these steps:

```bash
docker-compose -f docker-compose.development.yml up -d
```

This will start both services and make your Next.js app available at `http://localhost:3001` with the PostgreSQL database running in the background. We also create a network so that our two containers can communicate with each other.

If you want to view the contents of the local database, you can use Drizzle Studio:

```bash
bun run db:studio
```

## Helpful Commands

- `docker-compose ps` – check status of Docker containers
- `docker-compose logs web` – view Next.js output logs
- `docker-compose logs cron` – view cron logs
- `docker-compose down` - shut down the Docker containers
- `docker-compose up -d` - start containers in the background
- `sudo systemctl restart nginx` - restart nginx
- `docker exec -it myapp-web-1 sh` - enter Next.js Docker container
- `docker exec -it myapp-db-1 psql -U myuser -d mydatabase` - enter Postgres db

## Personal Changes

Replace Nginx for Caddy, added fail2ban
Added Github Actions integrations
Added zod, trpc and postcss, also updated next
