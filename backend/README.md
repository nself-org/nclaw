# nClaw Backend

Self-hosting guide for the nClaw backend. The backend is a standard nSelf stack with five Pro plugins that provide AI, conversation management, messaging, voice, and browser automation.

## Required plugins

All five plugins are Pro tier (requires a license key):

| Plugin | What it provides |
|--------|-----------------|
| `ai` | AI provider routing, model management, streaming |
| `claw` | Conversation management, memory, tool dispatch, personas |
| `mux` | Messaging pipeline, email integration, webhook routing |
| `voice` | Speech-to-text and text-to-speech |
| `browser` | Browser automation via Chrome DevTools Protocol (CDP) |

## Prerequisites

- **nSelf CLI** v1.0+ — [install](https://nself.org/install)
- **Pro license key** — format: `nself_pro_` + 32 characters. Get one at [nself.org/pricing](https://nself.org/pricing) (Pro tier, $1.99/mo or $19.99/yr)
- **Docker** and Docker Compose

## Setup

Run these commands in the `backend/` directory:

```bash
# 1. Initialize the nSelf project (creates .env and base config)
nself init

# 2. Register your Pro license key
nself license set nself_pro_YOURKEY

# 3. Install the required Pro plugins
nself plugin install ai claw mux voice browser

# 4. Generate docker-compose and service config
nself build

# 5. Start all services
nself start
```

That's the complete setup. nSelf handles PostgreSQL, Hasura, Auth, Storage, and Nginx automatically.

## Environment variables

After `nself init`, a `.env` file is created. Key variables:

| Variable | Description |
|----------|-------------|
| `NSELF_PLUGIN_LICENSE_KEY` | Your Pro license key (`nself_pro_...`) |
| `HASURA_GRAPHQL_ADMIN_SECRET` | Admin secret for Hasura console access |
| `AUTH_JWT_SECRET` | JWT signing secret for Auth |
| `POSTGRES_PASSWORD` | PostgreSQL superuser password |
| `NSELF_DOMAIN` | Your server's domain (or `localhost` for local dev) |
| `NSELF_ENV` | `development` or `production` |
| `AI_DEFAULT_PROVIDER` | Default AI provider (`openai`, `anthropic`, `ollama`, etc.) |
| `AI_OPENAI_API_KEY` | OpenAI API key (if using OpenAI) |
| `AI_ANTHROPIC_API_KEY` | Anthropic API key (if using Anthropic) |

Do not commit `.env` to version control.

## Verify the backend is running

```bash
# Check all services are up
nself status

# Check service health
nself health
```

Expected URLs once running:

| Service | URL |
|---------|-----|
| GraphQL API | `http://localhost:8080/v1/graphql` |
| GraphQL console (Hasura) | `http://localhost:8080/console` |
| Auth | `http://localhost:4000` |
| Storage | `http://localhost:9000` |
| nself-claw API | `http://localhost:8080/v1/plugins/claw` |
| nself-voice API | `http://localhost:8080/v1/plugins/voice` |
| nself-browser API | `http://localhost:8080/v1/plugins/browser` |

For a production deployment with a domain and TLS, set `NSELF_DOMAIN` before running `nself build`. nSelf will configure Nginx and SSL automatically.

## Connecting the client

In the nClaw Flutter app, set the backend URL when prompted on first launch:

- **Local dev:** `http://localhost:4000`
- **Remote server:** `https://your-domain.com` (requires `NSELF_DOMAIN` to be set and DNS configured)

The URL points to the Auth service. The app discovers all other endpoints automatically.

## Stopping and updating

```bash
# Stop all services
nself stop

# Pull latest images and restart
nself pull
nself start

# View logs
nself logs
nself logs claw    # logs for a specific plugin
```

## Troubleshooting

**`nself plugin install` fails with "license invalid"**
Verify your key is set correctly:
```bash
nself license show
```
The key must start with `nself_pro_`. Ensure you have a Pro tier subscription.

**Backend starts but the client cannot connect**
Check that all containers are healthy:
```bash
nself status
```
If any service shows `unhealthy`, check its logs:
```bash
nself logs hasura
nself logs auth
```

**"Plugin not found" error in the app**
The plugin may not have started correctly. Check:
```bash
nself logs claw
```
Try rebuilding:
```bash
nself stop
nself build
nself start
```

**Database migration errors**
Run migrations manually:
```bash
nself db migrate
```

**Port conflicts**
nSelf services use ports 5432 (PostgreSQL), 8080 (Hasura), 4000 (Auth), 9000 (Storage), and 80/443 (Nginx). Stop any local services using these ports before running `nself start`.
