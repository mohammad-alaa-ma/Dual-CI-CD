# First CI for provisioning Infra using Terraform

## Step 1: Prepare Cloud VM (ubuntu 24 t2.medium)

### Install and Configure

```bash
sudo apt update
## Install Java (Jenkins Needs Java)
sudo apt install -y openjdk-17-jdk
java -version
## Add Jenkins Repository and Key
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee \
  /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update
sudo apt install -y jenkins
sudo systemctl enable jenkins
sudo systemctl start jenkins
sudo systemctl status jenkins

```

```bash
## Install terraform
sudo apt-get update
sudo apt-get install -y unzip
wget https://releases.hashicorp.com/terraform/1.9.5/terraform_1.9.5_linux_amd64.zip
sudo unzip terraform_1.9.5_linux_amd64.zip -d /usr/local/bin/
terraform -version
```


![Line](./Screenshots/Jenkinsfile.terraform/1.png)


![Line](./Screenshots/Jenkinsfile.terraform/2.png)







Access Jenkins:
 `http://<VM_PUBLIC_IP>:8080`

---

## Step 2: Configure AWS Credentials for Terraform

Terraform will need access to AWS to build infrastructure.

### Use IAM User Access Keys

1. Create an IAM role in AWS (e.g., `roleForJenkinsInfra`) with permissions like:

   * `AmazonS3FullAccess`
   * `AmazonEKSFullAccess`
   * `AmazonEKSServicePolicy`
   * `AmazonEC2FullAccess`
   * `AmazonVPCFullAccess`
   * `IAMFullAccess`
   * etc. (or use a custom least-privilege policy later)

---

![Line](./Screenshots/Jenkinsfile.terraform/4.png)


## Step 3: Connect Jenkins with GitHub

### In your GitHub repo:

* Go to **Settings → Webhooks → Add webhook**
* Payload URL → `http://<your_VM_IP>:8080/github-webhook/`
* Content type: `application/json`
* Select: “Just the push event”

![Line](./Screenshots/Jenkinsfile.terraform/3.png)


### In Jenkins:

* Install the plugin ( if not installed ):

  * “GitHub Integration” or “GitHub Plugin”
* Create a new **Pipeline job**

  * Choose: “GitHub hook trigger for GITScm polling”

---

## Step 4: Create the Pipeline Script (`Jenkinsfile.terraform`)

This file will be in GitHub repo's root (Jenkins will read it).


## Step 5: Folder Structure Related to this CI pipeline

```
.
├── Jenkinsfile.terraform
└── terraform/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── backend.tf
```

---

## Flow Summary

| Step | Action                                             | Tool            |
| ---- | -------------------------------------------------- | --------------- |
| 1    | Developer commits change to `terraform/`           | GitHub          |
| 2    | GitHub webhook notifies Jenkins                    | GitHub Webhook  |
| 3    | Jenkins pulls latest code                          | Git             |
| 4    | Jenkins runs Terraform init, validate, plan, apply | Terraform       |
| 5    | Infrastructure is provisioned/updated              | AWS (EKS, etc.) |

---

## Running the pipeline to provision infra on changes made in terrafrom directory


![Line](./Screenshots/Jenkinsfile.terraform/5.png)

![Line](./Screenshots/Jenkinsfile.terraform/6.png)

![Line](./Screenshots/Jenkinsfile.terraform/7.png)

![Line](./Screenshots/Jenkinsfile.terraform/8.png)

![Line](./Screenshots/Jenkinsfile.terraform/9.png)

![Line](./Screenshots/Jenkinsfile.terraform/10.png)

---

# Second CI in EKS using helm for building, making smoke test, pushing to ECR and Notifying on failure in any stage

## Step 1: Create EKS Cluster with Two Nodes

First, let's set up your EKS cluster using AWS CloudShell. We'll use `eksctl` which is pre-installed in CloudShell.
```bash
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz"
tar -xzf eksctl_Linux_amd64.tar.gz
sudo mv eksctl /usr/local/bin
eksctl version
```

### Commands for Step 1:

```bash
# Create EKS cluster with 2 nodes and 20GB storage each
eksctl create cluster \
  --name jenkins-cluster \
  --region us-east-1 \
  --nodegroup-name jenkins-nodes \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 2 \
  --nodes-max 2 \
  --node-volume-size 20 \
  --managed
```


### Verify the cluster creation:
```bash
# Check cluster status
eksctl get cluster --name jenkins-cluster --region us-east-1
```
![Line](./Screenshots/Jenkinsfile.build//1.png)

```bash
# Verify nodes
kubectl get nodes
```
![Line](./Screenshots/Jenkinsfile.build//2.png)

## Step 2: Install Helm

First, we need to install Helm in CloudShell environment.

### Commands for Step 2:

```bash
# Download and install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify Helm installation
helm version
```

**Expected output:** You should see Helm version 3.x.x

![Line](./Screenshots/Jenkinsfile.build//3.png)


## Step 3: Preparing EBS driver for Jenkins master pod installed by Helm


### I. Associate IAM OIDC Provider

Associate your EKS cluster with an **OIDC provider** to enable Kubernetes service accounts to assume IAM roles securely.

```bash
eksctl utils associate-iam-oidc-provider \
  --region us-east-1 \
  --cluster jenkins-cluster \
  --approve
```
![Line](./Screenshots/Jenkinsfile.build//4.png)

### II. Create IAM Service Account

Create a **service account** linked to an **IAM role** with EBS permissions.

```bash
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster jenkins-cluster \
  --region us-east-1 \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve \
  --role-only \
  --role-name AmazonEKS_EBS_CSI_DriverRole
```

This command:

* Creates the Kubernetes service account `ebs-csi-controller-sa`.
* Creates and attaches the IAM role `AmazonEKS_EBS_CSI_DriverRole`.
* Establishes trust via the OIDC provider.

![Line](./Screenshots/Jenkinsfile.build//5.png)

### III. Install the EBS CSI Driver Addon

Install the **Amazon EBS CSI driver** addon using the IAM role created above.

```bash
eksctl create addon \
  --name aws-ebs-csi-driver \
  --cluster jenkins-cluster \
  --region us-east-1 \
  --service-account-role-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/AmazonEKS_EBS_CSI_DriverRole \
  --force
```
The addon deploys EBS CSI controller and node pods, which use the `ebs-csi-controller-sa` service account to assume the attached IAM role for EBS operations.



### IV. Verify the Installation

```bash
# Check driver pods
kubectl get pods -n kube-system | grep ebs-csi

# Check storage classes
kubectl get storageclass
```

You should see:

* Pods like `ebs-csi-controller` and `ebs-csi-node` running.
* A `gp2` or `gp3` storage class available.

![Line](./Screenshots/Jenkinsfile.build//6.png)

---

### Summary of Roles

| Component           | Purpose                                                  |
| ------------------- | -------------------------------------------------------- |
| **OIDC Provider**   | Enables AWS to trust Kubernetes service accounts         |
| **Service Account** | Identity inside Kubernetes for the EBS CSI driver        |
| **IAM Role**        | Grants AWS EBS permissions to the driver                 |
| **EKS Addon**       | Deploys and manages the EBS CSI driver pods              |
| **EBS CSI Driver**  | Handles EBS volume creation, attachment, and deletion    |
| **Jenkins Pod**     | Requests PersistentVolume → driver provisions EBS volume |

---

## Step 4: Add Jenkins Helm Repository



### Commands for Step 4:

```bash
# Add Jenkins Helm repository
helm repo add jenkins https://charts.jenkins.io

# Update Helm repositories
helm repo update

# Verify Jenkins chart is available
helm search repo jenkins
```

**Expected output:** You should see the Jenkins chart listed with its version.

![Line](./Screenshots/Jenkinsfile.build//7.png)


## Step 5: Install Jenkins using Helm with your values file

Now let's install Jenkins using your `jenkins-values.yaml` file.

```bash
controller:
  serviceAccount:
    create: false
    name: jenkins
  
  installPlugins:
    - kubernetes:latest
    - workflow-aggregator:latest
    - git:latest
    - configuration-as-code:latest
  
  serviceType: NodePort
  nodePort: 32000
  
agent:
  podName: "jenkins-agent"
  
persistence:
  enabled: true
  size: 8Gi
  storageClass: gp2
```

### Commands for Step 5:

```bash
# Create a namespace for Jenkins
kubectl create namespace jenkins

# Install Jenkins using your values file
helm install jenkins jenkins/jenkins \
  --namespace jenkins \
  --values jenkins-values.yaml
```
![Line](./Screenshots/Jenkinsfile.build//8.png)

```bash
# Wait for Jenkins to be ready (this may take 2-3 minutes)
kubectl get pods -n jenkins -w
```
![Line](./Screenshots/Jenkinsfile.build//9.png)

**The 8 GB EBS volume is created by CSI driver**

![Line](./Screenshots/Jenkinsfile.build//11.png)




### Get the initial admin password:
```bash
# Get Jenkins admin password
kubectl exec -n jenkins -it svc/jenkins -c jenkins -- cat /run/secrets/additional/chart-admin-password && echo
```



### Get the NodePort access:
```bash
# Get the node external IP
kubectl get nodes -o wide

# Confirm NodePort
kubectl get svc -n jenkins
```
![Line](./Screenshots/Jenkinsfile.build//10.png)


**NOTE:** If there is a problem in accessing jenkins server check allowed inbound of the security group attached to nodes

**You should access Jenkins at:** `http://<NODE_EXTERNAL_IP>:32000`


## Step 6: Create IAM User and Add AWS Credentials to Jenkins

1. **Create an IAM User for ECR Access**
   - In the AWS Console → IAM → Users → Create User  
   - Attach a minimal policy with ECR access:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    }
  ]
}
```
Get the Access Key ID and Secret Access Key

![Line](./Screenshots/Jenkinsfile.build//12.png)


Add AWS Credentials and telegram token and chat ID to Jenkins.


## Step 7: Create an ECR Repository

```bash
aws ecr create-repository \
  --repository-name iti-gp-project \
  --region us-east-1

# Verify the repository was created
aws ecr describe-repositories --repository-names iti-gp-project --region us-east-1
```

![Line](./Screenshots/Jenkinsfile.build//13.png)


You should see your repository URI, for example:
<accountID>.dkr.ecr.us-east-1.amazonaws.com/iti-gp-project

## Step 8: Configure GitHub Webhook for Jenkins
In your GitHub repo, go to Settings → Webhooks → Add Webhook

Set:

Payload URL: http://<JENKINSNode_PUBLIC_IP>:32000/github-webhook/

Content type: application/json, Event: Just the push event

 This ensures Jenkins automatically triggers builds on new GitHub commits.

![Line](./Screenshots/Jenkinsfile.build//14.png)

## Running the pipeline to check building, testing, pushing and notifying on failure in any stage

**I) Making a push in the code file in github repo**

![Line](./Screenshots/Jenkinsfile.build//15.png)

**Here is the result**
- Part or the console output from smoke test section
![Line](./Screenshots/Jenkinsfile.build//16.png)

- The Pipeline flow
![Line](./Screenshots/Jenkinsfile.build//17.png)

- Checking the ECR repo 
![Line](./Screenshots/Jenkinsfile.build//18.png)

**II) Making a change in the code**

![Line](./Screenshots/Jenkinsfile.build//19.png)

**Here is the result**

- Part of the console output from smoke test section
![Line](./Screenshots/Jenkinsfile.build//20.png)


- The pipeline flow
![Line](./Screenshots/Jenkinsfile.build//21.png)


**III) Simulating an error in 'Docker Build' stage in pipeline to check notification**


![Line](./Screenshots/Jenkinsfile.build//22.png)

![Line](./Screenshots/Jenkinsfile.build//23.png)

![Line](./Screenshots/Jenkinsfile.build//24.png)

**IV) Simulating an error in 'Smoke Test' stage in pipeline to check notification**

![Line](./Screenshots/Jenkinsfile.build//25.png)

![Line](./Screenshots/Jenkinsfile.build//26.png)

![Line](./Screenshots/Jenkinsfile.build//27.png)


**V) Simulating an error in 'ECR Push' in pipeline to check notification**


![Line](./Screenshots/Jenkinsfile.build//28.png)


![Line](./Screenshots/Jenkinsfile.build//29.png)


![Line](./Screenshots/Jenkinsfile.build//30.png)
