# Projet DevOps
#### Groupe du projet : 
    - Alicia SACI 5IW1
    - Awa Bah 5IW1

### Azure :
  1. Connexion au compte azure
    ```az login```

### Terrafom : Déploiement des ressources 
  1. Créer le groupe de ressources dans azure
     - Dans terraform.tfvars, renseigner la location, le resource_groupe ainsi que le nom du compte de stockage :
       ```
       location             = "francecentral"
       resource_group       = "rg-esgi-alicia-saci-awa-bah"
       storage_account_name = "staliciasaci-awabah"
       ```
     - Dans main.tf, créer le groupe de ressources :
       ```
       resource "azurerm_resource_group" "rg_main" {
        name     = var.resource_group
        location = var.location
        tags = {
          environment = "Terraform Lab"
          }
        }
       ```
  2. Créer le registre de conteneur
     - Dans main.tf, créer le register de conteneur avec le nom "registeryaliciasaci". le mettre dans le groupe de ressouces principal avec SKU à standard.
       ```
        resource "azurerm_container_registry" "acr" {
        name                = "registryaliciaawa"
        resource_group_name = azurerm_resource_group.rg_main.name
        location            = azurerm_resource_group.rg_main.location
        sku                 = "Standard"
        admin_enabled       = false
        }
       ```
  3. Créer un kluster Kubernetes
     - Dans main.tf, créer le kluster au nom "cluster_kube". La location et le groupe de ressources sont les mêmes défini dans le terraform.tfvars. Le kluster contient 1 seul node.
       ```
       resource "azurerm_kubernetes_cluster" "rg_main" {
        name                = "cluster_kube"
        location            = azurerm_resource_group.rg_main.location
        resource_group_name = azurerm_resource_group.rg_main.name
        dns_prefix          = "kubecluster"

        default_node_pool {
        name       = "default"
        node_count = 1
        vm_size    = "Standard_B2s"
        }

        identity {
        type = "SystemAssigned"
        }
        }
      ```
  4. Adresse IP publique
      ```
      resource "azurerm_public_ip" "aks_public_ip" {
      name                = "aks-public-ip"
      resource_group_name = azurerm_kubernetes_cluster.rg_main.node_resource_group
      location            = azurerm_kubernetes_cluster.rg_main.location
      allocation_method   = "Static"
      sku                 = "Standard"

      tags = {
      environment = "Terraform Lab"
      }
      }
      ```
  5. Créer un role pour que le cluster puisse pull depuis le registry
      ```
      resource "azurerm_role_assignment" "acr_pull_assignment" {
        scope                = azurerm_container_registry.acr.id
        role_definition_name = "AcrPull"
        principal_id         = azurerm_kubernetes_cluster.rg_main.kubelet_identity[0].object_id
      }
      ``` 
  6. Créer un role pour pouvoir push des images dans le registry
      ```
      resource "azurerm_role_assignment" "acr_push_assignment" {
        scope                = azurerm_container_registry.acr.id
        role_definition_name = "AcrPush"
        principal_id         = data.azurerm_client_config.current.object_id
      }
      ``` 
  7. Initialiser les dossier terraform
    `terraform init`

  8. Déployer les ressources
    `terraform apply`


### Docker : build de l'image
  1. Se placer dans le dossier flask-app
    `cd flask-app`
  2. Construire l'image flask-app 
    `docker build . -t flask-app`
  3. Se connecter au registry 
    `az acr login --name <nom-regsitry>`
  4. Tagger l'image flask-app dans le registry Azure
    `docker tag flask-app <nom-registry>.azurecr.io/flask-app`
  5. Push l'image dans le repository Azure
    `docker push <nom-registry>.azurecr.io/flask-app`


### Kubernetes 
  1. Se connecter au cluster AKS de Azure
      ```
      az aks get-credentials --resource-group <nom-ressource-groupe> --name <nom-cluster-kubernetes>
      ```  
  2. Utiliser Helm pour installer un Ingress Nginx

    1. Récupérer l'adresse IP publique déclaré dans les ressources dans une variable
        ```
        PUBLIC_IP=$(az network public-ip show  --resource-group 'Nom groupe de ressource cluster kube' -n 'Nom de l'adresse ip' --query "ipAddress" | tr -d '"')
        ```
    2. Définition du namespace a créer
        ```
        NAMESPACE=ingress-basic
        ```
    3. Ajouter ingress dans les repo Helm 
      `helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx`
    4. Mettre à jour les repo helm
      `helm repo update`
    5. Installer l'Ingress avec helm
      ```helm install ingress-nginx ingress-nginx/ingress-nginx \
        --create-namespace \
        --namespace $NAMESPACE \
        --set controller.service.loadBalancerIP=$PUBLIC_IP \
        --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz 
      ```
  
  3. Créer un service redis
    1. Dans le dossier kubernetes créer un fichier redis.yaml
      ```
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: redis
        namespace: ingress-basic
      spec:
        replicas: 1
        selector:
          matchLabels:
            app: redis
        template:
          metadata:
            labels:
              app: redis
          spec:
            containers:
            - name: redis
              image: redis:alpine
              ports:
              - containerPort: 6379
            volumes:
            - name: redis-storage
              emptyDir: {}
          

      ---
      apiVersion: v1
      kind: Service
      metadata:
        name: redis
        namespace: ingress-basic
      spec:
        type: ClusterIP
        selector:
          app: redis
        ports:
        - protocol: TCP
          port : 6379
          targetPort: 6379
      ```

    2. Créer le service sur kubernetes 
      ```
        kubectl apply -f kubernetes/redis.yaml --namespace ingress-basic
      ```

  4. Créer un service Flask-app
    1. Créer dans kubernetes le fichier flask.yaml
      ```
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: flask-app
          namespace: ingress-basic
        spec:
          replicas: 1
          selector : 
            matchLabels:
              app: flask-app

          template:
            metadata:
              labels:
                app: flask-app
            spec:
              containers:
                - name: flask-app
                  image: <nom-registry>.azurecr.io/flask-app:latest
                  ports:
                  - containerPort: 8000
        ---
        apiVersion: v1
        kind: Service
        metadata:
          name: flask-app 
        spec:
          type: ClusterIP
          ports:
          - port: 8000
          selector:
            app: flask-app
      ```
    2. Créer le service flask sur kubernetes
      `kubectl apply -f kubernetes/flask.yaml --namespace ingress-basic`

  5. Créer le routage sur Ingress
    1. Dans le dossier kubernetes créer le fichier ingress.yaml
      ```
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: name-ingress
        annotations:
          nginx.ingress.kubernetes.io/ssl-redirect: "false"
          nginx.ingress.kubernetes.io/use-regex: "true"
          nginx.ingress.kubernetes.io/rewrite-target: /$2
      spec:
        ingressClassName: nginx
        rules:
        - http:
            paths:
            - path: /(.*)
              pathType: Prefix
              backend:
                service:
                  name: flask-app
                  port:
                    number: 8000
      ```
    2. Créer la route ingress sur kuvbernetes
      ```
      kubectl apply -f kubernetes/ingress.yaml --namespace ingress-basic
      ```
    



  
  
