# HYLASTIX Test

## Running the Demo with GitHub Actions
This project includes three GitHub Actions workflows:
1. roll-out-vm - Creates an Azure environment with a virtual machine.
2. configure-vm - Configures the VM by installing Docker and deploying a Keyclock-protected static web site.
3. disassemble-vm - Destroys the Azure environment and removes the VM.

### Required GitHub Secrets
For these workflows to run successfully, the following GitHub secrets must be configured:
* ARM_CLIENT_ID
* ARM_CLIENT_SECRET
* ARM_SUBSCRIPTION_ID
* ARM_TENANT_ID
* SSH_PUBLIC_KEY
* SSH_PRIVATE_KEY
* OAUTH2_COOKIE_SECRET

### Generating Azure Service Principal Credentials
The `ARM_*` secrets can be created by running:
```
az ad sp create-for-rbac \
  --name "github-terraform-sp" \
  --sdk-auth \
  --role Contributor \
  --scopes /subscriptions/<YOUR_SUBSCRIPTION_ID>
```
This command returns JSON output similar to:
```
{
  "clientId": "bf...cd",
  "clientSecret": "DG...sN",
  "subscriptionId": "eb...cd",
  "tenantId": "ad...70",
  "activeDirectoryEndpointUrl": "https://login.microsoftonline.com",
  "resourceManagerEndpointUrl": "https://management.azure.com/",
  "activeDirectoryGraphResourceId": "https://graph.windows.net/",
  "sqlManagementEndpointUrl": "https://management.core.windows.net:8443/",
  "galleryEndpointUrl": "https://gallery.azure.com/",
  "managementEndpointUrl": "https://management.core.windows.net/"
}
```
From this output, use the values for `clientId`, `clientSecret`, `subscriptionId`, and `tenantId`.

### Generating an SSH Key
An SSH key pair is required to access the VM (and is also used by Ansible). Generate it with:
```
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

### OAuth2 Cookie Secret
The `OAUTH2_COOKIE_SECRET` must be a 32-byte random base64 string. For example:
```
openssl rand -base64 32
```

### Accessing the Demo Website
After running the `roll-out-vm` and `configure-vm` workflows, the static web site will be available at:
```
http://<VM_PUBLIC_IP>
```
Authentication is handled via Keycloak. The default credentials are:
* Username: `user1`
* Password: `password`
The VM's public IP can be found int the GitHub Actions logs::
* in the `roll-out-vm` workflow -> `terraform apply` step (outputs at the end).
* in the `configure-vm` workflow -> `ansible playbook run` step.

### Tearing Down the Environment
To remove all resources, run the `disassemble-vm` workflow.

## Architecture
In Azure, the following infrastructure is provisioned:
* A **Virtual Network (Vnet)** with a private subnet.
* A **single VM** within the subnet, assigned a public IP address.
* A **Network Security Group (NSG)** attached to the subnet, allowing inbound traffic only on:
  * SSH (22)
  * HTTP/HTTPS (80/443)
  * Keycloak (8080)
All other ports are blocked from the Internet. Specifically:
* Postgres (5432) and OAuth2 Proxy (4180) are only accessible on the internal Docker bridge network.

### Services on the VM
On the Azure VM, Docker Engine is installed, and services are orchestrated with Docker Compose. The following containers are deployed (see `ansible\roles\keycloak-stack\templates\docker-compose.yml.j2`):
* **Keycloak** (identity provider)
* **Postgres** (database for Keycloak)
* **OAuth2 Proxy** (authentication/authorization proxy)
* **Web** - Nginx serving the static website
* **Nginx Proxy** - handles external requests and routes them internally

```mermaid
graph TD
    subgraph AzureVNet["Azure VNet (Private Subnet)"]
        VM[Azure VM<br/>Public IP + NSG]
        
        subgraph Docker["Docker Bridge Network"]
            KC[Keycloak]
            PG[Postgres]
            O2P[OAuth2 Proxy]
            WEB[Static Website (Nginx)]
            NGINX[Nginx Proxy]
        end
    end

    Internet[[Internet]] -->|SSH (22), HTTP/HTTPS (80/443), Keycloak (8080)| VM
    VM --> Docker

    %% Internal connections
    KC <-->|DB Connection (5432)| PG
    O2P <-->|Auth Tokens| KC
    NGINX --> O2P
    O2P --> WEB
```

### Request Flow
1. User visits `http://<VM_PUBLIC_IP>/`.
2. **Nginx** forwards the request to **OAuth2 Proxy**.
3. **OAuth2 Proxy** checks for authentication. If the user is not logged in, it redirects to **Keycloak**.
4. After login, **Keycloak** redirects the user back to **OAuth2 Proxy** with an authorization code (`/oauth2/callback`).
5. **OAuth2 Proxy* exchanges the code for tokens with **Keycloak**.
6. Upon successful validation, **OAuth2 Proxy** sets a session cookie and forwards the original request to the upstream **web (Nginx)** container.
7. The user sees static webpage.

```mermaid
flowchart TD
    U[User Browser] -->|1. Visit http://PUBLIC_HOSTNAME/| NginxProxy[Nginx Proxy]
    NginxProxy -->|2. Forward request| O2P[OAuth2 Proxy]
    O2P -->|3. Redirect to login if not authenticated| KC[Keycloak]
    KC -->|4. Redirect back with auth code| O2P
    O2P -->|5. Exchange code for tokens| KC
    O2P -->|6. Validate token & set cookie| Web[Static Website (Nginx)]
    Web -->|7. Return static page| U
```

## Justification
The design choices it this project are justified as follows:
* **OAuth2 Proxy + Keycloak + NGINX** provide a robust solution for adding authentication and authorization to applications that do not natively support OIDC or OAuth2 (such as this static web site).
* **Keycloak**: Serves as the OpenID Connect (OIDC) provider and OAuth2 authorization server. It handles user authentication, manages accounts, realms, and client configurations.
* **OAuth2 Proxy**: Acts as a reverse proxy in front of the static web site. It intercepts requests, preforms the OIDC flow with Keycloak, and injects authentication data into HTTP headers before forwarding requests to the upstream application.
* **NGINX (web container)**: Hosts and serves the static web site. It sits upstream of Oauth2 Proxy and receives only authenticated traffic.
* **NGINX (proxy container)**: Functions as a reverse proxy that directs incomming traffic to OAuth2 Proxy.
* **Latest container images**: We use the latest versions of Keycloak, OAuth2 Proxy, Postgres, and Nginx to ensure stability, security patches, and up-to-date features.
* **Docker Engine (container runtime)**:
  * Chosen for its wide support, ease of installation (via Ansible), minimal overhead, and user-friendly experience for local development and operations.
  * Alternatives:
    * Podman - lightweight and daemonless, but with smaller ecosystem adoption.
    * containerd - highly efficient and used in Kubernetes environments, but less convenient for standalone setups.
* **Separation of workflows**:
  * While the `roll-out-vm` and `configure-vm` GitHub Actions could be combined into a signle workflow, we keep them separate to imporve flexibility during testing and development.
  * This allows provisioning the VM independently and experimenting manually without immediately applying the Ansible configuration step.

## Extensibility
The current setup is designed as a lightweight demo, but it can be extended in several ways to improve security, scalability, and production readiness:
* **Enable TLS with Let’s Encrypt and Azure DNS**
Secure the application with HTTPS certificates and integrate with Azure DNS for domain management.
* **Manage sensitive variables more securely**
  * Use **Ansible Vault** for encrypted variables, or
  * Integrate with an **external secrets store** (e.g., Azure Key Vault).
* **Scale Keycloak and the web application**
  * Run Keycloak on a dedicated VM.
  * Use an Azure Load Balancer with Virtual Machine Scale Sets (VMSS) for the web application to enable auto-scaling.
* **Adopt managed services for production**
For a production-ready deployment, migrate to:
  * Azure Kubernetes Service (AKS) for container orchestration.
  * A managed database service (e.g., Azure Database for PostgreSQL).
This is not necessary for the demo setup, as it would add complexity and cost.

## Additional notes

### Terraform backend
The terraform backend uses an **Azure Storage account** and a **container** inside it to store state file.

This allows multiple GitHub Actions workflows to share and update the same Terraform state.

Resources required: 
* Resource group (example: `rg-terraform-state`)
* Storage account (example: `tfstatestorage`)
* Container in the storage account (example: `tfstate`)

Create them via Azure CLI:
```
az group create --name rg-terraform-state --location westeurope

az storage account create \
  --name tfstatestorage82063e34 \
  --resource-group rg-terraform-state \
  --sku Standard_LRS \
  --kind StorageV2 \
  --location westeurope

az storage container create \
  --name hxtest \
  --account-name tfstatestorage82063e34
```

### Keycloak custom realm
This demo imports a custom Keycloak realm: `myrealm` (see `ansible\roles\keycloak-stack\templates\myrealm-realm.json.j2`)
* Default username and password: `user1` and `password`
* These can be overridden using environment variables:
  * `USER_NAME`
  * `USER_PASSWORD`
(defined in see `ansible\roles\keycloak-stack\defaults\main.yml`).

### Keycloak HTTPS
By default, Keycloak runs in HTTPS mode.

For this demo, HTTPS is **disabled** after keycloak container becomes ready (configured in  `ansible\roles\keycloak-stack\tasks\main.yml`).
* The Keycloak UI is than available at `http://<VM_PUBLIC_IP>:8080`.
* To encure reliability, Ansible checks the Keycloak health endpoint (up to 5 minutes), before starting dependent containers like OAuth2 Proxy.

### Customization of Sensitive Data
Several sensitive defaults can be overridden using environment variables (optionally stored in GitHub secrets):
* KEYCLOAK_ADMIN_USER (default `admin`)
* KEYCLOAK_ADMIN_PASSWORD (default `AdminPassword123`)
* POSTGRES_USER (default `keycloak`)
* POSTGRES_PASSWORD (default `keycloak`)
* OAUTH2_CLIENT_ID (default `keycloak-client-id`)
* OAUTH2_CLIENT_SECRET (default `keycloak-client-secret`)

### Running the Demo Manually
1. **Login to Azure**
```
az login
```
Ensure your account has sufficient privileges.
2. **Prepare Terraform state storage**
Either use the Azure backend (see above) or comment out backend.tf to store the state locally.
3. **Provision the environment**
```
cd terraform
terraform init
terraform apply
```
* `terraform apply` will ask for the `ssh_public_key`.
* Alternatevely, set it via environment variable:
```
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_rsa.pub)"
```
4. **Configure with Ansible**
* Prepare `inventory.ini` ()use VM's public IP and private key
* Run:
```
export ANSIBLE_HOST_KEY_CHECKING="False"
export OAUTH2_COOKIE_SECRET="$(openssl rand -base64 32)"
ansible-playbook -i inventory.ini playbook.yml
```
5. **Access the demo**
Visit `http://<VM_PUBLIC_IP>`
Login with:
* Username: `user1`
* Password: `password`.
6. ** Destroy the environment**
```
cd terraform
terraform destroy
```
