# Database Migrations

This project uses [Sequel](https://sequel.jeremyevans.net/) for database migrations.

## Migration Naming Convention

Migrations use **timestamp-based filenames** to avoid conflicts and maintain chronological order:

```
YYYYMMDDHHMMSS_description.rb
```

Example: `20250116120000_create_your_migration.rb`

## Creating New Migrations

### Unix/macOS/Linux

```bash
# Create a new migration with current timestamp
touch "db/migrations/$(date +%Y%m%d%H%M%S)_your_migration_name.rb"

# Example
touch "db/migrations/$(date +%Y%m%d%H%M%S)_add_status_to_notifications.rb"
```

### Windows (PowerShell)

```powershell
# Create a new migration with current timestamp
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
New-Item -Path "db/migrations/${timestamp}_your_migration_name.rb" -ItemType File

# Example
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
New-Item -Path "db/migrations/${timestamp}_add_status_to_notifications.rb" -ItemType File
```