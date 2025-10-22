## Cluster Installation

make sure .gitignore has "clusters/aws/auth/kubeconfig" in it

Process takes ~30min

```shell
cd clusters/wtf
cp ../pac-config/install-config.yaml .
openshift-install create cluster --dir . --log-level=info
```

https://console-openshift-console.apps.wtf.bitiq.io/dashboards

### Install ODF

Setting up StorageSystem:
use an existing StorageClass (gp3)
use Ceph RBD as the default StorageClass

disable noobaa
```
oc edit storagecluster ocs-storagecluster -n openshift-storage
```
add (under "spec"):
```
  multiCloudGateway:
    reconcileStrategy: "ignore"
```

```shell
oc scale deployment noobaa-operator --replicas=0 -n openshift-storage
oc scale statefulset noobaa-core --replicas=0 -n openshift-storage
oc scale deployment noobaa-db --replicas=0 -n openshift-storage
oc delete statefulset noobaa-db-pg -n openshift-storage
oc delete deployment noobaa-endpoint -n openshift-storage

oc delete noobaa noobaa -n openshift-storage

oc patch -n openshift-storage  noobaas.noobaa.io/noobaa --type=merge -p '{"metadata": {"finalizers":null}}'
```

### Install other Operators

Lightspeed
NFD
cert-manager


### strfry

```shell
cd /Users/pac/repos/github.com/PaulCapestany/pac-infra/clusters/pac-config/z-initial-setup
oc apply -f 0-default-serviceaccount.yaml
oc apply -f 01-quay-secret.yaml

cd ../services/strfry
oc apply -f .
```

### Couchbase 

Install Couchbase Autonomous Operator https://docs.couchbase.com/operator/current/install-openshift.html
NOTE: check that we're using most-current vertsion of macOS install tool as well as latest release of couchbase server (https://www.couchbase.com/downloads/?family=couchbase-server)
```shell
cd /Users/pac/repos/github.com/bitiq-io/gitops/pac-config/services/couchbase-autonomous-operator_2.8.1-164-openshift-linux-amd64
oc create -f crd.yaml && oc create secret docker-registry rh-catalog --docker-server=registry.connect.redhat.com --docker-username=paulcapestany --docker-password=woss2few-PSAF.ai --docker-email=capestany@gmail.com && bin/cao create admission --image-pull-secret rh-catalog && bin/cao create operator --image-pull-secret rh-catalog

cd ../couchbase
oc apply -f .
```

to access couchbase dashboard locally:
```sh
while true; do kubectl port-forward couchbase-cluster-0000 8091:8091; echo "Lost connection"; sleep 1; done
```


NOTE: setting podSecurityContext was key to getting CAO to actually deploy Couchbase clusters on OpenShift ODF

Most ODF Storage Systems (ceph-rbd, and not-non-resilient-sc) are fully able to run fine with just 3 m6i.xlarge nodes located in different zones (cephfs requires one extra node due to CPU constraints supposedly, noobaa object store stuff requires even more, but, we're not using that)



### nostr-services

```shell
cd /Users/pac/repos/github.com/PaulCapestany/pac-infra/clusters/pac-config/services/nostouch
oc apply -f 0-deployment-stream.yaml
```

create all couchbase indices and eventing functions

```sql
CREATE INDEX kind_and_event_lookup ON `default`:`all-nostr-events`.`_default`.`_default`(`kind`,(distinct (array (`t`[1]) for `t` in `tags` when ((`t`[0]) = "e") end))) PARTITION BY HASH(META().id) WITH {"num_replica": 1}

CREATE INDEX thread_by_any_message_id_lookup ON `default`:`dev-threads`.`_default`.`_default`(DISTINCT ARRAY message.id FOR message IN messages END) PARTITION BY HASH(META().id) WITH {"num_replica": 1}


```

nostr_query has dev-threads-fts-index.json
nostr_threads has nostr_threads_event_func.json
nostr_ai has dev-nostr-ai-eventing-func.json


```shell
cd /Users/pac/repos/github.com/PaulCapestany/pac-infra/clusters/pac-config/services/nostr_threads
oc apply -f dev-0-service.yaml && oc apply -f dev-1-deployment.yaml
```

```shell
cd /Users/pac/repos/github.com/PaulCapestany/pac-infra/clusters/pac-config/services/nostr_query
oc apply -f .
```

need to find the default router being used via (should be something like a913962e9e4a8411082aff5cd924ebbe-1432670166.us-east-1.elb.amazonaws.com):
```shell
oc -n openshift-ingress get service router-default
```

then need to add dev.bitiq.io A record (using alias) to include the load balancer https://us-east-1.console.aws.amazon.com/route53/v2/hostedzones?region=us-east-1#ListRecordSets/ZPCVSGRXCIK5E


```shell
cd /Users/pac/repos/github.com/PaulCapestany/pac-infra/clusters/pac-config/services/nostr_site
oc apply -f dev-0-service.yaml && oc apply -f dev-1-site-deployment.yaml
```

need to install NFD operator and GPUs

make edits to worker-gpu.yaml (for more NIM compatability check https://docs.nvidia.com/nim/large-language-models/latest/supported-models.html)
- change machineset throughout (e.g. "wtf-hjvjz")
- edit AMI
- change instance type if needed (good for comparing instance types: https://instances.vantage.sh/)

set up worker-gpu
```shell
cd /Users/pac/repos/github.com/PaulCapestany/pac-infra/clusters/pac-config/services/gpu/other
oc apply -f worker-gpu-small.yaml && oc apply -f label-gpu-storage.yaml

```

Install nvidia-gpu-operator https://docs.nvidia.com/datacenter/cloud-native/openshift/latest/prerequisites.html 

```shell
oc create configmap nvidia-dcgm-exporter-dashboard -n openshift-config-managed --from-file=dcgm-exporter-dashboard.json && oc label configmap nvidia-dcgm-exporter-dashboard -n openshift-config-managed "console.openshift.io/dashboard=true"

cd /Users/pac/repos/github.com/PaulCapestany/pac-infra/clusters/pac-config/services/gpu/other
oc apply -f nvidia-cluster-policy.yaml

# can take a few minutes... sanity-check that GPUs are detected and working
oc get pods,daemonset -n nvidia-gpu-operator
oc exec -n nvidia-gpu-operator -it pod/nvidia-driver-daemonset-418.94.202503061016-0-xpd6m -- nvidia-smi
```

deploy ollama

```sh
cd /Users/pac/repos/github.com/PaulCapestany/pac-infra/clusters/pac-config/services/gpu/other
oc apply -f ollama.yaml

oc exec -n ollama -ti ollama-c4b9ccfb9-97zdk -- bash
ollama pull nomic-embed-text
ollama pull mxbai-embed-large
```



```shell
cd /Users/pac/repos/github.com/PaulCapestany/pac-infra/clusters/pac-config/services/nostr_ai
oc apply -f .
```

if i need to delete a bucket without deleting indexes:
```sql
DELETE FROM `dev-threads`;
```


### cert-manager

installed red hats cert-manager operator


update DNS (A/CNAME) records on Route 53 to point to whatever LoadBalancer openshift-ingress is using (e.g. a988bef8340b14626a0daa362ce183bb-1295891857.us-east-1.elb.amazonaws.com) via:
```sh
oc describe ingresscontroller <ingresscontroller-name> -n openshift-ingress-operator
oc -n openshift-ingress get service router-default
```

next:

```sh
cd /Users/pac/repos/github.com/PaulCapestany/pac-infra/clusters/pac-config/services/web

# Create policy document (save the JSON above as cert-manager-route53-policy.json)
aws iam create-policy \
  --policy-name CertManagerRoute53 \
  --policy-document file://cert-manager-route53-policy.json

# Create IAM user for cert-manager
aws iam create-user --user-name cert-manager

# Attach policy to the user
aws iam attach-user-policy \
  --user-name cert-manager \
  --policy-arn arn:aws:iam::078220466467:policy/CertManagerRoute53

# Create access key for the user
aws iam create-access-key --user-name cert-manager
```

create k8s secret:

```sh
# Create cert-manager namespace (if not already created by the operator)
oc create namespace cert-manager

# Create secret with AWS credentials
oc create secret generic route53-credentials-secret \
  --from-literal=aws_access_key_id=<AWS_ACCESS_KEY_ID> \
  --from-literal=aws_secret_access_key=<AWS_SECRET_ACCESS_KEY> \
  -n cert-manager

```



create cluster-issuer and certs:

```sh
cd /Users/pac/repos/github.com/PaulCapestany/pac-infra/clusters/pac-config/z-initial-setup

oc apply -f cluster-issuer.yaml

oc apply -f certs.yaml
```

monitor:

```sh
oc get certificate -n openshift-ingress
NAME                     READY   SECRET                  AGE
bitiq-io-cert            False   bitiq-io-tls            10m
dev-bitiq-io-cert        True    dev-bitiq-io-tls        10m
ipiqi-com-cert           True    ipiqi-com-tls           10m
paulcapestany-com-cert   True    paulcapestany-com-tls   10m
```

allow router to read certs and then apply routes:
```sh
oc apply -f router-rbac.yaml

oc apply -f 3-routes.yaml
```


```sh
oc get routes -A
```


### nginx static sites

not sure why but have to manually copy each domain's certificate and key (e.g. from paulcapestany-com-tls) into route (e.g. paulcapestany-com-route). remember that http01 ACME challange cannot handle wildcards for subdomains (only dns01 can).

NOTE: after 90 days the TLS certs did not get autoreplaced with the externally managed cert approach 

to get files for static sites over to pod:
```sh
cd /Users/pac/repos/github.com/PaulCapestany/fileserver_updated_files
oc rsync ./public/ nginx-deployment-7b6fdb77fd-v4ggk:/usr/share/nginx/html/ -n default

oc exec -it nginx-deployment-87c58fdc5-fdcpm -- bash -c "find /usr/share/nginx/html -type d -exec chmod 755 {} \; && find /usr/share/nginx/html -type f -exec chmod 644 {} \; && echo 'All permissions fixed successfully'"
```




### Install Nvidia NIM Operator

https://docs.nvidia.com/nim-operator/latest/ 

???: https://docs.nvidia.com/nim-operator/latest/install-openshift.html

```shell
oc create secret -n openshift-operators docker-registry ngc-secret \
    --docker-server=nvcr.io \
    --docker-username=\$oauthtoken \
    --docker-password=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

oc create secret -n openshift-operators generic ngc-api-secret \
    --from-literal=NGC_API_KEY=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   

# see available images from nvidia...$$
ngc registry image list


oc get nimcaches.apps.nvidia.com -n openshift-operators \
    llama-3.2-nv-embedqa-1b-v2 -o=jsonpath="{.status.profiles}" | jq .
```

https://build.nvidia.com/search?q=embed

nvcr.io/nim/snowflake/arctic-embed-l:1.0.1

https://www.nvidia.com/en-us/data-center/free-trial-nvidia-ai-enterprise/

https://docs.api.nvidia.com/nim/reference/nvidia-llama-3_2-nv-embedqa-1b-v2-infer

https://build.nvidia.com/nvidia/llama-3_2-nv-embedqa-1b-v2/modelcard

max tokens: 8092

curl --request POST \
     --url http://llama-3-2-nv-embedqa-1b-v2.openshift-operators.svc.cluster.local:8000/v1/embeddings \
     --header 'accept: application/json' \
     --header 'content-type: application/json' \
     --data '
{
  "model": "nvidia/llama-3.2-nv-embedqa-1b-v2",
  "encoding_format": "float",
  "truncate": "true",
  "input_type": "passage",
  "input": "blahgasd",
  "user": "na"
}
'


vector size: 1024
max tokens: 512

https://build.nvidia.com/snowflake/arctic-embed-l/modelcard

curl --request POST \
     --url http://arctic.openshift-operators.svc.cluster.local:8000/v1/embeddings \
     --header 'accept: application/json' \
     --header 'content-type: application/json' \
     --data '
{
  "model": "snowflake/arctic-embed-l",
  "encoding_format": "float",
  "truncate": "END",
  "input_type": "passage",
  "input": "test"
}
'


### ollama

TODO: see if it makes sensee to use this at some point: https://github.com/nekomeowww/ollama-operator 

```shell
oc apply -f https://raw.githubusercontent.com/nekomeowww/ollama-operator/main/dist/install.yaml
go install github.com/nekomeowww/ollama-operator/cmd/kollama@latest
```



## Cluster Deletion


```sh
cd /Users/pac/repos/github.com/PaulCapestany/pac-infra/clusters/wtf
openshift-install destroy cluster --dir . --log-level=info
```
need to get rid of both *.apps.wtf.bitiq.io and api.wtf.bitiq.io A records at https://us-east-1.console.aws.amazon.com/route53/v2/hostedzones?region=us-east-1#ListRecordSets/ZPCVSGRXCIK5E 

 
also delete s3 buckets
 