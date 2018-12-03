# EKS-CLI

EKS cluster bootstrap with batteries included

## Highlights

* Supports creation of multiple node groups of different types with communication enabled between them
* Taint and label your nodegroups
* Authorize IAM users for cluster access 
* Manage IAM policies that will be attached to your nodes
* Easily configure docker repository secrets to allow pulling private images
* Manage Route53 DNS records to point at your Kubernetes services
* Export nodegroups to SporInst Elastigroups
* Auto resolving AMIs by region & instance types (GPU enabled AMIs)
* Even more...

## Usage

```
$ gem install eks_cli -v 0.2.4
$ eks create --cluster-name My-EKS-Cluster
$ eks create-nodegroup --cluster-name My-EKS-Cluster --group-name nodes --ssh-key-name <my-ssh-key> --yes
```

You can type `eks` in your shell to get the full synopsis of available commands

```bash
Commands:
  eks add-iam-user IAM_ARN                                     # adds an IAM user as an authorized member on the EKS cluster
  eks create                                                   # creates a new EKS cluster
  eks create-cluster-security-group                            # creates a SG for cluster communication
  eks create-cluster-vpc                                       # creates a vpc according to aws cloudformation template
  eks create-default-storage-class                             # creates default storage class on a new k8s cluster
  eks create-dns-autoscaler                                    # creates kube dns autoscaler
  eks create-eks-cluster                                       # create EKS cluster on AWS
  eks create-eks-role                                          # creates an IAM role for usage by EKS
  eks create-nodegroup                                         # creates all nodegroups on environment
  eks delete-nodegroup                                         # deletes cloudformation stack for nodegroup
  eks detach-iam-policies                                      # detaches added policies to nodegroup IAM Role
  eks enable-gpu                                               # installs nvidia plugin as a daemonset on the cluster
  eks export-nodegroup                                         # exports nodegroup auto scaling group to spotinst
  eks help [COMMAND]                                           # Describe available commands or one specific command
  eks scale-nodegroup --group-name=GROUP_NAME --max=N --min=N  # scales a nodegroup
  eks set-docker-registry-credentials USERNAME PASSWORD EMAIL  # sets docker registry credentials
  eks set-iam-policies --policies=one two three                # sets IAM policies to be attached to created nodegroups
  eks set-inter-vpc-networking TO_VPC_ID TO_SG_ID              # creates a vpc peering connection, sets route tables and allows network access on SG
  eks show-config                                              # print cluster configuration
  eks update-auth                                              # update aws auth configmap to allow all nodegroups to connect to control plane
  eks update-dns HOSTNAME K8S_SERVICE_NAME                     # alters route53 CNAME records to point to k8s service ELBs
  eks version                                                  # prints eks_cli version
  eks wait-for-cluster                                         # waits until cluster responds to HTTP requests

Options:
  c, --cluster-name=CLUSTER_NAME 
```

## Prerequisites

1. Ruby
2. [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) version >= 10 on your `PATH`
3. [aws-iam-authenticator](https://github.com/kubernetes-sigs/aws-iam-authenticator) on your `PATH`
4. [aws-cli](https://docs.aws.amazon.com/cli/latest/userguide/installing.html) version >= 1.16.18 on your `PATH`

## Selected Commands

### Creating more than a single nodegroup

Nodegroups are created separately from the cluster. 

You can use `eks create-nodegroup` multiple times to create several nodegroups with different instance types and number of workers.
Nodes in different nodegroups may communicate freely thanks to a shared Security Group.

## Scaling nodegroups

Scale nodegroups up and down using

`$ eks scale-nodegroup --cluster-name My-EKS-Cluster --group-name nodes --min 1 --max 10`

### Authorize an IAM user to access the cluster

`$ eks add-iam-user arn:aws:iam::XXXXXXXX:user/XXXXXXXX --cluster-name=My-EKS-Cluster --yes`

Edits `aws-auth` configmap and updates it on EKS to allow an IAM user access the cluster via `kubectl`

### Setting IAM policies to be attached to EKS nodes

`$ eks set-iam-policies --cluster-name=My-EKS-Cluster --policies=AmazonS3FullAccess AmazonDynamoDBFullAccess`

Sets IAM policies to be attached to nodegroups once created.
This settings does not work retro-actively - only affects future `eks create-nodegroup` commands.

### Routing Route53 hostnames to Kubernetes service

`$ eks update-dns my-cool-service.my-company.com cool-service --route53-hosted-zone-id=XXXXX --elb-hosted-zone-id=XXXXXX --cluster-name=My-EKS-Cluster`

Takes the ELB endpoint from `cool-service` and puts it as an alias record of `my-cool-service.my-company.com` on Route53

### Enabling GPU

`$ eks enable-gpu --cluster-name EKS-Staging`

Installs the nvidia device plugin required to have your GPUs exposed

*Assumptions*: 

1. You have a nodegroup using [EKS GPU AMI](https://docs.aws.amazon.com/eks/latest/userguide/eks-optimized-ami.html)
2. This nodegroup uses a GPU instance (p2.x / p3.x etc)

### Adding Dockerhub Secrets

`$ eks set-docker-registry-credentials <dockerhub-user> <dockerhub-password> <dockerhub-email> --cluster-name My-EKS-Cluster`

Adds your dockerhub credentials as a secret and attaches it to the default ServiceAccount's imagePullSecrets

### Creating Default Storage Class

`$ eks create-default-storage-class --cluster-name My-EKS-Cluster`

Creates a standard gp2 default storage class named gp2

### Installing DNS autoscaler

`$ eks create-dns-autoscaler --cluster-name My-EKS-Cluster`

Creates kube-dns autoscaler with sane defaults

### Connecting to an existing VPC

`$ eks set-inter-vpc-networking VPC_ID SG_ID`

Assuming you have some shared resources on another VPC (an RDS instance for example), this command opens communication between your new EKS cluster and your old VPC:

1. Creating and accepting a VPC peering connection from your EKS cluster VPC to the old VPC
2. Setting route tables on both directions to allow communication
3. Adding an ingress rule to SG_ID to accept all communication from your new cluster nodes.

### Exporting nodegroups to Spotinst

`$ eks export-nodegroup --group-name=other-nodes`

Exports the corresponding Auto Scaling Group to a Spotinst Elastigroup

Requires the following environment variables to be set:
* SPOTINST_ACCOUNT_ID
* SPOTINST_API_TOKEN

## Contributing

Is more than welcome! ;)
