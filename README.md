# EKS-CLI

EKS cluster bootstrap with batteries included

## Usage

```
$ gem install eks_cli
$ eks bootstrap us-west-2 --cluster-name=My-EKS-Cluster
$ eks create-cluster-vpc --cluster-name=My-EKS-Cluster
$ eks create-cluster-security-group --cluster-name My-EKS-Cluster --open-ports=22
$ eks create-nodegroup --cluster-name My-EKS-Cluster --group-name nodes --ssh-key-name my-ssh-key --min 1 --max 3
$ eks create-nodegroup --cluster-name My-EKS-Cluster --group-name other-nodes --ssh-key-name my-ssh-key --min 3 --max 3 --instance-type m5.2xlarge
$ eks create-nodegroup --all --cluster-name My-EKS-Cluster --yes
```

## Extra Stuff

### Setting IAM policies to be attached to EKS nodes

`$ eks set-iam-policies --cluster-name=My-EKS-Cluster --policies=AmazonS3FullAccess AmazonDynamoDBFullAccess`

### Routing Route53 hostnames to Kubernetes service

`$ eks update-dns my-cool-service.my-company.com cool-service --route53-hosted-zone-id=XXXXX --elb-hosted-zone-id=XXXXXX --cluster-name=My-EKS-Cluster`

### Enabling GPU

`$ eks enable-gpu --cluster-name EKS-Staging`

### Adding Dockerhub Secrets

`$ eks set-docker-registry-credentials <dockerhub-user> <dockerhub-email> <dockerhub-password> --cluster-name My-EKS-Cluster`

### Creating Default Storage Class

`$ eks create-default-storage-class --cluster-name My-EKS-Cluster`
