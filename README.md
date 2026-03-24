# Infrastructure DevOps Automatisée sur Oracle Cloud

> Projet de fin de module **DevOps & Cloud Computing** — Master Excellence en Intelligence Artificielle  
> Faculté des Sciences Ben M'Sick — Université Hassan II de Casablanca — 2025–2026

---

## Table des matières

- [Vue d'ensemble](#vue-densemble)
- [Architecture](#architecture)
- [Prérequis](#prérequis)
- [Structure du projet](#structure-du-projet)
- [Étape 1 — Terraform](#étape-1--terraform)
- [Étape 2 — Création des VMs Oracle Cloud](#étape-2--création-des-vms-oracle-cloud)
- [Étape 3 — Ansible](#étape-3--ansible)
- [Étape 4 — Cluster Kubernetes](#étape-4--cluster-kubernetes)
- [Étape 5 — Application Flask](#étape-5--application-flask)
- [Étape 6 — Pipeline CI/CD](#étape-6--pipeline-cicd)
- [Étape 7 — Déploiement Kubernetes](#étape-7--déploiement-kubernetes)
- [Étape 8 — Monitoring](#étape-8--monitoring)
- [Accès aux services](#accès-aux-services)
- [Problèmes rencontrés et solutions](#problèmes-rencontrés-et-solutions)

---

## Vue d'ensemble

Ce projet met en place une infrastructure DevOps complète et automatisée sur **Oracle Cloud Free Tier**, couvrant l'ensemble du cycle de vie applicatif : du provisionnement de l'infrastructure jusqu'au monitoring en production.

**Stack technologique :**

| Outil | Rôle |
|-------|------|
| Terraform | Provisionnement réseau Oracle Cloud |
| Ansible | Configuration des VMs (Docker, Kubernetes) |
| Docker | Conteneurisation multi-architecture (amd64 + arm64) |
| Kubernetes (kubeadm) | Orchestration des conteneurs |
| GitHub Actions | Pipeline CI/CD automatisé |
| Prometheus + Grafana | Monitoring et visualisation |

---

## Architecture

```
Machine Locale (WSL Ubuntu 24.04)
├── Terraform   → Réseau Oracle Cloud (VCN, Subnet, Security Lists)
├── Ansible     → Configuration Docker + Kubernetes sur les VMs
└── GitHub      → Pipeline CI/CD (test → build → deploy)

Oracle Cloud (af-casablanca-1)
├── k8s-master  84.8.221.147  (privée: 10.0.0.52)
│   ├── Kubernetes Control Plane (API Server, Scheduler, etcd)
│   └── Stack monitoring (Prometheus + Grafana)
└── k8s-worker  84.8.223.153  (privée: 10.0.0.108)
    ├── Kubernetes Worker Node
    └── Application Flask — 2 replicas — port 30000

Flux CI/CD:
git push → Tests pytest → Docker Build (arm64+amd64) → Docker Hub → kubectl deploy → Pods Running
```

**Spécifications des VMs :**

| VM | Shape | IP Publique | IP Privée | Rôle |
|----|-------|-------------|-----------|------|
| k8s-master | VM.Standard.A1.Flex (2 OCPU, 12 GB) | 84.8.221.147 | 10.0.0.52 | Control Plane |
| k8s-worker | VM.Standard.A1.Flex (2 OCPU, 12 GB) | 84.8.223.153 | 10.0.0.108 | Worker Node |

---

## Prérequis

- WSL2 avec Ubuntu 24.04
- Compte Oracle Cloud Free Tier (région af-casablanca-1)
- Compte GitHub avec accès Actions
- Compte Docker Hub
- Python 3.11+

---

## Structure du projet

```
devops-project/
├── Présentation_Infrastructure DevOps Automatisée sur Oracle Cloud CICD.pdf
├── Rapport_Infrastructure_DevOps_Automatisée_sur_Oracle_Cloud.pdf
├── ansible/
│   ├── inventory.ini          # Hôtes cibles (master + worker)
│   └── playbook-setup.yml     # Installation Docker + Kubernetes
├── app/
│   ├── app.py                 # API REST Flask (/, /health, /ui)
│   ├── Dockerfile             # Image multi-arch python:3.11-slim
│   ├── requirements.txt       # Flask, Gunicorn, Flask-CORS
│   ├── static/
│   │   └── index.html         # Dashboard web de supervision
│   └── tests/
│       └── test_app.py        # Tests pytest (test_home, test_health)
├── k8s/
│   ├── deployment.yaml        # 2 replicas, probes, resource limits
│   └── service.yaml           # NodePort 30000 → port 5000
└── terraform/
    ├── main.tf                # VCN, Subnet, Security Lists, Instances
    ├── terraform.tfstate      # État courant de l'infrastructure
    └── terraform.tfstate.backup
```

---

## Étape 1 — Terraform

### Installation

```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg \
  --dearmor -o /usr/share/keyrings/hashicorp.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] \
  https://apt.releases.hashicorp.com noble main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt-get update && sudo apt-get install -y terraform
```

> ⚠️ Utiliser `noble` (Ubuntu 24.04) et non `focal` (Ubuntu 20.04).

### Configuration OCI

```bash
mkdir -p ~/.oci
mv ~/Downloads/hajar*.pem ~/.oci/oci_api_key.pem
chmod 600 ~/.oci/oci_api_key.pem
```

Créer `~/.oci/config` :

```ini
[DEFAULT]
user=ocid1.user.oc1..xxxxxxxxxxxxxxxx
fingerprint=xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx
tenancy=ocid1.tenancy.oc1..xxxxxxxxxxxxxxxx
region=af-casablanca-1
key_file=~/.oci/oci_api_key.pem
```

Générer la clé SSH :

```bash
ssh-keygen -t rsa -b 4096 -C "hajar@devops-project"
```

### Déploiement

```bash
# Fix réseau WSL2
echo "13.224.83.61 registry.terraform.io" | sudo tee -a /etc/hosts

cd terraform/
terraform init
terraform plan
terraform apply
```

**Résultat :** VCN `devops-vcn` et subnet `public-subnet` créés.

> ⚠️ Erreur `404-NotAuthorizedOrNotFound` lors de la création des VMs — restrictions IAM Free Tier. Les VMs ont été créées manuellement (voir Étape 2) en réutilisant le réseau Terraform.

---

## Étape 2 — Création des VMs Oracle Cloud

Depuis la console Oracle Cloud → **Compute → Instances → Create Instance** :

| Paramètre | Valeur |
|-----------|--------|
| Nom | k8s-master / k8s-worker |
| Image | Canonical Ubuntu 22.04 |
| Shape | VM.Standard.A1.Flex |
| OCPUs | 2 |
| RAM | 12 GB |
| Réseau | VCN devops-vcn + subnet public |
| Clé SSH | Coller le contenu de `~/.ssh/id_rsa.pub` |

**Security List — Règles Ingress à ouvrir :**

| Port | Protocole | Usage |
|------|-----------|-------|
| 22 | TCP | SSH |
| 6443 | TCP | Kubernetes API Server |
| 10250 | TCP | kubelet |
| 30000–32767 | TCP | NodePort (application) |
| 31000 | TCP | Grafana |
| Tous | ICMP | Ping / diagnostic |

---

## Étape 3 — Ansible

### Installation

```bash
pip3 install ansible --break-system-packages
```

### Inventaire

```ini
# ansible/inventory.ini
[master]
k8s-master ansible_host=84.8.221.147 ansible_user=ubuntu \
  ansible_ssh_private_key_file=~/.ssh/id_rsa

[worker]
k8s-worker ansible_host=84.8.223.153 ansible_user=ubuntu \
  ansible_ssh_private_key_file=~/.ssh/id_rsa

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

### Exécution

```bash
cd ansible/

# Test de connectivité
ansible all -i inventory.ini -m ping

# Configuration complète
ansible-playbook -i inventory.ini playbook-setup.yml
```

**Le playbook installe sur les deux VMs :**
- Docker CE (arch=arm64, repo jammy)
- containerd avec `SystemdCgroup=true`
- kubeadm, kubelet, kubectl v1.28 (version fixée)
- Modules noyau `overlay` et `br_netfilter`
- Paramètres sysctl pour Kubernetes
- Désactivation du swap

---

## Étape 4 — Cluster Kubernetes

### Initialisation du Master

```bash
ssh ubuntu@84.8.221.147

# Configurer containerd
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' \
  /etc/containerd/config.toml
sudo systemctl restart containerd

# Initialiser le cluster
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=10.0.0.52

# Configurer kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Installer Flannel (plugin réseau)
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# Obtenir la commande join pour le worker
kubeadm token create --print-join-command
```

### Jonction du Worker

```bash
ssh ubuntu@84.8.223.153

# Même configuration containerd
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' \
  /etc/containerd/config.toml
sudo systemctl restart containerd

# Rejoindre le cluster (commande obtenue depuis le master)
sudo kubeadm join 10.0.0.52:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

### Vérification

```bash
kubectl get nodes
# NAME                STATUS   ROLES           AGE   VERSION
# devops-vcn-571552   Ready    <none>          ...   v1.28.15
# vcn-devops          Ready    control-plane   ...   v1.28.15
```

> ⚠️ Après redémarrage des VMs, si le port 6443 devient inaccessible, réinitialiser iptables :
> ```bash
> sudo iptables -F && sudo iptables -X
> sudo iptables -t nat -F && sudo iptables -t nat -X
> sudo iptables -P INPUT ACCEPT
> sudo iptables -P FORWARD ACCEPT
> sudo iptables -P OUTPUT ACCEPT
> ```

---

## Étape 5 — Application Flask

### Routes

| Route | Réponse |
|-------|---------|
| `GET /` | `{"message": "API DevOps...", "status": "running", "version": "1.0.0"}` |
| `GET /health` | `{"status": "healthy"}` — utilisé par les sondes Kubernetes |
| `GET /ui` | Dashboard web de supervision |

### Tests locaux

```bash
cd app/
pip install -r requirements.txt pytest
pytest tests/ -v
```

### Build Docker local

```bash
docker build -t flask-devops:local .
docker run -p 5000:5000 flask-devops:local
curl http://localhost:5000/health
```

---

## Étape 6 — Pipeline CI/CD

### Secrets GitHub à configurer

**GitHub → Settings → Secrets and variables → Actions :**

| Secret | Description |
|--------|-------------|
| `DOCKERHUB_USERNAME` | Nom d'utilisateur Docker Hub |
| `DOCKERHUB_TOKEN` | Token Docker Hub (Account Settings → Security) |
| `KUBE_CONFIG` | Contenu de `~/.kube/config` encodé en base64 |
| `MASTER_SSH_KEY` | Clé SSH privée (`~/.ssh/id_rsa`) |

```bash
# Générer KUBE_CONFIG (sur le master)
cat ~/.kube/config | base64 -w 0
```

### Pipeline — 3 jobs séquentiels

```
Push → [test] → [build-push] → [deploy]
```

1. **test** : `pytest app/tests/ -v` — échec = pipeline stoppé
2. **build-push** : Docker Buildx multi-arch (`linux/amd64,linux/arm64`) → Docker Hub
3. **deploy** : `kubectl set image` + `kubectl rollout status` — rolling update sans downtime

Le fichier `.github/workflows/ci-cd.yml` se trouve à la racine du dépôt GitHub.

---

## Étape 7 — Déploiement Kubernetes

```bash
# Copier les manifests sur le master
scp -r k8s/ ubuntu@84.8.221.147:~/k8s/

# Appliquer
ssh ubuntu@84.8.221.147
kubectl apply -f ~/k8s/deployment.yaml
kubectl apply -f ~/k8s/service.yaml

# Vérifier
kubectl get pods
kubectl get svc
```

**Caractéristiques du déploiement :**
- 2 replicas (haute disponibilité)
- `livenessProbe` sur `/health` (redémarre si le pod ne répond plus)
- `readinessProbe` sur `/health` (attend que le pod soit prêt avant d'envoyer du trafic)
- Limites : 64–128 Mi RAM · 100–200m CPU

---

## Étape 8 — Monitoring

```bash
ssh ubuntu@84.8.221.147

# Installer Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Ajouter le repo
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts
helm repo update

# Installer le stack complet
kubectl create namespace monitoring
helm install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=31000

# Vérifier
kubectl get pods -n monitoring
```

**Récupérer le mot de passe Grafana :**

```bash
kubectl get secret -n monitoring kube-prometheus-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

**Dashboards Grafana à importer :**

| ID | Nom |
|----|-----|
| 6417 | Kubernetes Cluster (Prometheus) |
| 1860 | Node Exporter Full |
| 15760 | Kubernetes cluster monitoring |

---

## Accès aux services

| Service | URL |
|---------|-----|
| API Flask | http://84.8.223.153:30000 |
| Health check | http://84.8.223.153:30000/health |
| Dashboard UI | http://84.8.223.153:30000/ui |
| Grafana | http://84.8.223.153:31000 |

---

## Problèmes rencontrés et solutions

| Problème | Cause | Solution |
|----------|-------|----------|
| `Unable to locate package terraform` | Repo `focal` au lieu de `noble` | Utiliser `noble` dans l'URL du dépôt HashiCorp |
| `404-NotAuthorizedOrNotFound` Terraform | Restrictions IAM Free Tier root | Créer les VMs manuellement via la console Oracle |
| `NumCPU: 1, minimum: 2` kubeadm | VMs avec 1 OCPU | Redimensionner à 2 OCPUs dans la console Oracle |
| `br_netfilter not found` | Module noyau non chargé | `sudo modprobe br_netfilter` + sysctl |
| Port 6443 inaccessible | Firewall Oracle Cloud | Ajouter règle Ingress TCP 6443 dans Security List |
| `exec format error` pods | Image x86 sur ARM64 | Build multi-arch avec QEMU + Docker Buildx |
| TLS certificate error CI/CD | IP publique absente du certificat | `insecure-skip-tls-verify: true` dans kubeconfig |
| Port 6443 timeout après redémarrage | Règles iptables réinitialisées | Vider iptables et relancer kubelet |
| `No such file or directory: /app/static/` | Dossier absent du Dockerfile | Ajouter `COPY static/ static/` dans le Dockerfile |

---

## Documents

- 📄 [Rapport complet](./Rapport_Infrastructure_DevOps_Automatisée_sur_Oracle_Cloud.pdf)
- 📊 [Présentation](./Présentation_Infrastructure%20DevOps%20Automatisée%20sur%20Oracle%20Cloud%20CICD.pdf)

---

**Hajar ELKHALIDI & Nohaila ICHOU** — Master Excellence en Intelligence Artificielle — FSBM — Université Hassan II de Casablanca — 2025–2026
