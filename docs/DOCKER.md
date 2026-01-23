# Docker Deployment Guide

This guide explains how to run the PeopleHR-Outlook Calendar Sync Tool in a Docker container.

## Prerequisites

- Docker installed (https://docs.docker.com/get-docker/)
- Configured `settings.json` file

## Build the Docker Image

From the repository root:

```bash
docker build -t peoplehr-sync:latest .
```

## Run the Container

### Basic Run

```bash
docker run -v /path/to/your/settings.json:/app/settings.json peoplehr-sync:latest
```

### Run with Log Persistence

Mount a local directory for logs:

```bash
docker run \
  -v /path/to/your/settings.json:/app/settings.json \
  -v /path/to/logs:/app/logs \
  peoplehr-sync:latest
```

### Run in WhatIf Mode

```bash
docker run \
  -v /path/to/your/settings.json:/app/settings.json \
  peoplehr-sync:latest \
  -WhatIf
```

## Docker Compose

Create a `docker-compose.yml`:

```yaml
version: '3.8'

services:
  peoplehr-sync:
    build: .
    image: peoplehr-sync:latest
    volumes:
      - ./settings.json:/app/settings.json:ro
      - ./logs:/app/logs
    restart: "no"
```

Run with:

```bash
docker-compose up
```

## Scheduled Runs with Docker

### Using Cron (Linux)

Add to crontab:

```bash
# Run every day at 6 AM
0 6 * * * docker run -v /path/to/settings.json:/app/settings.json -v /path/to/logs:/app/logs peoplehr-sync:latest
```

### Using Windows Task Scheduler

Create a task that runs:

```powershell
docker run -v C:\path\to\settings.json:/app/settings.json -v C:\path\to\logs:/app/logs peoplehr-sync:latest
```

## Kubernetes Deployment

### CronJob Example

Create `peoplehr-sync-cronjob.yaml`:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: peoplehr-sync
spec:
  schedule: "0 6 * * *"  # Every day at 6 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: sync
            image: peoplehr-sync:latest
            volumeMounts:
            - name: config
              mountPath: /app/settings.json
              subPath: settings.json
              readOnly: true
            - name: logs
              mountPath: /app/logs
          volumes:
          - name: config
            secret:
              secretName: peoplehr-sync-config
          - name: logs
            persistentVolumeClaim:
              claimName: peoplehr-sync-logs
          restartPolicy: OnFailure
```

Create the secret:

```bash
kubectl create secret generic peoplehr-sync-config --from-file=settings.json
```

Apply the CronJob:

```bash
kubectl apply -f peoplehr-sync-cronjob.yaml
```

## Azure Container Instances

### Using Azure CLI

```bash
# Create resource group
az group create --name peoplehr-sync-rg --location eastus

# Create container instance
az container create \
  --resource-group peoplehr-sync-rg \
  --name peoplehr-sync \
  --image peoplehr-sync:latest \
  --cpu 1 --memory 1 \
  --restart-policy Never \
  --environment-variables \
    'TenantId'='your-tenant-id' \
    'ClientId'='your-client-id' \
  --secure-environment-variables \
    'ClientSecret'='your-client-secret' \
    'PeopleHrApiKey'='your-api-key'
```

Note: For production, use Azure Key Vault instead of environment variables.

## Security Considerations

### Protect settings.json

When using containers:

1. **Never bake settings.json into the image**
   ```dockerfile
   # ❌ DON'T DO THIS
   COPY settings.json /app/
   ```

2. **Use volume mounts**
   ```bash
   # ✅ DO THIS
   docker run -v /path/to/settings.json:/app/settings.json:ro peoplehr-sync
   ```

3. **Use read-only mounts** (`:ro` flag) when possible

### Use Secrets Management

#### Docker Secrets (Swarm)

```bash
echo "your-secret" | docker secret create client_secret -
```

Update your script to read from `/run/secrets/client_secret`

#### Kubernetes Secrets

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: peoplehr-sync-secrets
type: Opaque
stringData:
  tenantId: "your-tenant-id"
  clientId: "your-client-id"
  clientSecret: "your-client-secret"
  peopleHrApiKey: "your-api-key"
```

#### Azure Key Vault

Use Azure Key Vault with Container Instances:

```bash
az container create \
  --resource-group peoplehr-sync-rg \
  --name peoplehr-sync \
  --image peoplehr-sync:latest \
  --assign-identity --scope /subscriptions/{subscriptionId} \
  --environment-variables \
    'AZURE_KEYVAULT_URL'='https://your-vault.vault.azure.net/'
```

## Monitoring and Logging

### View Container Logs

```bash
# Docker
docker logs <container-id>

# Docker Compose
docker-compose logs

# Kubernetes
kubectl logs job/peoplehr-sync-<timestamp>
```

### Export Logs

```bash
# Docker
docker logs <container-id> > sync-output.log

# Kubernetes
kubectl logs job/peoplehr-sync-<timestamp> > sync-output.log
```

## Troubleshooting

### Container Exits Immediately

Check logs:
```bash
docker logs <container-id>
```

Common causes:
- settings.json not mounted correctly
- Invalid credentials
- Network connectivity issues

### Permission Denied Errors

Ensure volume mounts have correct permissions:
```bash
chmod 644 settings.json
```

### Out of Memory

Increase memory allocation:
```bash
docker run --memory=2g -v /path/to/settings.json:/app/settings.json peoplehr-sync
```

## Best Practices

1. **Use specific image tags** instead of `:latest`
2. **Implement health checks** for long-running containers
3. **Set resource limits** to prevent resource exhaustion
4. **Use read-only root filesystem** when possible
5. **Run as non-root user** (add to Dockerfile if needed)
6. **Scan images for vulnerabilities** regularly

---

**Last Updated**: January 2026
