# PostgreSQL 18 HA Setup with Patroni on Rocky Linux 9

Ill guide you through setting up a 3-node PostgreSQL 18 HA cluster using Patroni, Podman, and Quadlet.

## Prerequisites on All 3 Nodes

```bash
# Update system
sudo dnf update -y

# Install podman
sudo dnf install -y podman podman-plugins

# Enable podman socket
sudo systemctl enable --now podman.socket

# Create directory structure
sudo mkdir -p /var/lib/containers/postgres/{data,config,certs,logs}
sudo chmod -R 777 /var/lib/containers/postgres

sudo chown -R 999:999 /var/lib/containers/postgres/data/
sudo chmod 700 /var/lib/containers/postgres/data/

# Keep config and logs accessible
sudo chmod 755 /var/lib/containers/postgres/config
sudo chmod 755 /var/lib/containers/postgres/logs


# Create Quadlet directory
sudo mkdir -p /etc/containers/systemd
```

## Step 1: Create Patroni Configuration Files

### On pg-node1 (192.168.100.104):

```bash
sudo tee /var/lib/containers/postgres/config/patroni.yml > /dev/null <<'EOF'
scope: postgres-cluster
name: pg-node1

restapi:
  listen: 0.0.0.0:8008
  connect_address: 192.168.100.104:8008

etcd3:
  hosts: 192.168.100.104:2379,192.168.100.105:2379,192.168.100.106:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      parameters:
        max_connections: 200
        shared_buffers: 256MB
        wal_level: replica
        hot_standby: on
        max_wal_senders: 10
        max_replication_slots: 10

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - host replication replicator 192.168.100.0/24 md5
    - host all all 0.0.0.0/0 md5

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 192.168.100.104:5432
  data_dir: /var/lib/postgresql/data
  pgpass: /tmp/pgpass
  authentication:
    replication:
      username: replicator
      password: replicator_password
    superuser:
      username: postgres
      password: postgres_password

tags:
    nofailover: false
    noloadbalance: false
    clonefrom: false
    nosync: false
EOF
```

### On pg-node2 (192.168.100.105):

```bash
sudo tee /var/lib/containers/postgres/config/patroni.yml > /dev/null <<'EOF'
scope: postgres-cluster
name: pg-node2

restapi:
  listen: 0.0.0.0:8008
  connect_address: 192.168.100.105:8008

etcd3:
  hosts: 192.168.100.104:2379,192.168.100.105:2379,192.168.100.106:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      parameters:
        max_connections: 200
        shared_buffers: 256MB
        wal_level: replica
        hot_standby: on
        max_wal_senders: 10
        max_replication_slots: 10

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - host replication replicator 192.168.100.0/24 md5
    - host all all 0.0.0.0/0 md5

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 192.168.100.105:5432
  data_dir: /var/lib/postgresql/data
  pgpass: /tmp/pgpass
  authentication:
    replication:
      username: replicator
      password: replicator_password
    superuser:
      username: postgres
      password: postgres_password

tags:
    nofailover: false
    noloadbalance: false
    clonefrom: false
    nosync: false
EOF
```

### On pg-node3 (192.168.100.106):

```bash
sudo tee /var/lib/containers/postgres/config/patroni.yml > /dev/null <<'EOF'
scope: postgres-cluster
name: pg-node3

restapi:
  listen: 0.0.0.0:8008
  connect_address: 192.168.100.106:8008

etcd3:
  hosts: 192.168.100.104:2379,192.168.100.105:2379,192.168.100.106:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      parameters:
        max_connections: 200
        shared_buffers: 256MB
        wal_level: replica
        hot_standby: on
        max_wal_senders: 10
        max_replication_slots: 10

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - host replication replicator 192.168.100.0/24 md5
    - host all all 0.0.0.0/0 md5

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 192.168.100.106:5432
  data_dir: /var/lib/postgresql/data
  pgpass: /tmp/pgpass
  authentication:
    replication:
      username: replicator
      password: replicator_password
    superuser:
      username: postgres
      password: postgres_password

tags:
    nofailover: false
    noloadbalance: false
    clonefrom: false
    nosync: false
EOF
```

## Step 2: Create Dockerfile for Custom Patroni Image

On any node (youll build once and share or rebuild on each):

```bash
mkdir -p ~/patroni-build
cd ~/patroni-build

cat > Dockerfile <<'EOF'
FROM postgres:18

# Install dependencies
RUN apt-get update && \
    apt-get install -y python3 python3-pip python3-psycopg2 && \
    pip3 install --break-system-packages patroni[etcd3] && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create directories
RUN mkdir -p /var/lib/postgresql/data && \
    chown -R postgres:postgres /var/lib/postgresql

USER postgres

EXPOSE 5432 8008

CMD ["patroni", "/etc/patroni/patroni.yml"]
EOF

# Build the image
podman build -t localhost/patroni-pg18:latest .
```

## Step 3: Create etcd Quadlet Service (All Nodes)

### On pg-node1:
```bash
sudo tee /etc/containers/systemd/etcd.container > /dev/null <<'EOF'
[Unit]
Description=etcd container for Patroni
After=network-online.target

[Container]
Image=quay.io/coreos/etcd:v3.5.11
ContainerName=etcd
Network=host
Environment=ETCD_NAME=etcd1
Environment=ETCD_INITIAL_ADVERTISE_PEER_URLS=http://192.168.100.104:2380
Environment=ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380
Environment=ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
Environment=ETCD_ADVERTISE_CLIENT_URLS=http://192.168.100.104:2379
Environment=ETCD_INITIAL_CLUSTER_TOKEN=etcd-cluster
Environment=ETCD_INITIAL_CLUSTER=etcd1=http://192.168.100.104:2380,etcd2=http://192.168.100.105:2380,etcd3=http://192.168.100.106:2380
Environment=ETCD_INITIAL_CLUSTER_STATE=new
Volume=/var/lib/containers/postgres/data/etcd:/etcd-data:Z

[Service]
Restart=always

[Install]
WantedBy=multi-user.target default.target
EOF
```

### On pg-node2:
```bash
sudo tee /etc/containers/systemd/etcd.container > /dev/null <<'EOF'
[Unit]
Description=etcd container for Patroni
After=network-online.target

[Container]
Image=quay.io/coreos/etcd:v3.5.11
ContainerName=etcd
Network=host
Environment=ETCD_NAME=etcd2
Environment=ETCD_INITIAL_ADVERTISE_PEER_URLS=http://192.168.100.105:2380
Environment=ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380
Environment=ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
Environment=ETCD_ADVERTISE_CLIENT_URLS=http://192.168.100.105:2379
Environment=ETCD_INITIAL_CLUSTER_TOKEN=etcd-cluster
Environment=ETCD_INITIAL_CLUSTER=etcd1=http://192.168.100.104:2380,etcd2=http://192.168.100.105:2380,etcd3=http://192.168.100.106:2380
Environment=ETCD_INITIAL_CLUSTER_STATE=new
Volume=/var/lib/containers/postgres/data/etcd:/etcd-data:Z

[Service]
Restart=always

[Install]
WantedBy=multi-user.target default.target
EOF
```

### On pg-node3:
```bash
sudo tee /etc/containers/systemd/etcd.container > /dev/null <<'EOF'
[Unit]
Description=etcd container for Patroni
After=network-online.target

[Container]
Image=quay.io/coreos/etcd:v3.5.11
ContainerName=etcd
Network=host
Environment=ETCD_NAME=etcd3
Environment=ETCD_INITIAL_ADVERTISE_PEER_URLS=http://192.168.100.106:2380
Environment=ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380
Environment=ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
Environment=ETCD_ADVERTISE_CLIENT_URLS=http://192.168.100.106:2379
Environment=ETCD_INITIAL_CLUSTER_TOKEN=etcd-cluster
Environment=ETCD_INITIAL_CLUSTER=etcd1=http://192.168.100.104:2380,etcd2=http://192.168.100.105:2380,etcd3=http://192.168.100.106:2380
Environment=ETCD_INITIAL_CLUSTER_STATE=new
Volume=/var/lib/containers/postgres/data/etcd:/etcd-data:Z

[Service]
Restart=always

[Install]
WantedBy=multi-user.target default.target
EOF
```

## Step 4: Create Patroni Quadlet Service (All Nodes)

```bash
sudo tee /etc/containers/systemd/patroni.container > /dev/null <<'EOF'
[Unit]
Description=Patroni PostgreSQL HA
After=etcd.service
Requires=etcd.service

[Container]
Image=localhost/patroni-pg18:latest
ContainerName=patroni
Network=host
Volume=/var/lib/containers/postgres/data:/var/lib/postgresql/data:Z
Volume=/var/lib/containers/postgres/config/patroni.yml:/etc/patroni/patroni.yml:Z
Volume=/var/lib/containers/postgres/logs:/var/log/patroni:Z

[Service]
Restart=always

[Install]
WantedBy=multi-user.target default.target
EOF
```

## Step 5: Configure Firewall (All Nodes)

```bash
# Open required ports
sudo firewall-cmd --permanent --add-port=5432/tcp  # PostgreSQL
sudo firewall-cmd --permanent --add-port=8008/tcp  # Patroni REST API
sudo firewall-cmd --permanent --add-port=2379/tcp  # etcd client
sudo firewall-cmd --permanent --add-port=2380/tcp  # etcd peer
sudo firewall-cmd --reload
```

## Step 6: Start Services (All Nodes - Start in Order)

```bash
# Reload systemd to pick up Quadlet files
sudo systemctl daemon-reload

# Start etcd on all nodes simultaneously
sudo systemctl start etcd.service

# Wait 10 seconds for etcd cluster to form
sleep 10

# Check etcd health (on any node)
podman exec etcd etcdctl endpoint health --cluster

# Start Patroni on node1 first
sudo systemctl start patroni.service

# Wait for node1 to become leader (30 seconds)
sleep 30

# Start Patroni on node2 and node3
sudo systemctl start patroni.service
```

## Step 7: Verify Cluster Status

On any node:

```bash
# Check Patroni cluster status
podman exec patroni patronictl -c /etc/patroni/patroni.yml list

# Check PostgreSQL is running
podman exec patroni psql -U postgres -c "SELECT version();"

# Check replication status
podman exec patroni psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Check etcd cluster
podman exec etcd etcdctl member list
```

## Step 8: Enable Services for Auto-start (All Nodes)

```bash
sudo systemctl enable etcd.service
sudo systemctl enable patroni.service
```

## Common Commands

```bash
# Check cluster status
podman exec patroni patronictl -c /etc/patroni/patroni.yml list

# Manual failover
podman exec patroni patronictl -c /etc/patroni/patroni.yml failover

# Restart a node
podman exec patroni patronictl -c /etc/patroni/patroni.yml restart pg-node1

# Check logs
sudo journalctl -u patroni.service -f
sudo journalctl -u etcd.service -f
```

## Test Failover

```bash
# On the current leader node, stop Patroni
sudo systemctl stop patroni.service

# Watch the cluster elect a new leader
podman exec patroni patronictl -c /etc/patroni/patroni.yml list
```

## Connection Details

- **PostgreSQL Port:** 5432
- **Patroni API Port:** 8008
- **Default superuser:** postgres / postgres_password
- **Replication user:** replicator / replicator_password

Connect to any node on port 5432, and Patroni will handle routing reads/writes appropriately!