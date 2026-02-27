# Ramaseshan's Toptal interview task

## Requirements for Installation 

1. [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?view=azure-cli-latest&pivots=apt)
2. [OpenTofu or Terraform](https://opentofu.org/)
3. kubectl and kubenamespace
4. Docker
5. Azure Subscription and a resource group (A copy of subscription ID and Resource Group ID)

Note: I had access to an azure cloud at the point of preparation, similar setup can be implemented in AWS or GCP or smaller cloud providers like DigitalOcean or Linode etc


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





docker login -u NodeACRPullTokken01 -p 5KctAMG2KdZrpEKMyZ2gV51QGRl2rXPY80Yl14nGxqWNeVoonYrXJQQJ99CBACGhslBEqg7NAAABAZCRddby nodeprodacr.azurecr.io