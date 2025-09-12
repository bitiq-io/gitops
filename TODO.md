# TODO

- Improve instructions for running locally.
- Note that `crc setup && crc start` may take a while to complete; highlight the web console URL and admin credentials.
- Document reliable login: `oc login -u kubeadmin -p PASSWORD https://api.crc.testing:6443` rather than relying on `crc console --credentials` output.
- Explain configuring `ARGOCD_HOST` and editing the Argo CD RBAC configmap before restarting the server and logging in with SSO.
- Add a second example microservice and wire App-of-Apps dependencies or convert the image bump to a Tekton PR flow that edits environment Helm values directly.
