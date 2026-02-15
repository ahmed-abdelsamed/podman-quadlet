:'
setup and configured Postgres 18 HA on 3 podman with quadlet  on 3 VMs rocky linux 9 and nodes: {pg-node1: 192.168.100.101, pg-node2:192.168.100.102, pg-node3:192.168.100.103} ,
Using path /var/lib/containers/postgres/{data,config,certs,logs}
With Custom patroni image
set all permission for avoid any issues
step by step without complex
'

#I'll guide you through setting up PostgreSQL 18 HA with Patroni, etcd, and HAProxy on 3 Rocky Linux 9 VMs using Podman with Quadlet.

## Prerequisites on All 3 Nodes

First, lets prepare all three nodes (pg-node1, pg-node2, pg-node3):

### 1. Install Required Packages

```bash
dnf update -y
dnf install -y podman podman-plugins container-tools
```

## add nodes in hosts file:
# Edit /etc/hosts
cat >> /etc/hosts << EOF
192.168.100.101 pg-node1
192.168.100.102 pg-node2
192.168.100.103 pg-node3
EOF

setenforce 0
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config


### 2. Enable Podman Socket

```bash
systemctl enable --now podman.socket
```

### 3. Create Directory Structure

```bash
mkdir -p /var/lib/containers/postgres/{data,config,certs,logs}
mkdir -p /etc/containers/systemd
```

### 4. Set Permissions

```bash
chmod -R 755 /var/lib/containers/postgres
chown -R root:root /var/lib/containers/postgres
chmod 755 /etc/containers/systemd
```

---

## Part 1: Generate SSL Certificates (On pg-node1)

### 1. Install OpenSSL

```bash
dnf install -y openssl
```

### 2. Generate CA Certificate

```bash
cd /var/lib/containers/postgres/certs

# Generate CA private key
openssl genrsa -out ca-key.pem 4096

# Generate CA certificate
openssl req -new -x509 -days 3650 -key ca-key.pem -out ca-cert.pem -subj "/CN=PostgreSQL-CA"
```

### 3. Generate Server Certificates for Each Node

**For pg-node1:**

```bash
# Generate private key
openssl genrsa -out pg-node1-key.pem 4096

# Generate certificate signing request
openssl req -new -key pg-node1-key.pem -out pg-node1.csr -subj "/CN=pg-node1"

# Create extensions file
cat > pg-node1-ext.cnf << EOF
subjectAltName = DNS:pg-node1,DNS:localhost,IP:192.168.100.101,IP:127.0.0.1
EOF

# Sign certificate
openssl x509 -req -days 3650 -in pg-node1.csr -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial -out pg-node1-cert.pem -extfile pg-node1-ext.cnf
```

**For pg-node2:**

```bash
openssl genrsa -out pg-node2-key.pem 4096
openssl req -new -key pg-node2-key.pem -out pg-node2.csr -subj "/CN=pg-node2"

cat > pg-node2-ext.cnf << EOF
subjectAltName = DNS:pg-node2,DNS:localhost,IP:192.168.100.102,IP:127.0.0.1
EOF

openssl x509 -req -days 3650 -in pg-node2.csr -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial -out pg-node2-cert.pem -extfile pg-node2-ext.cnf
```

**For pg-node3:**

```bash
openssl genrsa -out pg-node3-key.pem 4096
openssl req -new -key pg-node3-key.pem -out pg-node3.csr -subj "/CN=pg-node3"

cat > pg-node3-ext.cnf << EOF
subjectAltName = DNS:pg-node3,DNS:localhost,IP:192.168.100.103,IP:127.0.0.1
EOF

openssl x509 -req -days 3650 -in pg-node3.csr -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial -out pg-node3-cert.pem -extfile pg-node3-ext.cnf
```

### 4. Set Certificate Permissions

```bash
chmod 644 /var/lib/containers/postgres/certs/*.pem
chmod 600 /var/lib/containers/postgres/certs/*-key.pem
```

### 5. Copy Certificates to Other Nodes

**Copy to pg-node2:**

```bash
scp /var/lib/containers/postgres/certs/ca-cert.pem root@192.168.100.102:/var/lib/containers/postgres/certs/
scp /var/lib/containers/postgres/certs/pg-node2-cert.pem root@192.168.100.102:/var/lib/containers/postgres/certs/
scp /var/lib/containers/postgres/certs/pg-node2-key.pem root@192.168.100.102:/var/lib/containers/postgres/certs/
```

**Copy to pg-node3:**

```bash
scp /var/lib/containers/postgres/certs/ca-cert.pem root@192.168.100.103:/var/lib/containers/postgres/certs/
scp /var/lib/containers/postgres/certs/pg-node3-cert.pem root@192.168.100.103:/var/lib/containers/postgres/certs/
scp /var/lib/containers/postgres/certs/pg-node3-key.pem root@192.168.100.103:/var/lib/containers/postgres/certs/
```

**On pg-node2 and pg-node3, set permissions:**

```bash
chmod 644 /var/lib/containers/postgres/certs/*.pem
chmod 600 /var/lib/containers/postgres/certs/*-key.pem
```

---

## Part 2: Create Podman Secrets (On Each Node)

### On pg-node1:

```bash
# PostgreSQL passwords
echo "Passw0rd!" | podman secret create postgres_password -
echo "Passw0rd!" | podman secret create postgres_replica_password -
echo "Passw0rd!" | podman secret create patroni_password -

# SSL certificates
podman secret create postgres_ca_cert /var/lib/containers/postgres/certs/ca-cert.pem
podman secret create postgres_server_cert /var/lib/containers/postgres/certs/pg-node1-cert.pem
podman secret create postgres_server_key /var/lib/containers/postgres/certs/pg-node1-key.pem
```

### On pg-node2:

```bash
echo "Passw0rd!" | podman secret create postgres_password -
echo "Passw0rd!" | podman secret create postgres_replica_password -
echo "Passw0rd!" | podman secret create patroni_password -

podman secret create postgres_ca_cert /var/lib/containers/postgres/certs/ca-cert.pem
podman secret create postgres_server_cert /var/lib/containers/postgres/certs/pg-node2-cert.pem
podman secret create postgres_server_key /var/lib/containers/postgres/certs/pg-node2-key.pem
```

### On pg-node3:

```bash
echo "Passw0rd!" | podman secret create postgres_password -
echo "Passw0rd!" | podman secret create postgres_replica_password -
echo "Passw0rd!" | podman secret create patroni_password -

podman secret create postgres_ca_cert /var/lib/containers/postgres/certs/ca-cert.pem
podman secret create postgres_server_cert /var/lib/containers/postgres/certs/pg-node3-cert.pem
podman secret create postgres_server_key /var/lib/containers/postgres/certs/pg-node3-key.pem
```

### Verify Secrets

```bash
podman secret ls
```

---

## Part 3: Create Podman Volumes (On Each Node)

```bash
podman volume create pg_data
podman volume create pg_logs
podman volume create pg_conf
podman volume create etcd_data
podman volume create patroni_config
```

### Verify Volumes

```bash
podman volume ls
```

---

## Part 4: Create Podman Network (On Each Node)

```bash
#podman network create postgres-network
```

### Verify Network

```bash
podman network inspect postgres-network
```

---

## Part 5: Create etcd Configuration (On Each Node)

### On pg-node1:

```bash
cat > /var/lib/containers/postgres/config/etcd.conf << 'EOF'
ETCD_NAME=etcd1
ETCD_DATA_DIR=/etcd-data
ETCD_LISTEN_PEER_URLS=http://192.168.100.101:2380
ETCD_LISTEN_CLIENT_URLS=http://192.168.100.101:2379,http://127.0.0.1:2379
ETCD_INITIAL_ADVERTISE_PEER_URLS=http://192.168.100.101:2380
ETCD_ADVERTISE_CLIENT_URLS=http://192.168.100.101:2379
ETCD_INITIAL_CLUSTER=etcd1=http://192.168.100.101:2380,etcd2=http://192.168.100.102:2380,etcd3=http://192.168.100.103:2380
ETCD_INITIAL_CLUSTER_STATE=new
ETCD_INITIAL_CLUSTER_TOKEN=postgres-cluster
EOF
```

### On pg-node2:

```bash
cat > /var/lib/containers/postgres/config/etcd.conf << 'EOF'
ETCD_NAME=etcd2
ETCD_DATA_DIR=/etcd-data
ETCD_LISTEN_PEER_URLS=http://192.168.100.102:2380
ETCD_LISTEN_CLIENT_URLS=http://192.168.100.102:2379,http://127.0.0.1:2379
ETCD_INITIAL_ADVERTISE_PEER_URLS=http://192.168.100.102:2380
ETCD_ADVERTISE_CLIENT_URLS=http://192.168.100.102:2379
ETCD_INITIAL_CLUSTER=etcd1=http://192.168.100.101:2380,etcd2=http://192.168.100.102:2380,etcd3=http://192.168.100.103:2380
ETCD_INITIAL_CLUSTER_STATE=new
ETCD_INITIAL_CLUSTER_TOKEN=postgres-cluster
EOF
```

### On pg-node3:

```bash
cat > /var/lib/containers/postgres/config/etcd.conf << 'EOF'
ETCD_NAME=etcd3
ETCD_DATA_DIR=/etcd-data
ETCD_LISTEN_PEER_URLS=http://192.168.100.103:2380
ETCD_LISTEN_CLIENT_URLS=http://192.168.100.103:2379,http://127.0.0.1:2379
ETCD_INITIAL_ADVERTISE_PEER_URLS=http://192.168.100.103:2380
ETCD_ADVERTISE_CLIENT_URLS=http://192.168.100.103:2379
ETCD_INITIAL_CLUSTER=etcd1=http://192.168.100.101:2380,etcd2=http://192.168.100.102:2380,etcd3=http://192.168.100.103:2380
ETCD_INITIAL_CLUSTER_STATE=new
ETCD_INITIAL_CLUSTER_TOKEN=postgres-cluster
EOF
```

### Set Permissions

```bash
chmod 644 /var/lib/containers/postgres/config/etcd.conf
```

---

## Part 6: Create etcd Quadlet File (On Each Node)

### On pg-node1:

```bash
cat > /etc/containers/systemd/etcd.container << 'EOF'
[Unit]
Description=etcd for PostgreSQL HA Cluster
After=network-online.target
Wants=network-online.target

[Container]
Image=gcr.io/etcd-development/etcd:v3.5.12
ContainerName=etcd
Network=host
#PublishPort=2379:2379
#PublishPort=2380:2380
Volume=etcd_data:/etcd-data:Z
EnvironmentFile=/var/lib/containers/postgres/config/etcd.conf
AutoUpdate=registry

[Service]
Restart=always
TimeoutStartSec=900

[Install]
WantedBy=multi-user.target default.target
EOF
```

### On pg-node2 and pg-node3:

Same content as pg-node1 (copy the file above)

```bash
cat > /etc/containers/systemd/etcd.container << 'EOF'
[Unit]
Description=etcd for PostgreSQL HA Cluster
After=network-online.target
Wants=network-online.target

[Container]
Image=gcr.io/etcd-development/etcd:v3.5.12
ContainerName=etcd
Network=host
#PublishPort=2379:2379
#PublishPort=2380:2380
Volume=etcd_data:/etcd-data:Z
EnvironmentFile=/var/lib/containers/postgres/config/etcd.conf
AutoUpdate=registry

[Service]
Restart=always
TimeoutStartSec=900

[Install]
WantedBy=multi-user.target default.target
EOF
```

### Set Permissions

```bash
chmod 644 /etc/containers/systemd/etcd.container
```

---

## Part 7: Create Patroni Configuration (On Each Node)

### On pg-node1:

```bash
cat > /var/lib/containers/postgres/config/patroni.yml << 'EOF'
scope: postgres-cluster
namespace: /db/
name: pg-node1

restapi:
  listen: 0.0.0.0:8008
  connect_address: 192.168.100.101:8008

etcd3:
  hosts: 192.168.100.101:2379,192.168.100.102:2379,192.168.100.103:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        max_connections: 100
        shared_buffers: 256MB
        effective_cache_size: 1GB
        maintenance_work_mem: 64MB
        checkpoint_completion_target: 0.9
        wal_buffers: 16MB
        default_statistics_target: 100
        random_page_cost: 1.1
        effective_io_concurrency: 200
        work_mem: 2621kB
        min_wal_size: 1GB
        max_wal_size: 4GB
        max_worker_processes: 2
        max_parallel_workers_per_gather: 1
        max_parallel_workers: 2
        max_parallel_maintenance_workers: 1
        wal_level: replica
        max_wal_senders: 10
        max_replication_slots: 10
        hot_standby: on
        ssl: on
        ssl_ca_file: /var/lib/postgresql/certs/ca-cert.pem
        ssl_cert_file: /var/lib/postgresql/certs/server-cert.pem
        ssl_key_file: /var/lib/postgresql/certs/server-key.pem

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - host replication replicator 192.168.100.0/24 md5
    - host all all 0.0.0.0/0 md5
    - host all all ::0/0 md5

  users:
    admin:
      password: Passw0rd!
      options:
        - createrole
        - createdb
    replicator:
      password: Passw0rd!
      options:
        - replication

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 192.168.100.101:5432
  data_dir: /var/lib/postgresql/data
  bin_dir: /usr/lib/postgresql/18/bin
  pgpass: /tmp/pgpass
  authentication:
    replication:
      username: replicator
      password: Passw0rd!
    superuser:
      username: postgres
      password: Passw0rd!
    rewind:
      username: replicator
      password: Passw0rd!
  parameters:
    unix_socket_directories: '/var/run/postgresql'
    ssl: on
    ssl_ca_file: /var/lib/postgresql/certs/ca-cert.pem
    ssl_cert_file: /var/lib/postgresql/certs/server-cert.pem
    ssl_key_file: /var/lib/postgresql/certs/server-key.pem

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF
```

### On pg-node2:

```bash
cat > /var/lib/containers/postgres/config/patroni.yml << 'EOF'
scope: postgres-cluster
namespace: /db/
name: pg-node2

restapi:
  listen: 0.0.0.0:8008
  connect_address: 192.168.100.102:8008

etcd3:
  hosts: 192.168.100.101:2379,192.168.100.102:2379,192.168.100.103:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        max_connections: 100
        shared_buffers: 256MB
        effective_cache_size: 1GB
        maintenance_work_mem: 64MB
        checkpoint_completion_target: 0.9
        wal_buffers: 16MB
        default_statistics_target: 100
        random_page_cost: 1.1
        effective_io_concurrency: 200
        work_mem: 2621kB
        min_wal_size: 1GB
        max_wal_size: 4GB
        max_worker_processes: 2
        max_parallel_workers_per_gather: 1
        max_parallel_workers: 2
        max_parallel_maintenance_workers: 1
        wal_level: replica
        max_wal_senders: 10
        max_replication_slots: 10
        hot_standby: on
        ssl: on
        ssl_ca_file: /var/lib/postgresql/certs/ca-cert.pem
        ssl_cert_file: /var/lib/postgresql/certs/server-cert.pem
        ssl_key_file: /var/lib/postgresql/certs/server-key.pem

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - host replication replicator 192.168.100.0/24 md5
    - host all all 0.0.0.0/0 md5
    - host all all ::0/0 md5

  users:
    admin:
      password: MyStrongPassword123!
      options:
        - createrole
        - createdb
    replicator:
      password: MyReplicaPassword123!
      options:
        - replication

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 192.168.100.102:5432
  data_dir: /var/lib/postgresql/data
  bin_dir: /usr/lib/postgresql/18/bin
  pgpass: /tmp/pgpass
  authentication:
    replication:
      username: replicator
      password: MyReplicaPassword123!
    superuser:
      username: postgres
      password: MyStrongPassword123!
    rewind:
      username: replicator
      password: MyReplicaPassword123!
  parameters:
    unix_socket_directories: '/var/run/postgresql'
    ssl: on
    ssl_ca_file: /var/lib/postgresql/certs/ca-cert.pem
    ssl_cert_file: /var/lib/postgresql/certs/server-cert.pem
    ssl_key_file: /var/lib/postgresql/certs/server-key.pem

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF
```

### On pg-node3:

```bash
cat > /var/lib/containers/postgres/config/patroni.yml << 'EOF'
scope: postgres-cluster
namespace: /db/
name: pg-node3

restapi:
  listen: 0.0.0.0:8008
  connect_address: 192.168.100.103:8008

etcd:
  hosts: 192.168.100.101:2379,192.168.100.102:2379,192.168.100.103:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        max_connections: 100
        shared_buffers: 256MB
        effective_cache_size: 1GB
        maintenance_work_mem: 64MB
        checkpoint_completion_target: 0.9
        wal_buffers: 16MB
        default_statistics_target: 100
        random_page_cost: 1.1
        effective_io_concurrency: 200
        work_mem: 2621kB
        min_wal_size: 1GB
        max_wal_size: 4GB
        max_worker_processes: 2
        max_parallel_workers_per_gather: 1
        max_parallel_workers: 2
        max_parallel_maintenance_workers: 1
        wal_level: replica
        max_wal_senders: 10
        max_replication_slots: 10
        hot_standby: on
        ssl: on
        ssl_ca_file: /var/lib/postgresql/certs/ca-cert.pem
        ssl_cert_file: /var/lib/postgresql/certs/server-cert.pem
        ssl_key_file: /var/lib/postgresql/certs/server-key.pem

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - host replication replicator 192.168.100.0/24 md5
    - host all all 0.0.0.0/0 md5
    - host all all ::0/0 md5

  users:
    admin:
      password: MyStrongPassword123!
      options:
        - createrole
        - createdb
    replicator:
      password: MyReplicaPassword123!
      options:
        - replication

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 192.168.100.103:5432
  data_dir: /var/lib/postgresql/data
  bin_dir: /usr/lib/postgresql/18/bin
  pgpass: /tmp/pgpass
  authentication:
    replication:
      username: replicator
      password: MyReplicaPassword123!
    superuser:
      username: postgres
      password: MyStrongPassword123!
    rewind:
      username: replicator
      password: MyReplicaPassword123!
  parameters:
    unix_socket_directories: '/var/run/postgresql'
    ssl: on
    ssl_ca_file: /var/lib/postgresql/certs/ca-cert.pem
    ssl_cert_file: /var/lib/postgresql/certs/server-cert.pem
    ssl_key_file: /var/lib/postgresql/certs/server-key.pem

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF
```

### Set Permissions

```bash
chmod 644 /var/lib/containers/postgres/config/patroni.yml
```

---

## Part 8: Create Patroni Dockerfile (On All Nodes)

We need to create a custom image with Patroni and PostgreSQL 18.

```bash
mkdir -p /var/lib/containers/postgres/build
cd /var/lib/containers/postgres/build
```

```bash
cat > Dockerfile << 'EOF'
FROM postgres:18

USER root

RUN apt-get update && \
    apt-get install -y python3 python3-pip python3-venv && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/patroni-venv && \
    /opt/patroni-venv/bin/pip install --upgrade pip && \
    /opt/patroni-venv/bin/pip install patroni[etcd] psycopg2-binary

RUN mkdir -p /var/lib/postgresql/certs && \
    chown -R postgres:postgres /var/lib/postgresql/certs && \
    chmod 700 /var/lib/postgresql/certs

# Create symlinks for PostgreSQL binaries
RUN ln -s /usr/lib/postgresql/18/bin/* /usr/local/bin/ || true

ENV PATH="/opt/patroni-venv/bin:/usr/lib/postgresql/18/bin:$PATH"

USER postgres

CMD ["/opt/patroni-venv/bin/patroni", "/etc/patroni/patroni.yml"]
EOF
```

### Build the Image

```bash
podman build -t localhost/patroni-postgres:18 .
```

This will take a few minutes. Verify the image:

```bash
podman images | grep patroni-postgres
```

podman save -o patroni-postgres.tar localhost/patroni-postgres:18
scp patroni-postgres.tar root@192.168.100.102:/tmp/
scp patroni-postgres.tar root@192.168.100.103:/tmp/
# on node2,3
podman load -i /tmp/patroni-postgres.tar
---

## Part 9: Create Patroni Quadlet File (On Each Node)

### On pg-node1:

```bash
cat > /etc/containers/systemd/patroni.container << 'EOF'
[Unit]
Description=Patroni PostgreSQL HA on pg-node1
After=etcd.service
Requires=etcd.service

[Container]
Image=localhost/patroni-postgres:18
ContainerName=patroni
Network=host
#PublishPort=5432:5432
#PublishPort=8008:8008
Volume=pg_data:/var/lib/postgresql/data:z
Volume=pg_logs:/var/lib/postgresql/logs:z
Volume=/var/lib/containers/postgres/config/patroni.yml:/etc/patroni/patroni.yml:ro,z
Volume=/var/lib/containers/postgres/certs/ca-cert.pem:/var/lib/postgresql/certs/ca-cert.pem:ro,z
Volume=/var/lib/containers/postgres/certs/pg-node1-cert.pem:/var/lib/postgresql/certs/server-cert.pem:ro,z
Volume=/var/lib/containers/postgres/certs/pg-node1-key.pem:/var/lib/postgresql/certs/server-key.pem:ro,z
Environment=PATRONI_SCOPE=postgres-cluster
Environment=PATRONI_NAME=pg-node1

[Service]
Restart=always
TimeoutStartSec=900

[Install]
WantedBy=multi-user.target default.target
EOF
```

### On pg-node2:

```bash
cat > /etc/containers/systemd/patroni.container << 'EOF'
[Unit]
Description=Patroni PostgreSQL HA on pg-node2
After=etcd.service
Requires=etcd.service

[Container]
Image=localhost/patroni-postgres:18
ContainerName=patroni
Network=host
#PublishPort=5432:5432
#PublishPort=8008:8008
Volume=pg_data:/var/lib/postgresql/data:z
Volume=pg_logs:/var/lib/postgresql/logs:z
Volume=/var/lib/containers/postgres/config/patroni.yml:/etc/patroni/patroni.yml:ro,z
Volume=/var/lib/containers/postgres/certs/ca-cert.pem:/var/lib/postgresql/certs/ca-cert.pem:ro,z
Volume=/var/lib/containers/postgres/certs/pg-node2-cert.pem:/var/lib/postgresql/certs/server-cert.pem:ro,z
Volume=/var/lib/containers/postgres/certs/pg-node2-key.pem:/var/lib/postgresql/certs/server-key.pem:ro,z
Environment=PATRONI_SCOPE=postgres-cluster
Environment=PATRONI_NAME=pg-node2

[Service]
Restart=always
TimeoutStartSec=900

[Install]
WantedBy=multi-user.target default.target
EOF
```

### On pg-node3:

```bash
cat > /etc/containers/systemd/patroni.container << 'EOF'
[Unit]
Description=Patroni PostgreSQL HA on pg-node3
After=etcd.service
Requires=etcd.service

[Container]
Image=localhost/patroni-postgres:18
ContainerName=patroni
Network=host
#PublishPort=5432:5432
#PublishPort=8008:8008
Volume=pg_data:/var/lib/postgresql/data:z
Volume=pg_logs:/var/lib/postgresql/logs:z
Volume=/var/lib/containers/postgres/config/patroni.yml:/etc/patroni/patroni.yml:ro,z
Volume=/var/lib/containers/postgres/certs/ca-cert.pem:/var/lib/postgresql/certs/ca-cert.pem:ro,z
Volume=/var/lib/containers/postgres/certs/pg-node3-cert.pem:/var/lib/postgresql/certs/server-cert.pem:ro,z
Volume=/var/lib/containers/postgres/certs/pg-node3-key.pem:/var/lib/postgresql/certs/server-key.pem:ro,z
Environment=PATRONI_SCOPE=postgres-cluster
Environment=PATRONI_NAME=pg-node3

[Service]
Restart=always
TimeoutStartSec=900

[Install]
WantedBy=multi-user.target default.target
EOF
```

### Set Permissions

```bash
chmod 644 /var/lib/containers/postgres/certs/ca-cert.pem
chmod 644 /var/lib/containers/postgres/certs/pg-node1-cert.pem
chmod 600 /var/lib/containers/postgres/certs/pg-node1-key.pem
chown -R 999:999 /var/lib/containers/postgres/certs/
```
chmod 644 /var/lib/containers/postgres/certs/ca-cert.pem
chmod 644 /var/lib/containers/postgres/certs/pg-node2-cert.pem
chmod 600 /var/lib/containers/postgres/certs/pg-node2-key.pem
chown -R 999:999 /var/lib/containers/postgres/certs/
```
chmod 644 /var/lib/containers/postgres/certs/ca-cert.pem
chmod 644 /var/lib/containers/postgres/certs/pg-node3-cert.pem
chmod 600 /var/lib/containers/postgres/certs/pg-node3-key.pem
chown -R 999:999 /var/lib/containers/postgres/certs/
---

## Part 10: Configure Firewall (On All Nodes)

```bash
firewall-cmd --permanent --add-port=5432/tcp
firewall-cmd --permanent --add-port=8008/tcp
firewall-cmd --permanent --add-port=2379/tcp
firewall-cmd --permanent --add-port=2380/tcp
firewall-cmd --reload
```

---

## Part 11: Start Services (On All Nodes)

### Reload Systemd

```bash
systemctl daemon-reload
```

### Start etcd First (On All 3 Nodes Simultaneously)

It is important to start etcd on all nodes at roughly the same time:

```bash
systemctl start etcd.service
```

### Verify etcd Cluster

Wait 30 seconds, then check:

```bash
podman exec etcd etcdctl member list
: '
podman exec etcd etcdctl member list
1b4fd21405d8691b, started, etcd1, http://192.168.100.101:2380, http://192.168.100.101:2379, false
5162930cc76c12b9, started, etcd2, http://192.168.100.102:2380, http://192.168.100.102:2379, false
76bf7b3d8721cb40, started, etcd3, http://192.168.100.103:2380, http://192.168.100.103:2379, false

'
podman exec etcd etcdctl endpoint health
:'
http://192.168.100.101:2379 is healthy: successfully committed proposal: took = 4.462159ms
http://192.168.100.102:2379 is healthy: successfully committed proposal: took = 5.889379ms
http://192.168.100.103:2379 is healthy: successfully committed proposal: took = 23.783002ms
'
podman exec etcd etcdctl --endpoints=http://192.168.100.101:2379,http://192.168.100.102:2379,http://192.168.100.103:2379 endpoint health
http://192.168.100.101:2379 is healthy: successfully committed proposal: took = 4.162451ms
http://192.168.100.103:2379 is healthy: successfully committed proposal: took = 6.069617ms
http://192.168.100.102:2379 is healthy: successfully committed proposal: took = 6.936574ms




```

### Start Patroni (On All 3 Nodes)

After etcd is healthy:

```bash
systemctl enable --now patroni.service
```

### Check Status

```bash
systemctl status etcd.service
systemctl status patroni.service
```

---

## Part 12: Verify the Cluster

### Check Patroni Cluster Status

On any node:

```bash
podman exec patroni patronictl -c /etc/patroni/patroni.yml list
```

You should see all 3 nodes, with one as Leader and two as Replicas.

### Check PostgreSQL Replication

```bash
podman exec patroni psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

### Test Connection

```bash
podman exec patroni psql -U postgres -c "SELECT version();"
```

---

## Part 13: Optional - Setup HAProxy for Load Balancing

You can install HAProxy on one of the nodes or a separate node.

### On a Node (e.g., pg-node1):

```bash
cat > /var/lib/containers/postgres/config/haproxy.cfg << 'EOF'
global
    maxconn 100

defaults
    log global
    mode tcp
    retries 2
    timeout client 30m
    timeout connect 4s
    timeout server 30m
    timeout check 5s

listen stats
    mode http
    bind *:7000
    stats enable
    stats uri /

listen primary
    bind *:5000
    option httpchk OPTIONS /primary
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server pg-node1 192.168.100.101:5432 maxconn 100 check port 8008
    server pg-node2 192.168.100.102:5432 maxconn 100 check port 8008
    server pg-node3 192.168.100.103:5432 maxconn 100 check port 8008

listen replicas
    bind *:5001
    balance roundrobin
    option httpchk OPTIONS /replica
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server pg-node1 192.168.100.101:5432 maxconn 100 check port 8008
    server pg-node2 192.168.100.102:5432 maxconn 100 check port 8008
    server pg-node3 192.168.100.103:5432 maxconn 100 check port 8008
EOF
```

### Create HAProxy Quadlet:

```bash
cat > /etc/containers/systemd/haproxy.container << 'EOF'
[Unit]
Description=HAProxy for PostgreSQL HA
After=patroni.service
Wants=patroni.service

[Container]
Image=docker.io/library/haproxy:latest
ContainerName=haproxy
Network=postgres-network
PublishPort=5000:5000
PublishPort=5001:5001
PublishPort=7000:7000
Volume=/var/lib/containers/postgres/config/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro,Z
User=0
Group=0

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target default.target
EOF
```

### Enable and Start:

```bash
chmod 644 /etc/containers/systemd/haproxy.container
firewall-cmd --permanent --add-port=5000/tcp
firewall-cmd --permanent --add-port=5001/tcp
firewall-cmd --permanent --add-port=7000/tcp
firewall-cmd --reload
systemctl daemon-reload
systemctl enable --now haproxy.service
```

---

## Summary

You now have:
- **3-node etcd cluster** for distributed configuration
- **3-node PostgreSQL 18 cluster** with Patroni for HA
- **SSL/TLS encryption** for secure connections
- **Automatic failover** managed by Patroni
- **Optional HAProxy** for connection pooling and load balancing

Connect to the primary via port 5000 (HAProxy) or directly to port 5432 on any node. Patroni will handle automatic failover if the primary goes down.