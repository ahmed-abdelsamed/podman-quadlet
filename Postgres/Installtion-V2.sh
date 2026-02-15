:'
setup and configured Postgres 18 HA on 3 podman with quadlet  on 3 VMs rocky linux 9 and nodes: {pg-node1: 192.168.100.101, pg-node2:192.168.100.102, pg-node3:192.168.100.103} ,
Using path /var/lib/containers/postgres/{data,config,certs,logs}
With Custom patroni image
set all permission for avoid any issues
step by step without complex
'

#I'll guide you through setting up PostgreSQL 18 HA with Patroni, etcd, and HAProxy on 3 Rocky Linux 9 VMs using Podman with Quadlet.

## Prerequisites on All 3 Nodes

# First, lets prepare all three nodes (pg-node1, pg-node2, pg-node3):

### 1. Install Required Packages
dnf makecache
dnf update -y
dnf install -y podman podman-plugins container-tools podman-docker git
### 2. Enable Podman Socket
systemctl enable --now podman.socket


# On all nodes
sudo firewall-cmd --permanent --add-port=5432/tcp  # PostgreSQL
sudo firewall-cmd --permanent --add-port=8008/tcp  # Patroni REST API
sudo firewall-cmd --permanent --add-port=2379/tcp  # etcd client
sudo firewall-cmd --permanent --add-port=2380/tcp  # etcd peer
sudo firewall-cmd --reload

# On all nodes
sudo setenforce 0
sudo sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config

## add nodes in hosts file:
# Edit /etc/hosts
cat >> /etc/hosts << EOF
192.168.100.101 pg-node1
192.168.100.102 pg-node2
192.168.100.103 pg-node3
EOF

# On all nodes
sudo mkdir -p /var/lib/containers/postgres/{data/pgdata,data/etcd,config,logs}
sudo mkdir -p /var/lib/containers/etcd/data
# On all nodes
sudo chown -R 999:999 /var/lib/containers/postgres/data/pgdata
sudo chmod 700 /var/lib/containers/postgres/data/pgdata

# Keep config and logs accessible
sudo chmod 755 /var/lib/containers/postgres/config
sudo chmod 755 /var/lib/containers/postgres/logs


# On pg-node1
mkdir -p ~/patroni-build
cd ~/patroni-build
cat > Dockerfile <<'EOF'
FROM postgres:18

RUN apt-get update && \
    apt-get install -y python3 python3-pip python3-psycopg2 && \
    pip3 install --break-system-packages patroni[etcd] && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

USER postgres
EOF

# Build image
podman build -t localhost/patroni-postgres:18 .

# Save image to tar
podman save -o patroni-postgres-18.tar localhost/patroni-postgres:18

# Copy to other nodes
scp patroni-postgres-18.tar pg-node2:/tmp/
scp patroni-postgres-18.tar pg-node3:/tmp/

# On pg-node2 and pg-node3, load the image:
# podman load -i /tmp/patroni-postgres-18.tar

## On pg-node1 (192.168.100.101):
sudo cat > /etc/containers/systemd/etcd.container <<'EOF'
[Unit]
Description=etcd Container
After=network-online.target

[Container]
Image=quay.io/coreos/etcd:v3.5.12
ContainerName=etcd
Network=host
Volume=/var/lib/containers/etcd/data:/etcd-data:Z
Environment=ETCD_NAME=etcd1
Environment=ETCD_DATA_DIR=/etcd-data
Environment=ETCD_LISTEN_PEER_URLS=http://192.168.100.101:2380
Environment=ETCD_LISTEN_CLIENT_URLS=http://192.168.100.101:2379,http://127.0.0.1:2379
Environment=ETCD_INITIAL_ADVERTISE_PEER_URLS=http://192.168.100.101:2380
Environment=ETCD_ADVERTISE_CLIENT_URLS=http://192.168.100.101:2379
Environment=ETCD_INITIAL_CLUSTER=etcd1=http://192.168.100.101:2380,etcd2=http://192.168.100.102:2380,etcd3=http://192.168.100.103:2380
Environment=ETCD_INITIAL_CLUSTER_STATE=new
Environment=ETCD_INITIAL_CLUSTER_TOKEN=etcd-cluster-postgres

[Service]
Restart=always

[Install]
WantedBy=multi-user.target default.target
EOF

#On pg-node2 (192.168.100.102):
sudo cat > /etc/containers/systemd/etcd.container <<'EOF'
[Unit]
Description=etcd Container
After=network-online.target

[Container]
Image=quay.io/coreos/etcd:v3.5.12
ContainerName=etcd
Network=host
Volume=/var/lib/containers/etcd/data:/etcd-data:Z
Environment=ETCD_NAME=etcd2
Environment=ETCD_DATA_DIR=/etcd-data
Environment=ETCD_LISTEN_PEER_URLS=http://192.168.100.102:2380
Environment=ETCD_LISTEN_CLIENT_URLS=http://192.168.100.102:2379,http://127.0.0.1:2379
Environment=ETCD_INITIAL_ADVERTISE_PEER_URLS=http://192.168.100.102:2380
Environment=ETCD_ADVERTISE_CLIENT_URLS=http://192.168.100.102:2379
Environment=ETCD_INITIAL_CLUSTER=etcd1=http://192.168.100.101:2380,etcd2=http://192.168.100.102:2380,etcd3=http://192.168.100.103:2380
Environment=ETCD_INITIAL_CLUSTER_STATE=new
Environment=ETCD_INITIAL_CLUSTER_TOKEN=etcd-cluster-postgres

[Service]
Restart=always

[Install]
WantedBy=multi-user.target default.target
EOF

## On pg-node3 (192.168.100.103):
sudo cat > /etc/containers/systemd/ectd.container  <<'EOF'
[Unit]
Description=etcd Container
After=network-online.target

[Container]
Image=quay.io/coreos/etcd:v3.5.12
ContainerName=etcd
Network=host
Volume=/var/lib/containers/etcd/data:/etcd-data:Z
Environment=ETCD_NAME=etcd3
Environment=ETCD_DATA_DIR=/etcd-data
Environment=ETCD_LISTEN_PEER_URLS=http://192.168.100.103:2380
Environment=ETCD_LISTEN_CLIENT_URLS=http://192.168.100.103:2379,http://127.0.0.1:2379
Environment=ETCD_INITIAL_ADVERTISE_PEER_URLS=http://192.168.100.103:2380
Environment=ETCD_ADVERTISE_CLIENT_URLS=http://192.168.100.103:2379
Environment=ETCD_INITIAL_CLUSTER=etcd1=http://192.168.100.101:2380,etcd2=http://192.168.100.102:2380,etcd3=http://192.168.100.103:2380
Environment=ETCD_INITIAL_CLUSTER_STATE=new
Environment=ETCD_INITIAL_CLUSTER_TOKEN=etcd-cluster-postgres

[Service]
Restart=always

[Install]
WantedBy=multi-user.target default.target
EOF

# On all nodes - run within 30 seconds of each other
sudo systemctl daemon-reload
sudo systemctl start etcd.service

# Wait 15 seconds after starting all nodes
sleep 15

# On any node - check cluster health
podman exec etcd etcdctl endpoint health
podman exec etcd etcdctl member list


#Expected output:

127.0.0.1:2379 is healthy: successfully committed proposal: took = 2.8ms
etcd1, started, etcd1, http://192.168.100.101:2380, http://192.168.100.101:2379, false
etcd2, started, etcd2, http://192.168.100.102:2380, http://192.168.100.102:2379, false
etcd3, started, etcd3, http://192.168.100.103:2380, http://192.168.100.103:2379, false

###############################################################################################
### : Create Patroni Config Files
#On pg-node1:
sudo cat > /var/lib/containers/postgres/config/patroni.yml <<'EOF'
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
      parameters:
        wal_level: replica
        hot_standby: "on"
        wal_keep_size: 1GB
        max_wal_senders: 10
        max_replication_slots: 10
        wal_log_hints: "on"

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - host replication replicator 0.0.0.0/0 md5
    - host all all 0.0.0.0/0 md5

  users:
    admin:
      password: admin123
      options:
        - createrole
        - createdb

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 192.168.100.101:5432
  data_dir: /var/lib/postgresql/data
  pgpass: /tmp/pgpass
  authentication:
    replication:
      username: replicator
      password: replicator123
    superuser:
      username: postgres
      password: postgres123
  parameters:
    unix_socket_directories: '/var/run/postgresql'

tags:
    nofailover: false
    noloadbalance: false
    clonefrom: false
    nosync: false

EOF

##Node2
sudo cat > /var/lib/containers/postgres/config/patroni.yml <<'EOF'
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
      parameters:
        wal_level: replica
        hot_standby: "on"
        wal_keep_size: 1GB
        max_wal_senders: 10
        max_replication_slots: 10
        wal_log_hints: "on"

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - host replication replicator 0.0.0.0/0 md5
    - host all all 0.0.0.0/0 md5

  users:
    admin:
      password: admin123
      options:
        - createrole
        - createdb

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 192.168.100.102:5432
  data_dir: /var/lib/postgresql/data
  pgpass: /tmp/pgpass
  authentication:
    replication:
      username: replicator
      password: replicator123
    superuser:
      username: postgres
      password: postgres123
  parameters:
    unix_socket_directories: '/var/run/postgresql'

tags:
    nofailover: false
    noloadbalance: false
    clonefrom: false
    nosync: false

EOF

# node3
sudo cat > /var/lib/containers/postgres/config/patroni.yml <<'EOF'

scope: postgres-cluster
namespace: /db/
name: pg-node3

restapi:
  listen: 0.0.0.0:8008
  connect_address: 192.168.100.103:8008

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
      parameters:
        wal_level: replica
        hot_standby: "on"
        wal_keep_size: 1GB
        max_wal_senders: 10
        max_replication_slots: 10
        wal_log_hints: "on"

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - host replication replicator 0.0.0.0/0 md5
    - host all all 0.0.0.0/0 md5

  users:
    admin:
      password: admin123
      options:
        - createrole
        - createdb

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 192.168.100.103:5432
  data_dir: /var/lib/postgresql/data
  pgpass: /tmp/pgpass
  authentication:
    replication:
      username: replicator
      password: replicator123
    superuser:
      username: postgres
      password: postgres123
  parameters:
    unix_socket_directories: '/var/run/postgresql'

tags:
    nofailover: false
    noloadbalance: false
    clonefrom: false
    nosync: false

EOF

##########

### Create Patroni Quadlet on All Nodes
# On pg-node1:
sudo cat > /etc/containers/systemd/patroni.container <<'EOF'
[Unit]
Description=Patroni PostgreSQL HA - Node 1
After=etcd.service
Requires=etcd.service

[Container]
Image=localhost/patroni-postgres:18
ContainerName=patroni
Network=host
Volume=/var/lib/containers/postgres/data/pgdata:/var/lib/postgresql/data:                                                                               Z
Volume=/var/lib/containers/postgres/config/patroni.yml:/etc/patroni.yml:z
Volume=/var/lib/containers/postgres/logs:/var/log/patroni:z
Exec=patroni /etc/patroni.yml

[Service]
Restart=always
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

## On pg-node32
sudo cat > /etc/containers/systemd/patroni.container <<'EOF'
[Unit]
Description=Patroni PostgreSQL HA - Node 2
After=etcd.service
Requires=etcd.service

[Container]
Image=localhost/patroni-postgres:18
ContainerName=patroni
Network=host
Volume=/var/lib/containers/postgres/data/pgdata:/var/lib/postgresql/data:                                                                               Z
Volume=/var/lib/containers/postgres/config/patroni.yml:/etc/patroni.yml:z
Volume=/var/lib/containers/postgres/logs:/var/log/patroni:z
Exec=patroni /etc/patroni.yml

[Service]
Restart=always
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

## On pg-node3
sudo cat > /etc/containers/systemd/patroni.container <<'EOF'

[Unit]
Description=Patroni PostgreSQL HA - Node 3
After=etcd.service
Requires=etcd.service

[Container]
Image=localhost/patroni-postgres:18
ContainerName=patroni
Network=host
Volume=/var/lib/containers/postgres/data/pgdata:/var/lib/postgresql/data:                                                                               Z
Volume=/var/lib/containers/postgres/config/patroni.yml:/etc/patroni.yml:z
Volume=/var/lib/containers/postgres/logs:/var/log/patroni:z
Exec=patroni /etc/patroni.yml

[Service]
Restart=always
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
## Operation
# On all nodes
sudo chown -R 999:999 /var/lib/containers/postgres/data/pgdata
sudo chmod 700 /var/lib/containers/postgres/data/pgdata

# Keep config and logs accessible
sudo chmod 755 /var/lib/containers/postgres/config
sudo chmod 755 /var/lib/containers/postgres/logs

#Note: User 999 is the default postgres user ID inside the container.

#Reload and Start
#bash# On all nodes
sudo systemctl daemon-reload
Start pg-node1 first (the leader):
#bash# On pg-node1
sudo systemctl start patroni.service

# Watch logs
sudo journalctl -u patroni.service -f
#Wait 30 seconds until pg-node1 is fully initialized, then start the replicas:
#bash# On pg-node2
sudo systemctl start patroni.service

# On pg-node3
sudo systemctl start patroni.service


##Step 5: Verify
#bash# Check cluster status
podman exec patroni patronictl -c /etc/patroni.yml list

# Check PostgreSQL is running
podman exec patroni psql -U postgres -c "SELECT version();"




##################
## Quick Commands Reference
 # Check cluster status
podman exec patroni patronictl -c /etc/patroni.yml list

# Manual switchover
podman exec patroni patronictl -c /etc/patroni.yml switchover

# Restart PostgreSQL
podman exec patroni patronictl -c /etc/patroni.yml restart postgres-cluster pg-node1

# Reload configuration
podman exec patroni patronictl -c /etc/patroni.yml reload postgres-cluster pg-node1

# Check etcd health
podman exec etcd etcdctl endpoint health

# View logs
sudo journalctl -u patroni.service -f
sudo journalctl -u etcd.service -f

# Check if etcd is listening
sudo netstat -tlnp | grep 237

#Quick Verification Script
#Run this on pg-node1 to check everything:
#!/bin/bash
echo "=== Checking etcd ==="
sudo systemctl status etcd.service --no-pager | head -5
podman exec etcd etcdctl endpoint health 2>&1

echo ""
echo "=== Checking etcd cluster ==="
podman exec etcd etcdctl member list 2>&1

echo ""
echo "=== Checking Patroni ==="
sudo systemctl status patroni.service --no-pager | head -5

echo ""
echo "=== Recent Patroni logs ==="
sudo journalctl -u patroni.service -n 10 --no-pager

curl -s http://192.168.100.101:8008/cluster
:'
{"members": [{"name": "pg-node1", "role": "leader", "state": "running", "api_url": "http://192.168.100.101:8008/patroni", "host": "192.168.100.101", "port": 5432, "timeline": 2}, {"name": "pg-node2", "role": "replica", "state": "running", "api_url": "http://192.168.100.102:8008/patroni", "host": "192.168.100.102", "port": 5432, "timeline": 1, "receive_lag": 14486448, "receive_lsn": "0/4260000", "replay_lag": 16976656, "replay_lsn": "0/40000A0", "lag": 14486448, "lsn": "0/4260000"}, {"name": "pg-node3", "role": "replica", "state": "running", "api_url": "http://192.168.100.103:8008/patroni", "host": "192.168.100.103", "port": 5432, "timeline": 1, "receive_lag": 0, "receive_lsn": "0/6000000", "replay_lag": 0, "replay_lsn": "0/60000A0", "lag": 0, "lsn": "0/60000A0"}], "scope": "postgres-cluster"}[
'

# Check specific node
curl -s http://192.168.100.101:8008/patroni
: '
{"state": "running", "postmaster_start_time": "2026-02-11 17:44:32.225029+00:00", "role": "primary", "server_version": 180001, "xlog": {"location": 84085680}, "timeline": 2, "dcs_last_seen": 1770895223, "database_system_identifier": "7605662808013144081", "patroni": {"version": "4.1.0", "scope": "postgres-cluster", "name": "pg-node1"}}
'

# Get leader
curl -s http://192.168.100.101:8008/leader
:'
{"state": "running", "postmaster_start_time": "2026-02-11 17:44:32.225029+00:00", "role": "primary", "server_version": 180001, "xlog": {"location": 84085680}, "timeline": 2, "dcs_last_seen": 1770895253, "database_system_identifier": "7605662808013144081", "patroni": {"version": "4.1.0", "scope": "postgres-cluster", "name": "pg-node1"}}
'

 # Get timeline/status
curl -s http://192.168.100.101:8008/health
:'
{"state": "running", "postmaster_start_time": "2026-02-11 17:44:32.225029+00:00", "role": "primary", "server_version": 180001, "xlog": {"location": 84085680}, "timeline": 2, "dcs_last_seen": 1770895283, "database_system_identifier": "7605662808013144081", "patroni": {"version": "4.1.0", "scope": "postgres-cluster", "name": "pg-node1"}}
'

### How to simulation failover for check postgres HA?
podman exec patroni patronictl -c /etc/patroni.yml list
+ Cluster: postgres-cluster (7605662808013144081) ----+-------------+-----+------------+-----+
| Member   | Host            | Role    | State   | TL | Receive LSN | Lag | Replay LSN | Lag |
+----------+-----------------+---------+---------+----+-------------+-----+------------+-----+
| pg-node1 | 192.168.100.101 | Leader  | running |  2 |             |     |            |     |
| pg-node2 | 192.168.100.102 | Replica | running |  1 |   0/4260000 |  14 |  0/40000A0 |  16 |
| pg-node3 | 192.168.100.103 | Replica | running |  1 |   0/6000000 |   0 |  0/60000A0 |   0 |
+----------+-----------------+---------+---------+----+-------------+-----+------------+-----+
##  Perform a switchover
# This will gracefully demote the leader and promote a replica
sudo podman exec -it patroni patronictl -c /etc/patroni.yml switchover --leader pg-node1 --candidate pg-node2

## Simulate Real Failure (Crash Test)
# On the current leader node (e.g., pg-node1)
sudo systemctl stop patroni
# On any remaining node, watch logs in real-time
sudo journalctl -u patroni -f

# Or check cluster status
curl -s http://192.168.100.102:8008/leader   
:'
curl -s http://192.168.100.102:8008/leader
{"state": "running", "postmaster_start_time": "2026-02-11 17:46:20.418782+00:00", "role": "replica", "server_version": 180001, "xlog": {"received_location": 69599232, "replayed_location": 67109024, "replayed_timestamp": null, "paused": false}, "timeline": 1, "dcs_last_seen": 1770895786, "database_system_identifier": "7605662808013144081", "patroni": {"version": "4.1.0", "scope": "postgres-cluster", "name": "pg-node2"}}
'

curl -s http://192.168.100.103:8008/leader
:'
{"state": "running", "postmaster_start_time": "2026-02-11 17:46:23.596981+00:00", "role": "primary", "server_version": 180001, "xlog": {"location": 100663776}, "timeline": 3, "dcs_last_seen": 1770895816, "database_system_identifier": "7605662808013144081", "patroni": {"version": "4.1.0", "scope": "postgres-cluster", "name": "pg-node3"}}
'
sudo podman exec -it patroni patronictl -c /etc/patroni.yml list
:'
 sudo podman exec -it patroni patronictl -c /etc/patroni.yml list
+ Cluster: postgres-cluster (7605662808013144081) ----+-------------+-----+------------+-----+
| Member   | Host            | Role    | State   | TL | Receive LSN | Lag | Replay LSN | Lag |
+----------+-----------------+---------+---------+----+-------------+-----+------------+-----+
| pg-node2 | 192.168.100.102 | Replica | running |  1 |   0/4260000 |  30 |  0/40000A0 |  32 |
| pg-node3 | 192.168.100.103 | Leader  | running |  3 |             |     |            |     |
+----------+-----------------+---------+---------+----+-------------+-----+------------+-----+
'
## Restore the failed node:
# On pg-node1
sudo systemctl start patroni
:'
sudo podman exec -it patroni patronictl -c /etc/patroni.yml list
+ Cluster: postgres-cluster (7605662808013144081) +----+-------------+-----+------------+-----+
| Member   | Host            | Role    | State    | TL | Receive LSN | Lag | Replay LSN | Lag |
+----------+-----------------+---------+----------+----+-------------+-----+------------+-----+
| pg-node1 | 192.168.100.101 | Replica | starting |    |     unknown |     |    unknown |     |
| pg-node2 | 192.168.100.102 | Replica | running  |  1 |   0/4260000 |  30 |  0/40000A0 |  32 |
| pg-node3 | 192.168.100.103 | Leader  | running  |  3 |             |     |            |     |
+----------+-----------------+---------+----------+----+-------------+-----+------------+-----+
'
# if still starting can be force rejoin cluster
# On pg-node1, check what's happening
sudo journalctl -u patroni -n 50 --no-pager

# Force pg-node1 to rejoin as replica
sudo podman exec -it patroni patronictl -c /etcpatroni.yml reinit postgres-cluster pg-node1

# If reinit doesn't work, restart patroni
sudo systemctl restart patroni

# Wait 30 seconds and check again
sudo podman exec -it patroni patronictl -c /etc/patroni.yml list
:'
+ Cluster: postgres-cluster (7605662808013144081) -+----+-------------+-----+------------+-----+
| Member   | Host            | Role    | State     | TL | Receive LSN | Lag | Replay LSN | Lag |
+----------+-----------------+---------+-----------+----+-------------+-----+------------+-----+
| pg-node1 | 192.168.100.101 | Replica | streaming |  3 |   0/8000060 |   0 |  0/8000060 |   0 |
| pg-node2 | 192.168.100.102 | Replica | running   |  1 |   0/4260000 |  62 |  0/40000A0 |  64 |
| pg-node3 | 192.168.100.103 | Leader  | running   |  3 |             |     |            |     |
+----------+-----------------+---------+-----------+----+-------------+-----+------------+-----+
'
## However, pg-node2 has a problem - it's stuck on timeline 1 with 64 MB lag. This needs to be fixed.
sudo podman exec -it patroni patronictl -c /etc/patroni.yml reinit postgres-cluster pg-node2

## Quick Verification Test:
# 1. Check leader
curl -s http://192.168.100.103:8008/leader

# 2. Test replication chain
sudo podman exec -it patroni psql -U postgres -h 192.168.100.103 -c "CREATE TABLE IF NOT EXISTS ha_working (id serial, status text, check_time timestamp DEFAULT now());"
sudo podman exec -it patroni psql -U postgres -h 192.168.100.103 -c "INSERT INTO ha_working (status) VALUES ('ALL GOOD');"

# 3. Verify on both replicas
sudo podman exec -it patroni psql -U postgres -h 192.168.100.101 -c "SELECT * FROM ha_working ORDER BY id DESC LIMIT 1;"
sudo podman exec -it patroni psql -U postgres -h 192.168.100.102 -c "SELECT * FROM ha_working ORDER BY id DESC LIMIT 1;"


ss -ntlp
:'
State         Recv-Q        Send-Q                 Local Address:Port               Peer Address:Port        Process
LISTEN        0             128                          0.0.0.0:22                      0.0.0.0:*            users:(("sshd",pid=755,fd=3))
LISTEN        0             4096                       127.0.0.1:2379                    0.0.0.0:*            users:(("etcd",pid=9116,fd=9))
LISTEN        0             200                          0.0.0.0:5432                    0.0.0.0:*            users:(("postgres",pid=9512,fd=6))
LISTEN        0             4096                 192.168.100.102:2379                    0.0.0.0:*            users:(("etcd",pid=9116,fd=8))
LISTEN        0             4096                 192.168.100.102:2380                    0.0.0.0:*            users:(("etcd",pid=9116,fd=7))
LISTEN        0             5                            0.0.0.0:8008                    0.0.0.0:*            users:(("patroni",pid=9478,fd=9))
LISTEN        0             128                             [::]:22                         [::]:*            users:(("sshd",pid=755,fd=4))
'





#####################################################################
##########
Step 1: Stop Everything on All Nodes
bash# On all nodes
sudo systemctl stop patroni.service
sudo systemctl stop etcd.service
Step 2: Clean Up Data Directories
bash# On all nodes
sudo podman stop -a
sudo podman rm -af

# Remove old data (important!)
sudo rm -rf /var/lib/containers/postgres/data/pgdata/*
sudo rm -rf /var/lib/containers/postgres/data/etcd/*

# Recreate with proper permissions
sudo mkdir -p /var/lib/containers/postgres/data/{pgdata,etcd}
sudo chmod -R 777 /var/lib/containers/postgres


###################################################################

######################################################################################################################
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