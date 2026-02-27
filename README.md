# Ramaseshan's Toptal interview task

[![infracost](https://img.shields.io/endpoint?url=https://dashboard.api.infracost.io/shields/json/8bcbc2f5-d603-42fc-bae7-a56856530d4e/repos/798b8a3f-e18d-4afc-80db-53a1f4703868/branch/62aba94f-67d8-49c9-befd-6c7d4d4b844e)](https://dashboard.infracost.io/org/rams-personal/repos/798b8a3f-e18d-4afc-80db-53a1f4703868?tab=branches)


## URL

URL for testing: https://node--prod--cdn--endpoint-adg9b9c4dsezacac.z02.azurefd.net/  (Sited rendered via a WAF gated edge located CDN, via Azure Frontdoor and Azure Application Gateway)

Version specific endpoint: https://node--prod--cdn--endpoint-adg9b9c4dsezacac.z02.azurefd.net/version/

CI/CD Pipeline git mirror: (https://github.com/voidspacexyz/ToptalTakeHome/actions/runs/22476979552)[https://github.com/voidspacexyz/ToptalTakeHome/]

## Requirements for Installation 

1. [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?view=azure-cli-latest&pivots=apt)
2. [OpenTofu or Terraform](https://opentofu.org/)
3. (kubectl)[https://kubernetes.io/docs/tasks/tools/] and (kubens)[https://webinstall.dev/kubens/]
4. (Docker)[https://docs.docker.com]
5. Azure Subscription and a resource group (A copy of subscription ID and Resource Group Name)

Note: I had access to an azure cloud at the point of preparation, but similar setup can be implemented in AWS or GCP or smaller cloud providers like DigitalOcean or Linode etc without compromising the architecture


## Setting up the cloud

This setup assumes you have a Azure Cloud account and a subscription created.

1. Login to azure cloud using `az login --use-device-code`
2. Create your resource group (in this case its called RamToptal)
3. Create the initial storage for OpenTofu using the following the Azure 
   1. ``` az storage account create \
  -n nodeprodtfstate \
  -g RamToptal \
  -l centralindia \
  --sku Standard_LRS \
  --kind StorageV2

az storage container create \
  -n tfstate \
  --account-name nodeprodtfstate```

4. Run `tofu init` to initialise the IaC
5. Validate the config `tofu validate` and ensure there are not syntax level errors
6. Copy the secrets file `cp secrets.tfvars.sample secrets.tfvars` and update the required values
7. Plan the IaC `tofu plan -var-file="secrets.tfvars"` 
8. Implement the plan `tofu apply -var-file="secrets.tfvars"`


## ACR Credentials

Due to my account limittaions, I could only deploy a basic ACR registry, so the token for push or pull to the registy is done manually. But in an ideal corportate environment, we can deploy a premium registry, and that allows for push and pull tokens to be controlled via Terraform itself. 

Steps to create tokens manually.

1. Go to the ACR pane
2. Click on Repository Permissions -> Tokens
3. Enter the token name as ACRPushToken01 (for Push) or ACRPullToken01 (for pull ) tokens
4. In the scope map for push, select _repositories_push and _repositories_push_metadata_write
5. In the scope map for pull, select select _repositories_pull and _repositories_pull_metadata_read
6. Click Create and copy the tokens for CI/CD or local pipelines

## App layer

The `dockerfile.api` and `Dockerfile.web` constains the container setup and run instructions and is annotated with details. 

### Local App Testing

The app uses docker-compose for local app testing. Refer `docker-compose.yml` for local docker-compose.

**Requirements**

- docker and docker-compose installed
- Ports required: 8080 (for the web), 3000 (api), 5432(postgres), 679(redis)

**How to run**
`docker compose up --build` will build and run the app. 

- The app uses postgresql 16, so as to ensure wider compactability across all major cloud providers and its platform services.
- The local version exposes the ports and services so as to enable better debug.

### Production App building

`docker-compose.prod.yml` contains the code for production docker-compose. 

**Requirements**
- ACR push token from the devops team. This is current manual limitation due to the limitation of a basic ACR tier. Once we move to production tier, we can generate tokens automatically for local or CI/CD integration
- `docker login nodeprodacr.azurecr.io` and use the credentials from above.

**Steps to build and push to ACR**

- Build the image: `TAG=v1.0.0 docker compose -f docker-compose.prod.yml build`
- Push the image: `TAG=v1.0.0 docker compose -f docker-compose.prod.yml push`

Note: TAG is product version.


**To verify the images exist**

- Login to ACR: `az acr login --name nodeprodacr`
- List of all repositories: `az acr repository list --name nodeprodacr --output table`
- To check API specific tag: `az acr repository show-tags --name nodeprodacr --repository node-api --output table`
- To check web specific tags: `az acr repository show-tags --name nodeprodacr --repository node-web --output table`


## Setting up Secrets

General Syntax: `az keyvault secret set --vault-name node-prod-kv --name <key> --value "<value>"` 

Mandatory Keys are follows:

| Key | Description|
| ---- | ---- |
| app-ro-password | The App's RO user password, automatically updated by OpenTofu. This is currently declared but unused, but ideal usage would be admin dashboards, BI tools like Metabase etc |
| app-ro-username | The App's RO user username, automatically updated by OpenTofu. This is currently declared but unused, but ideal usage would be admin dashboards, BI tools like Metabase etc | 
| app-rw-password | The App's RW user password, automatically updated by OpenTofu. This is currently used, instead of the RO keys, as there no read specific operation in the code  |
| app-rw-username | The App's RW user username, automatically updated by OpenTofu. This is currently used, instead of the RO keys, as there no read specific operation in the code |
| pg-admin-password | The postgresql database admin password. Not to be used for anything other than admin operations like user management, db management etc |
| pg-admin-username | Same as above |
| postgres-fqdn | The postgresql connection string. Currently not auto populated, read below for commands* . |
| redis-hostname | The redis server connection string. Auto populated by OpenTofu |
| redis-primary-access-key | The Redis access key. Auto populated by OpenTofu |
| redis-primary-key | The redis primary key reference value. Not auto-populated, read below for obtaining the same** . |

* - Ideally, this should get auto-populated, but this failed silently. Considering this was a one-off action, debugging was time boxed and the decision to make manual update. Commands for the same as follows
 ``` bash

  G_FQDN=$(az postgres flexible-server show \
    --resource-group RamToptal \
    --name <your-pg-server-name> \
    --query fullyQualifiedDomainName -o tsv)

  az keyvault secret set --vault-name node-prod-kv --name postgres-fqdn --value "$PG_FQDN" 
  ```

** - Same issue as above. The commands are as follows
    ```bash
      REDIS_HOST=$(az redis show -g RamToptal -n <redis-name> --query hostName -o tsv)
      
      REDIS_KEY=$(az redis list-keys -g RamToptal -n <redis-name> --query primaryKey -o tsv)

      az keyvault secret set --vault-name node-prod-kv --name redis-hostname --value "$REDIS_HOST"
      
      az keyvault secret set --vault-name node-prod-kv --name redis-primary-key --value "$REDIS_KEY"
      ```


## K8S layer

The implementation used helm charts, found in k8s/ folder.

- Both the API and Web are deployed in the `node--prod--ns` namespace. 
- We have implemented custom api endpoints in both web and api to enable liveness and rediness probes. These endpoints are in no way exhaustive, but are very rudimentary. 
- The first run of the application going live on a new database, we need to run the following. The following creates your application database. Moved to manual again because this is a one-off step, and tofu validate failed when the same came from OpenTofu. Need to figure this out later. 
  
  - First to create the respective users
    ```bash
      export PG_DB=nodeapp
      bash scripts/init-db-users.sh
    ```
  - Next is to create the database. 
    ```bash
    # Fetch secrets
      PG_ADMIN_USER=$(az keyvault secret show --vault-name node-prod-kv --name pg-admin-username --query value -o tsv)
      PG_ADMIN_PASS=$(az keyvault secret show --vault-name node-prod-kv --name pg-admin-password --query value -o tsv)
      APP_RW_PASS=$(az keyvault secret show --vault-name node-prod-kv --name app-rw-password --query value -o tsv)
      APP_RO_PASS=$(az keyvault secret show --vault-name node-prod-kv --name app-ro-password --query value -o tsv)

      # Start a sleeping pod inside the VNet
      kubectl run init-db --restart=Never -n node--prod--ns --image=postgres:16 -- sleep 300
      kubectl wait pod/init-db -n node--prod--ns --for=condition=Ready --timeout=60s

      # Write SQL locally — shell expands passwords here, no escaping needed in the SQL
      cat > /tmp/init-db.sql << ENDSQL
      GRANT CONNECT ON DATABASE appdb TO app_rw, app_ro;
      GRANT USAGE ON SCHEMA public TO app_rw, app_ro;
      GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_rw;
      GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_ro;
      GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_rw, app_ro;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_rw;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_ro;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO app_rw, app_ro;
      ENDSQL

      # Copy SQL into pod and execute — no shell escaping involved
      kubectl cp /tmp/init-db.sql node--prod--ns/init-db:/tmp/init-db.sql
      kubectl exec -n node--prod--ns init-db -- \
        psql "host=node--prod--postgres.postgres.database.azure.com port=5432 dbname=appdb user=${PG_ADMIN_USER} password=${PG_ADMIN_PASS} sslmode=require" \
        -v ON_ERROR_STOP=1 -f /tmp/init-db.sql

      # Clean up
      kubectl delete pod init-db -n node--prod--ns
    ```

- Once done, just run the following to update the helm charts for every release. Ideally you would never do this manually as the same would handled as part of the CD pipeline as documented in release.yml

  - ```bash
    export KEY_VAULT_NAME=node-prod-kv
    bash scripts/aks-deploy.sh
    ```


## Scope for improvement

- I had to deploy resources on a borrowed Azure subscription with many limitations and delayed access, which would not exist in an ideal scenario. I was limited to only 4 VM's of B2s, the basic tier in ACR, Standard tier in Postgresql etc. This limited the scale of platform showcase that was possible.
- The application itself was very elementary to showcase the brevity of the components. For instance, the application did not have any static assets at all, to actually load into the CDN. Some of these limitations like a healthcheck endpoint and readiness endpoint etc, were written but still the application was too skeleton to showcase more sensible things.
- Terraform is currently not in the pipeline, but does have a remote state lock file. It also dosent integrate with any cost management or tag organisation tool like Terrateam or Infracost.This was due my personal time limitation. 
- While SAST is interated, it is not currently a roadblocker on technical debt or code quality that it should be. The ideal relese workflow would run the SAST first, ensure there are not security vulnerabilities and only them proceed to build, release and deploy.
- Monitoring is enabled at every component level, but currently lacks a unified interface. This was also merely a time constraint and not a technical limitation. The centralised dashboard would take about 2 - 3 hours to complete
- Environment level seperation and deployment is currently not done due to resource limitations