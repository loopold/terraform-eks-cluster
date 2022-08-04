# Setting up ExternalDNS for Services on AWS

Based on [this tutorial][1]


```sh
cd ..
export EKS_CLUSTER_NAME=$(terraform output -raw cluster_name)
export EKS_CLUSTER_REGION=$(terraform output -raw region)
cd -
```

## IAM Policy

Use `Z0425410QKKWCECMIJIU` ID instead of `*`
```sh
aws iam create-policy --policy-name "AllowExternalDNSUpdates" --policy-document file://policy.json

export POLICY_ARN=$(aws iam list-policies \
 --query 'Policies[?PolicyName==`AllowExternalDNSUpdates`].Arn' --output text)
```

If you already provisioned a cluster or use other provisioning tools like Terraform, you can use AWS CLI to attach the policy to the `Node IAM Role`.
```sh
# get managed node group name (assuming there's only one node group)
GROUP_NAME=$(aws eks list-nodegroups --cluster-name $EKS_CLUSTER_NAME --region $EKS_CLUSTER_REGION \
  --query nodegroups --out text)
# fetch role arn given node group name
NODE_ROLE_ARN=$(aws eks describe-nodegroup --cluster-name $EKS_CLUSTER_NAME \
  --region $EKS_CLUSTER_REGION --nodegroup-name $GROUP_NAME --query nodegroup.nodeRole --out text)
# extract just the name part of role arn
NODE_ROLE_NAME=${NODE_ROLE_ARN##*/}
```
If you have multiple node groups or any unmanaged node groups, the process gets more complex. 
See [here](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md#get-role-name-with-other-configurations)

```sh
# attach policy arn created earlier to node IAM role
aws iam attach-role-policy --role-name $NODE_ROLE_NAME --policy-arn $POLICY_ARN
```


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
kubectl create --filename externaldns-with-rbac.yaml \
  --namespace ${EXTERNALDNS_NS:-"default"}
```


## Verify ExternalDNS works (Service example)

```sh
NGINXDEMO_NS="nginx"
kubectl get namespaces | grep -q $NGINXDEMO_NS || kubectl create namespace $NGINXDEMO_NS

kubectl apply --filename nginx.yaml --namespace ${NGINXDEMO_NS:-"default"}

kubectl get service nginx --namespace ${NGINXDEMO_NS:-"default"}

# wait ~2 minutes
ZONE_ID=$(aws route53 list-hosted-zones-by-name --output json --dns-name "k8s.test.devopsvelocity.com." --query "HostedZones[0].Id" --out text)
aws route53 list-resource-record-sets --output json --hosted-zone-id $ZONE_ID  --query "ResourceRecordSets[?Name == 'nginx.k8s.test.devopsvelocity.com.']|[?Type == 'A']"
```


## Verify ExternalDNS works (Ingress example)
For this tutorial, we have two endpoints, the service with `LoadBalancer` type and an ingress.  For practical purposes, if an ingress is used, the service type can be changed to `ClusterIP` as two endpoints are unecessary in this scenario.

```sh
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace
# Error: Kubernetes cluster unreachable: exec plugin: invalid apiVersion "client.authentication.k8s.io/v1alpha1"
```
Fix is probably [here][2]

**If you don't have Helm** or if you prefer to use a YAML manifest, you can run the following command instead:
```sh
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.3.0/deploy/static/provider/cloud/deploy.yaml
```

Create an ingress resource manifest file named ingress.yaml with the contents below:

```sh
kubectl apply --filename ingress.yaml --namespace ${NGINXDEMO_NS:-"default"}

```

## Cleaning

`cd .. && terraform destroy` will remove cluster but process will stuck and finally time out
until you manually delete created Load Balancers and extra Security Groups.


[1]: https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md
[2]: https://stackoverflow.com/questions/72126048/circleci-message-error-exec-plugin-invalid-apiversion-client-authentication
