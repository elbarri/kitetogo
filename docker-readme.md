# PostgreSQL with PostGIS Docker Setup

This project uses PostgreSQL with PostGIS extensions running in Docker for development.

## Quick Start

1. **Start the database:**
   ```bash
   docker compose up -d
   ```

2. **Check status:**
   ```bash
   docker compose ps
   ```

3. **Stop the database:**
   ```bash
   docker compose down
   ```

4. **View logs:**
   ```bash
   docker compose logs postgres
   ```

## Database Access

**Connect via psql:**
```bash
PGPASSWORD=postgres psql -h localhost -U postgres -d kite4rent_dev
```

**Run Elixir migrations:**
```bash
mix ecto.reset  # Recreate and migrate
mix ecto.migrate  # Just migrate
```

## Configuration

- **Databases**: `kite4rent_dev` and `kite4rent_test`
- **User**: `postgres`
- **Password**: `postgres`
- **Port**: `5432`
- **PostGIS Version**: 3.2

## PostGIS Verification

Test PostGIS is working:
```bash
PGPASSWORD=postgres psql -h localhost -U postgres -d kite4rent_dev -c "SELECT PostGIS_Version();"
```

## Data Persistence

Database data is persisted in Docker volume `kite4rent_postgres_data`. To completely reset:
```bash
docker compose down -v  # Removes volumes too
``` 