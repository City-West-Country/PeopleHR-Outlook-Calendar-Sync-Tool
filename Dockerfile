# Use PowerShell Core base image
FROM mcr.microsoft.com/powershell:7.4-ubuntu-22.04

# Set working directory
WORKDIR /app

# Copy application files
COPY src/ /app/src/
COPY run.ps1 /app/

# Create logs directory
RUN mkdir -p /app/logs

# Set environment variables
ENV PSModulePath="/usr/local/share/powershell/Modules:${PSModulePath}"

# Run the sync tool
# Note: You must mount settings.json as a volume
# Example: docker run -v /path/to/settings.json:/app/settings.json peoplehr-sync

ENTRYPOINT ["pwsh", "-File", "/app/run.ps1"]
