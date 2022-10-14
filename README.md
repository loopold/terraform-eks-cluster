# Provision and setting up ExternalDNS for Services on AWS

## Description

This is a work in progress.

This repo is a companion repo to the [Provision an EKS Cluster learn guide][1], containing
Terraform configuration files to provision an EKS cluster on AWS.
Based on Setting up ExternalDNS for Services on AWS [tutorial][2] and AWS Load Balancer Controller [Installation guide][4].

---

## Deploy an EKS Cluster

After `terraform apply` add a new context to the `~/.kube/config` file.
```sh
export EKS_CLUSTER_NAME=$(terraform output -raw cluster_name)
export EKS_CLUSTER_REGION=$(terraform output -raw region)
aws eks --region $EKS_CLUSTER_REGION update-kubeconfig --name $EKS_CLUSTER_NAME
```
Other variables
```sh
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
```

---

## IAM Policy

```sh
aws iam create-policy --policy-name "AllowExternalDNSUpdates" --policy-document file://enternal-dns-policy.json

export POLICY_ARN=$(aws iam list-policies --query 'Policies[?PolicyName==`AllowExternalDNSUpdates`].Arn' --output text)
```

If you already provisioned a cluster or use other provisioning tools like Terraform, you can use AWS CLI to attach the policy to the `Node IAM Role`.
```sh
# get managed node group name (assuming there's only one node group)
GROUP_NAME=$(aws eks list-nodegroups --cluster-name $EKS_CLUSTER_NAME --region $EKS_CLUSTER_REGION   --query nodegroups --out text)
# fetch role arn given node group name
NODE_ROLE_ARN=$(aws eks describe-nodegroup --cluster-name $EKS_CLUSTER_NAME --region $EKS_CLUSTER_REGION --nodegroup-name $GROUP_NAME --query nodegroup.nodeRole --out text)
# extract just the name part of role arn
NODE_ROLE_NAME=${NODE_ROLE_ARN##*/}
```
If you have multiple node groups or any unmanaged node groups, the process gets more complex. 
See [here][5]

```sh
# attach policy arn created earlier to node IAM role - check policy usage
aws iam attach-role-policy --role-name $NODE_ROLE_NAME --policy-arn $POLICY_ARN
```

---

## Deploy ExternalDNS

You can check if your cluster has RBAC by `kubectl api-versions | grep rbac.authorization.k8s.io`

```sh
export EXTERNALDNS_NS="default" # externaldns, kube-addons, etc

# create namespace if it does not yet exist
kubectl get namespaces | grep -q $EXTERNALDNS_NS || \
  kubectl create namespace $EXTERNALDNS_NS
```

### Manifest (for clusters with RBAC enabled)
Create, customize and, when ready, deploy:
```sh
kubectl apply -f external-dns-with-rbac.yaml -n ${EXTERNALDNS_NS:-"default"}
```

---

## Install cert-manager

We are not going to use the cert-manager for now. Go to the [next section](#aws-load-balancer-controller)

> ALB only supports ACM certificates. You need to upload certificate to ACM or you can create certs with AWS.

Set a version. Latest release is [here][7]:
```sh
export CERTMGRVER="v1.9.1"
export EKS_VPC_ID=$(AWS_REGION=$EKS_CLUSTER_REGION aws ec2 describe-vpcs --filter Name=tag:Name,Values=${EKS_CLUSTER_NAME/eks/vpc} --query "Vpcs[].VpcId" --output text)
```

### Via helm

```sh
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version $CERTMGRVER \
  --set installCRDs=true \
  --set region=$EKS_CLUSTER_REGION \
  --set vpcId=$EKS_VPC_ID
```

### Via manifest (refresh the command)
```sh
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.5.3/cert-manager.yaml
```

---

## AWS Load Balancer Controller

If you do not use `eksctl`, you need to ensure worker nodes security group permit access to TCP port 9443 from the kubernetes control plane for the webhook access. 

Edit inbound rules in sg: `education-eks-node` and add port 9443 for `education-eks-cluster` and outbound rules in the same sg - add port 80 to the world (`0/0`).

Set a version. Latest release is [here][6]:
```sh
export ALBCTRLVER="v2.4.4"
```

### Check metadata server version 2 (IMDSv2)

#### Skip it for now.

Instead of depending on IMDSv2, you alternatively may specify the AWS region and the VPC via the controller flags `--aws-region` and `--aws-vpc-id`
```sh
aws ec2 describe-instances --region $EKS_CLUSTER_REGION --instance-id i-0a19f22bfeb4e1464 --query "Reservations[0].Instances[0].MetadataOptions" | jq .
```
Server does not require IMDSv2 if `HttpTokens` is `optional`. If it is `required` you must set the hop limit to 2 (or more) in order to allow the AWS Load Balancer Controller to perform the metadata introspection.
```sh
aws ec2 modify-instance-metadata-options --http-put-response-hop-limit 2 --region $EKS_CLUSTER_REGION --instance-id i-0a19f22bfeb4e1464 ### 3
```

### IAM Permissions

The creation of the IAM OIDC provider was done with Terraform.

Download IAM policy for the AWS Load Balancer Controller and create role
```sh
curl -o lb-controller-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/$ALBCTRLVER/docs/install/iam_policy.json
aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://lb-controller-policy.json
```

ServiceAccount will be created in next step by Helm.

### Add Controller to Cluster

#### Via Helm
Note. The `helm install` command automatically applies the CRDs, but `helm upgrade` doesn't.

If you are setting `enableCertManager: true` you need to have installed cert-manager and it's CRDs before installing this chart; to install cert-manager follow the installation guide.

Helm install command for clusters with IRSA:
```sh
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system \
  --set clusterName=$EKS_CLUSTER_NAME \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  # --set enableCertManager=true

kubectl get sa -A | grep balancer
kubectl describe sa aws-load-balancer-controller -n kube-system
```

Attach policy to the role (do we need create a new one?) - creation of `$NODE_ROLE_NAME` is described [above](#iam-policy).
```sh
export LB_POLICY_ARN=arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy
aws iam attach-role-policy --role-name $NODE_ROLE_NAME --policy-arn $LB_POLICY_ARN
```

#### Via YAML manifests
Download spec for load balancer controller.
```sh
curl -o lb-controller.yaml -L "https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/download/${ALBCTRLVER}/${ALBCTRLVER//./_}_full.yaml"
```

Edit saved yaml (`--cluster-name=$EKS_CLUSTER_NAME`)
```sh
sed -i "s/--cluster-name=.*/--cluster-name=$EKS_CLUSTER_NAME/" lb-controller.yaml
# if macOS: 
sed -i "" "s/--cluster-name=.*/--cluster-name=$EKS_CLUSTER_NAME/" lb-controller.yaml
```
Apply
```sh
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"
kubectl apply -f lb-controller.yaml
```

#### Troubleshooting

Error `error: unable to recognize "v2_4_1_full.yaml": no matches for kind "IngressClassParams" in version "elbv2.k8s.aws/v1beta1"` can be solved by update the CRDs as below and then re-apply:
```sh
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"
```

Error from server (InternalError): error when creating "ingress.yaml": Internal error occurred: failed calling webhook "vingress.elbv2.k8s.aws": Post "https://aws-load-balancer-webhook-service.kube-system.svc:443/validate-networking-v1-ingress?timeout=10s": context deadline exceeded

```sh
  "ports": [
                {
                    "name": "webhook-server",
                    "containerPort": 9443,
                    "protocol": "TCP"
                }
            ],
```

---

## Deploy an app

### Service
```sh
kubectl apply -f service.yaml
```
### Deployment
```sh
kubectl apply -f deployment.yaml
```
### Ingress
```sh
kubectl apply -f ingress-tls.yaml
```

---

## Cleaning

Run `aws iam detach-role-policy` for `AWSLoadBalancerControllerIAMPolicy`

`terraform destroy` will remove cluster but the process may get stuck and finally time out
until you manually delete created Load Balancers and extra Security Groups (`k8s.*`).



[1]: https://learn.hashicorp.com/terraform/kubernetes/provision-eks-cluster
[2]: https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md
[3]: https://stackoverflow.com/questions/72126048/circleci-message-error-exec-plugin-invalid-apiversion-client-authentication
[4]: https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.4/deploy/installation/
[5]: https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md#get-role-name-with-other-configurations
[6]: https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases
[7]: https://github.com/cert-manager/cert-manager/releases
