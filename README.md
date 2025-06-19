# homelab

brew install siderolabs/tap/talosctl kubectl helm helmfile

talosctl gen config ramiel-cluster https://10.1.1.30:6443 \
  --install-image factory.talos.dev/nocloud-installer/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b:v1.10.4 \
  --with-secrets secrets.yaml \
  --config-patch @patches/cni.yaml \
  --config-patch @patches/disable-kube-proxy.yaml \
  --config-patch @patches/install-disk.yaml \
  --config-patch @patches/interface-names.yaml \
  --config-patch-control-plane @patches/vip.yaml \
  --output out/

mkdir -p ~/.talos
cp out/talosconfig ~/.talos/config

talosctl apply-config --insecure -n 10.1.1.31 -f out/controlplane.yaml
talosctl apply-config --insecure -n 10.1.1.32 -f out/controlplane.yaml
talosctl apply-config --insecure -n 10.1.1.33 -f out/controlplane.yaml

talosctl apply-config --insecure -n 10.1.1.41 -f out/worker.yaml
talosctl apply-config --insecure -n 10.1.1.42 -f out/worker.yaml
talosctl apply-config --insecure -n 10.1.1.43 -f out/worker.yaml

talosctl config endpoint 10.1.1.31 10.1.1.32 10.1.1.33
talosctl config node 10.1.1.31
talosctl config contexts

talosctl bootstrap
talosctl get members -n 10.1.1.31
talosctl kubeconfig -n 10.1.1.31

kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.3.0/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.3.0/config/crd/standard/gateway.networking.k8s.io_gateways.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.3.0/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.3.0/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.3.0/config/crd/standard/gateway.networking.k8s.io_grpcroutes.yaml

kubectl apply --server-side -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.26/releases/cnpg-1.26.0.yaml
