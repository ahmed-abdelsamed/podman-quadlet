# **Redis HA Cluster with Podman & Quadlet on 3 VMs**

## **📊 Architecture Overview**

##########
setup and configured redis 8.6 HA on 3 podman on 3 VMs rocky linux 9 and nodes: {redis-node1: 192.168.100.63, redis-node2:192.168.100.64, redis-node3:192.168.100.65} ,
Create Podman secrets for the certificates

Create Podman voulume for redis_data, redis_logs, redis_conf and sentinel_data, sentinel_logs, sentinel_conf

Create Podman network for redis and sentinel

Using root image, 

Using path /var/lib/containers/{data,config,certs,logs}

Using path /etc/containers/systemd/{redis-sentinel.container, redis.container}

set all permission for avoid any issues

step by step without scripts
##########################





```
VM1 (192.168.100.10)    VM2 (192.168.100.11)    VM3 (192.168.100.12)
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Redis Node 1   │    │  Redis Node 2   │    │  Redis Node 3   │
│  (Primary)      │    │  (Replica)      │    │  (Replica)      │
│  - TLS Certs    │    │  - TLS Certs    │    │  - TLS Certs    │
│  - Volume       │    │  - Volume       │    │  - Volume       │
│  - Sentinel     │    │  - Sentinel     │    │  - Sentinel     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
           │                        │                       │
           └────────────────────────┴───────────────────────┘
                    Redis Cluster + Sentinel HA
```
## all VMs
Update system
sudo dnf update -y

# Install Podman
sudo dnf install -y podman podman-plugins

# Enable podman socket for user services
systemctl enable --now podman.socket

mkdir -p /var/lib/containers/redis/{certs,config,data,logs}

# certificates generator

#On redis-node1 (Master):
cat > /var/lib/containers/redis/config/redis.conf << 'EOF'
# Network
bind 0.0.0.0
port 0
tls-port 6379
protected-mode yes

# TLS Configuration
tls-cert-file /certs/redis-node1-cert.pem
tls-key-file /certs/redis-node1-key.pem
tls-ca-cert-file /certs/ca-cert.pem
tls-auth-clients no
tls-replication yes

# Security
requirepass "Passw0rd!"
masterauth "Passw0rd!"

# Persistence
dir /data
appendonly yes
appendfsync everysec
save 900 1
save 300 10
save 60 10000

# Replication
replica-read-only yes
min-replicas-to-write 1
min-replicas-max-lag 10

# Logging
loglevel notice
logfile ""

# Performance
maxmemory 2gb
maxmemory-policy allkeys-lru
EOF
#On redis-node2 (Replica):
cat > /var/lib/containers/redis/config/redis.conf << 'EOF'
# Network
bind 0.0.0.0
port 0
tls-port 6379
protected-mode yes

# TLS Configuration
tls-cert-file /certs/redis-node2-cert.pem
tls-key-file /certs/redis-node2-key.pem
tls-ca-cert-file /certs/ca-cert.pem
tls-auth-clients no
tls-replication yes

# Security
requirepass "Passw0rd!"
masterauth "Passw0rd!"

# Persistence
dir /data
appendonly yes
appendfsync everysec
save 900 1
save 300 10
save 60 10000

# Replication
replicaof redis-node1 6379
replica-read-only yes

# Logging
loglevel notice
logfile ""

# Performance
maxmemory 2gb
maxmemory-policy allkeys-lru
EOF

##On redis-node3 (Replica):
cat > /var/lib/containers/redis/config/redis.conf << 'EOF'
# Network
bind 0.0.0.0
port 0
tls-port 6379
protected-mode yes

# TLS Configuration
tls-cert-file /certs/redis-node3-cert.pem
tls-key-file /certs/redis-node3-key.pem
tls-ca-cert-file /certs/ca-cert.pem
tls-auth-clients no
tls-replication yes

# Security
requirepass "Passw0rd!"
masterauth "Passw0rd!"

# Persistence
dir /data
appendonly yes
appendfsync everysec
save 900 1
save 300 10
save 60 10000

# Replication
replicaof redis-node1 6379
replica-read-only yes

# Logging
loglevel notice
logfile ""

# Performance
maxmemory 2gb
maxmemory-policy allkeys-lru
EOF


###Configure Sentinel (All Nodes)
#On redis-node1:
cat > /var/lib/containers/redis/config/sentinel.conf << 'EOF'
port 0
tls-port 26379
bind 0.0.0.0

# TLS Configuration
tls-cert-file /certs/redis-node1-cert.pem
tls-key-file /certs/redis-node1-key.pem
tls-ca-cert-file /certs/ca-cert.pem
tls-replication yes

# Sentinel Configuration
sentinel monitor mymaster 192.168.100.63 6379 2
sentinel auth-pass mymaster Passw0rd!
sentinel down-after-milliseconds mymaster 5000
sentinel parallel-syncs mymaster 1
sentinel failover-timeout mymaster 10000

# Logging
logfile ""
EOF

##On redis-node2:
cat > /var/lib/containers/redis/config/sentinel.conf << 'EOF'
port 0
tls-port 26379
bind 0.0.0.0

# TLS Configuration
tls-cert-file /certs/redis-node2-cert.pem
tls-key-file /certs/redis-node2-key.pem
tls-ca-cert-file /certs/ca-cert.pem
tls-replication yes

# Sentinel Configuration
sentinel monitor mymaster 192.168.100.63 6379 2
sentinel auth-pass mymaster Passw0rd!
sentinel down-after-milliseconds mymaster 5000
sentinel parallel-syncs mymaster 1
sentinel failover-timeout mymaster 10000

# Logging
logfile ""
EOF

##On redis-node3:
cat > /var/lib/containers/redis/config/sentinel.conf << 'EOF'
port 0
tls-port 26379
bind 0.0.0.0

# TLS Configuration
tls-cert-file /certs/redis-node3-cert.pem
tls-key-file /certs/redis-node3-key.pem
tls-ca-cert-file /certs/ca-cert.pem
tls-replication yes

# Sentinel Configuration
sentinel monitor mymaster 192.168.100.63 6379 2
sentinel auth-pass mymaster Passw0rd!
sentinel down-after-milliseconds mymaster 5000
sentinel parallel-syncs mymaster 1
sentinel failover-timeout mymaster 10000

# Logging
logfile ""
EOF

### Create Quadlet Files (All Nodes)
#Redis Container Quadlet
#On redis-node1:

cat > /etc/containers/systemd/redis.container << 'EOF'
[Unit]
Description=Redis Server
After=local-fs.target

[Container]
Image=docker.io/redis:latest
ContainerName=redis
AutoUpdate=registry

# User mapping - run as current user
User=999:999

# Volumes
Volume=/var/lib/containers/redis/data:/data:Z
Volume=/var/lib/containers/redis/config:/config:Z
Volume=/var/lib/containers/redis/certs:/certs:Z

# Network
PublishPort=6379:6379
Network=host

# Command
Exec=redis-server /config/redis.conf

# Health check
HealthCmd=redis-cli --tls --cert /certs/redis-node1-cert.pem --key /certs/redis-node1-key.pem --cacert /certs/ca-cert.pem -a Passw0rd! ping
HealthInterval=10s
HealthTimeout=5s
HealthRetries=3

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=default.target
EOF

# node2
cat > /etc/containers/systemd/redis.container << 'EOF'
[Unit]
Description=Redis Server
After=local-fs.target

[Container]
Image=docker.io/redis:latest
ContainerName=redis
AutoUpdate=registry

# User mapping - run as current user
User=999:999

# Volumes
Volume=/var/lib/containers/redis/data:/data:Z
Volume=/var/lib/containers/redis/config:/config:Z
Volume=/var/lib/containers/redis/certs:/certs:Z

# Network
PublishPort=6379:6379
Network=host

# Command
Exec=redis-server /config/redis.conf

# Health check
HealthCmd=redis-cli --tls --cert /certs/redis-node2-cert.pem --key /certs/redis-node2-key.pem --cacert /certs/ca-cert.pem -a Passw0rd! ping
HealthInterval=10s
HealthTimeout=5s
HealthRetries=3

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=default.target
EOF

# node3
cat > /etc/containers/systemd/redis.container << 'EOF'
[Unit]
Description=Redis Server
After=local-fs.target

[Container]
Image=docker.io/redis:latest
ContainerName=redis
AutoUpdate=registry

# User mapping - run as current user
User=999:999

# Volumes
Volume=/var/lib/containers/redis/data:/data:Z
Volume=/var/lib/containers/redis/config:/config:Z
Volume=/var/lib/containers/redis/certs:/certs:Z

# Network
PublishPort=6379:6379
Network=host

# Command
Exec=redis-server /config/redis.conf

# Health check
HealthCmd=redis-cli --tls --cert /certs/redis-node3-cert.pem --key /certs/redis-node3-key.pem --cacert /certs/ca-cert.pem -a Passw0rd! ping
HealthInterval=10s
HealthTimeout=5s
HealthRetries=3

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=default.target
EOF

###Sentinel Container Quadlet
#On all nodes:
cat > /etc/containers/systemd/redis-sentinel.container << 'EOF'
[Unit]
Description=Redis Sentinel
After=redis.service
Requires=redis.service

[Container]
Image=docker.io/redis:latest
ContainerName=redis-sentinel
AutoUpdate=registry

# Volumes
Volume=/var/lib/containers/redis/config:/config:Z
Volume=/var/lib/containers/redis/certs:/certs:Z

# Network
#PublishPort=26379:26379
#Network=host
PublishPort=0.0.0.0:9200:26379/tcp


# Add hosts file for name resolution
AddHost=redis-node1:192.168.100.63
AddHost=redis-node2:192.168.100.64
AddHost=redis-node3:192.168.100.65

# Command
Exec=redis-sentinel /config/sentinel.conf

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=default.target

EOF

## Persmission
# Set correct ownership (make readable by container)
chmod 644 ~/redis/certs/redis-node1-cert.pem
chmod 644 ~/redis/certs/redis-node1-key.pem  # Temporarily more permissive
chmod 644 ~/redis/certs/ca-cert.pem

# Better approach: Set ownership to container UID
# Redis container runs as UID 999 by default
sudo chown -R 999:999 ~/redis/certs/
chmod 600 ~/redis/certs/*-key.pem
chmod 644 ~/redis/certs/*-cert.pem
chmod 644 ~/redis/certs/ca-cert.pem




# Reload systemd user daemon
systemctl  daemon-reload

# Enable and start Redis
systemctl  start redis.service

# Wait a few seconds for Redis to start
sleep 5

# Enable and start Sentinel
systemctl  start redis-sentinel.service

# Enable lingering (allows user services to run without login)
#sudo loginctl enable-linger $USER

# Allow Redis and Sentinel ports
sudo firewall-cmd --permanent --add-port=6379/tcp
sudo firewall-cmd --permanent --add-port=26379/tcp
sudo firewall-cmd --reload


#Verify Deployment
#Check Redis Status:
# Check container status
podman ps

# Check Redis replication (on master)
redis-cli --tls \
  --cert ~/redis/certs/redis-node1-cert.pem \
  --key ~/redis/certs/redis-node1-key.pem \
  --cacert ~/redis/certs/ca-cert.pem \
  -a YourStrongPasswordHere \
  -h redis-node1 \
  INFO replication

# Check Sentinel status
redis-cli -p 26379 --tls \
  --cert ~/redis/certs/redis-node1-cert.pem \
  --key ~/redis/certs/redis-node1-key.pem \
  --cacert ~/redis/certs/ca-cert.pem \
  SENTINEL masters

#Test Replication:

  # Set a key on master (redis-node1)
redis-cli --tls \
  --cert ~/redis/certs/redis-node1-cert.pem \
  --key ~/redis/certs/redis-node1-key.pem \
  --cacert ~/redis/certs/ca-cert.pem \
  -a YourStrongPasswordHere \
  -h redis-node1 \
  SET testkey "Hello from Redis HA"

# Get the key from replica (redis-node2)
redis-cli --tls \
  --cert ~/redis/certs/redis-node2-cert.pem \
  --key ~/redis/certs/redis-node2-key.pem \
  --cacert ~/redis/certs/ca-cert.pem \
  -a YourStrongPasswordHere \
  -h redis-node2 \
  GET testkey

# Test Failover

# Stop Redis on master (redis-node1)
systemctl  stop redis.service

# Watch Sentinel promote a new master (run on any node)
redis-cli -p 26379 --tls \
  --cert ~/redis/certs/redis-node2-cert.pem \
  --key ~/redis/certs/redis-node2-key.pem \
  --cacert ~/redis/certs/ca-cert.pem \
  SENTINEL get-master-addr-by-name mymaster

# Start Redis on node1 again (it will become a replica)
systemctl start redis.service


journalctl  -u redis-sentinel.service -f
journalctl  -u redis.service -f