# pgAdmin Service

Web interface for PostgreSQL database management.

## Prerequisites

- Rancher Desktop with Kubernetes enabled
- Helm 3 installed
- kubectl configured
- **postgres** service must be deployed first

## Deploy

```powershell
# Package the Helm chart
cd chart
helm package .

# Install to Kubernetes (namespace must exist)
helm upgrade --install pgadmin pgadmin-0.1.0.tgz -n db-explorer

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=pgadmin -n db-explorer --timeout=120s
```

## Access

```powershell
# Port forward to localhost
kubectl port-forward -n db-explorer svc/pgadmin 8081:80

# Open in browser: http://localhost:8081
# Login:
#   Email: admin@local.com
#   Password: admin123
```

## Connect to PostgreSQL

After logging in:
1. Right-click **Servers** → **Register** → **Server**
2. **General** tab:
   - Name: `Database Change Explorer`
3. **Connection** tab:
   - Host: `postgres`
   - Port: `5432`
   - Database: `sourcedb`
   - Username: `dbuser`
   - Password: `dbpass123`
4. Click **Save**

## Test CDC Flow

Navigate to: **Servers** → **Database Change Explorer** → **Databases** → **sourcedb** → **Schemas** → **public** → **Tables** → **mara**

Right-click → **View/Edit Data** → **All Rows**

Try:
- **Insert**: Add a new row
- **Update**: Modify existing data
- **Delete**: Remove a row

Watch the changes appear in Tabix!

## Uninstall

```powershell
helm uninstall pgadmin -n db-explorer
```
