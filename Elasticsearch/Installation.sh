## install podman 
#!/bin/bash
sudo dnf  update -y      
sudo dnf install -y podman
sudo systemctl enable --now podman.socket
sudo usermod -aG podman $USER
newgrp podman
podman --version
echo "Podman installation completed."

## install buildah
sudo dnf install -y buildah
buildah --version
echo "Buildah installation completed."

## install skopeo
sudo dnf install -y skopeo
skopeo --version
echo "Skopeo installation completed."

echo "All installations completed successfully."

####################
# Create directories
sudo mkdir -p /opt/elasticsearch/{data,config,certs}
sudo mkdir -p /etc/containers/systemd/

# Set permissions (adjust UID/GID as needed - ES runs as 1000:1000)
sudo chown -R 1000:1000 /opt/elasticsearch/data
sudo chmod 755 /opt/elasticsearch/certs


#Create /opt/elasticsearch/config/elasticsearch.yml on each VM. Customize node.name and network.publish_host for each node.
# node1:

cat <<EOF | sudo tee /opt/elasticsearch/config/elasticsearch.yml
cluster.name: es-cluster
node.name: node1

network.host: 0.0.0.0
network.publish_host: 192.168.100.57
http.port: 9200
transport.port: 9300

discovery.seed_hosts:
  - 192.168.100.57:9300
  - 192.168.100.58:9300
  - 192.168.100.59:9300

cluster.initial_master_nodes:
  - node1
  - node2
  - node3


# TLS Configuration
xpack.security.enabled: true
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.keystore.path: /usr/share/elasticsearch/config/certs/node1.jks
xpack.security.transport.ssl.keystore.password: password
xpack.security.transport.ssl.truststore.path: /usr/share/elasticsearch/config/certs/truststore.jks
xpack.security.transport.ssl.truststore.password: password

xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.keystore.path: /usr/share/elasticsearch/config/certs/node1.jks
xpack.security.http.ssl.keystore.password: password
xpack.security.http.ssl.truststore.path: /usr/share/elasticsearch/config/certs/truststore.jks
xpack.security.http.ssl.truststore.password: password

# Additional security
xpack.security.authc.api_key.enabled: true
xpack.security.authc.anonymous.username: anonymous_user
xpack.security.authc.anonymous.roles: monitoring_role
xpack.security.authc.anonymous.authz_exception: false

# Performance settings
bootstrap.memory_lock: true

# Reduce circuit breaker limits if still having issues
indices.breaker.total.limit: 70%
indices.breaker.fielddata.limit: 40%
indices.breaker.request.limit: 40%

# Reduce query cache if memory constrained
indices.queries.cache.size: 5%

# Limit thread pools
thread_pool.write.queue_size: 500
thread_pool.search.queue_size: 500

EOF
echo "Elasticsearch configuration file created."

# node2:
cat <<EOF | sudo tee /opt/elasticsearch/config/elasticsearch.yml
cluster.name: es-cluster
node.name: node2

network.host: 0.0.0.0
network.publish_host: 192.168.100.58
http.port: 9200
transport.port: 9300

discovery.seed_hosts:
  - 192.168.100.57:9300
  - 192.168.100.58:9300
  - 192.168.100.59:9300

cluster.initial_master_nodes:
  - node1
  - node2
  - node3

# TLS Configuration
xpack.security.enabled: true
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.keystore.path: /opt/elasticsearch/certs/node2.jks
xpack.security.transport.ssl.keystore.password: password
xpack.security.transport.ssl.truststore.path: /opt/elasticsearch/certs/truststore.jks
xpack.security.transport.ssl.truststore.password: password

xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.keystore.path: /opt/elasticsearch/certs/node2.jks
xpack.security.http.ssl.keystore.password: password
xpack.security.http.ssl.truststore.path: /opt/elasticsearch/certs/truststore.jks
xpack.security.http.ssl.truststore.password: password

# Additional security
xpack.security.authc.api_key.enabled: true
xpack.security.authc.anonymous.username: anonymous_user
xpack.security.authc.anonymous.roles: monitoring_role
xpack.security.authc.anonymous.authz_exception: false

# Performance settings
bootstrap.memory_lock: true

# Reduce circuit breaker limits if still having issues
indices.breaker.total.limit: 70%
indices.breaker.fielddata.limit: 40%
indices.breaker.request.limit: 40%

# Reduce query cache if memory constrained
indices.queries.cache.size: 5%

# Limit thread pools
thread_pool.write.queue_size: 500
thread_pool.search.queue_size: 500
EOF

# node3:
cat <<EOF | sudo tee /opt/elasticsearch/config/elasticsearch.yml
cluster.name: es-cluster
node.name: node3

network.host: 0.0.0.0
network.publish_host: 192.168.100.59
http.port: 9200
transport.port: 9300

discovery.seed_hosts:
  - 192.168.100.57:9300
  - 192.168.100.58:9300
  - 192.168.100.59:9300

cluster.initial_master_nodes:
  - node1
  - node2
  - node3

# TLS Configuration
xpack.security.enabled: true
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.keystore.path: /usr/share/elasticsearch/config/certs/node3.jks
xpack.security.transport.ssl.keystore.password: password
xpack.security.transport.ssl.truststore.path: /usr/share/elasticsearch/config/certs/truststore.jks
xpack.security.transport.ssl.truststore.password: password

xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.keystore.path: /usr/share/elasticsearch/config/certs/node3.jks
xpack.security.http.ssl.keystore.password: password
xpack.security.http.ssl.truststore.path: /usr/share/elasticsearch/config/certs/truststore.jks
xpack.security.http.ssl.truststore.password: password

# Additional security
xpack.security.authc.api_key.enabled: true
xpack.security.authc.anonymous.username: anonymous_user
xpack.security.authc.anonymous.roles: monitoring_role
xpack.security.authc.anonymous.authz_exception: false

# Performance settings
bootstrap.memory_lock: true

# Reduce circuit breaker limits if still having issues
indices.breaker.total.limit: 70%
indices.breaker.fielddata.limit: 40%
indices.breaker.request.limit: 40%

# Reduce query cache if memory constrained
indices.queries.cache.size: 5%

# Limit thread pools
thread_pool.write.queue_size: 500
thread_pool.search.queue_size: 500

EOF
echo "Elasticsearch configuration file created."

# Create /etc/containers/systemd/elasticsearch.container on each VM:
cat <<EOF | sudo tee /etc/containers/systemd/elasticsearch.container
[Unit]
Description=Elasticsearch 8.16 Container
After=network-online.target
Wants=network-online.target

[Container]
Image=docker.elastic.co/elasticsearch/elasticsearch:8.16.0
ContainerName=elasticsearch

# Environment variables
Environment=ES_JAVA_OPTS=-Xms4g -Xmx4g
Environment=ELASTIC_PASSWORD=Passw0rd!
Environment=discovery.type=multi-node
Environment=bootstrap.memory_lock=true

# Volume mounts
Volume=/opt/elasticsearch/data:/usr/share/elasticsearch/data:Z
Volume=/opt/elasticsearch/config/elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml:Z,ro
Volume=/opt/elasticsearch/certs:/usr/share/elasticsearch/config/certs:Z,ro

# Network configuration
#Network=host
# PORTS - Use explicit binding to all interfaces
PublishPort=0.0.0.0:9200:9200/tcp
PublishPort=0.0.0.0:9300:9300/tcp

# Add memory limits to prevent runaway memory usage
# Set to 80-90% of VM RAM
PodmanArgs=--memory=6g
PodmanArgs=--memory-swap=6g

# Security options
SecurityLabelDisable=false
NoNewPrivileges=false

# Ulimits
Ulimit=memlock=-1:-1
Ulimit=nofile=65535:65535

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target default.target

EOF
echo "Podman systemd unit file for Elasticsearch created."

# Reload systemd to pick up the Quadlet file
sudo systemctl daemon-reload

# Start and enable the service
sudo systemctl start elasticsearch
sudo systemctl enable elasticsearch

# Check status
sudo systemctl status elasticsearch

# View logs
sudo journalctl -u elasticsearch.service -f

##Verify Cluster Health
# On any VM
curl -k -u elastic:Passw0rd! \
  https://localhost:9200/_cluster/health?pretty

# Check nodes
curl -k -u elastic:Passw0rd! \
  https://localhost:9200/_cat/nodes?v

echo "Elasticsearch Podman container setup completed."


sudo firewall-cmd --permanent --add-port=9200/tcp
sudo firewall-cmd --permanent --add-port=9300/tcp
sudo firewall-cmd --reload

