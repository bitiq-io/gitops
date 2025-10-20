GitOps-managed NGINX static sites for multiple domains.

What this pack includes
- Deployment, Service, PVC in `bitiq-local` namespace.
- NGINX config with per-domain server blocks and apex→www redirects where desired.
- OpenShift Routes per domain with edge TLS and cert-manager issuer annotations.
- One-shot Job to seed placeholder index.html files into the PVC.

Files
- 0-configmap.yaml — nginx.conf (virtual hosts for cyphai.com, didgo.com, paulcapestany.com, bitiq.io, noelcapestany.com, beatricecapestany.com, ipiqi.com, neuance.net)
- 1-nginx.yaml — Deployment (mounts PVC at `/usr/share/nginx/html`)
- 2-service.yaml — ClusterIP Service
- 3-route-www.yaml — Route for www.cyphai.com
- 4/5/6/8/9/10/11-route-*.yaml — Routes for additional domains
- 7-static-site-pvc.yaml — PVC for static content
- 12-init-static-sites-job.yaml — seeds index.html per domain directory

Usage
1) Ensure DNS CNAMEs for each domain point to your cluster/router host.
2) Allow Argo CD to sync this folder (umbrella app `nginx-sites-local`).
3) The Job `init-static-sites` runs once to seed placeholders. To re-run, delete the Job and let Argo recreate it, or bump the Job name.
4) Place real content by writing into the PVC path matching each domain, for example:
   - `/usr/share/nginx/html/cyphai.com/index.html`
   - `/usr/share/nginx/html/didgo.com/index.html`

TLS
- Routes include `cert-manager.io/cluster-issuer: letsencrypt-http01-local`. Ensure cert-manager is installed and port 80 is reachable for HTTP-01.

