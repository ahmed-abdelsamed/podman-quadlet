# Check service status
systemctl status etcd.service
systemctl status patroni.service

# Check logs
journalctl -u etcd.service -n 50
journalctl -u patroni.service -n 50

# Check Patroni cluster
podman exec patroni patronictl -c /etc/patroni/patroni.yml list


# in case failed docker image or chnage in yml after started patroni, recommenede:
# On all nodes
podman volume rm pg_data
podman volume create pg_data

systemctl reset-failed patroni.service
systemctl start patroni.service
journalctl -u patroni.service -f


# Check if etcd container is running
podman ps -a | grep etcd

# Check etcd service status
sudo systemctl status etcd.service

# Check logs if there's an issue
sudo journalctl -u etcd.service -n 50

# On pg-node3
sudo systemctl start etcd.service

# Wait a few seconds
sleep 5

# Check status
sudo systemctl status etcd.service

# Check cluster health
podman exec etcd etcdctl endpoint health --cluster

# Check member list
podman exec etcd etcdctl member list

# Should show all 3 members

# On pg-node3, stop etcd
sudo systemctl stop etcd.service

# Remove the data directory
sudo rm -rf /var/lib/containers/postgres/data/etcd/*

# Start it again
sudo systemctl start etcd.service

# Check logs
sudo journalctl -u etcd.service -f

# On pg-node1 FIRST
sudo systemctl start patroni.service

# Wait 30 seconds for it to initialize
sleep 30

# Check patroni logs
sudo journalctl -u patroni.service -f


# if still node 3 fails
# Remove the problematic member
podman exec etcd etcdctl member remove 9b636463d918b450
sudo systemctl stop etcd.service

# Update the quadlet file
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
Environment=ETCD_INITIAL_CLUSTER_STATE=existing
Volume=/var/lib/containers/postgres/data/etcd:/etcd-data:Z

[Service]
Restart=always

[Install]
WantedBy=multi-user.target default.target
EOF

sudo rm -rf /var/lib/containers/postgres/data/etcd/*
sudo systemctl daemon-reload
sudo systemctl start etcd.service


## if one node is failed
# On all nodes (104, 105, 106)
sudo systemctl stop etcd.service

# On all nodes
sudo rm -rf /var/lib/containers/postgres/data/etcd/*

# on all nodes
sudo systemctl start etcd.service

sleep 30

# Check on any node
podman exec etcd etcdctl member list
podman exec etcd etcdctl endpoint health --cluster


sudo journalctl -u patroni.service -n 50 --no-pager

### if any node fail for join 
# Stop patroni
sudo systemctl stop patroni.service

# Remove old PostgreSQL data (keep the directory structure)
sudo rm -rf /var/lib/containers/postgres/data/pg*
sudo rm -rf /var/lib/containers/postgres/data/PG*
sudo rm -rf /var/lib/containers/postgres/data/base
sudo rm -rf /var/lib/containers/postgres/data/global
sudo rm -rf /var/lib/containers/postgres/data/pg_*

# Or simply clear everything in data directory:
sudo find /var/lib/containers/postgres/data -mindepth 1 -maxdepth 1 ! -name 'etcd' -exec rm -rf {} \;

# Ensure correct permissions
sudo chown -R 999:999 /var/lib/containers/postgres/data
sudo chmod -R 700 /var/lib/containers/postgres/data

# Start patroni - it will clone from the leader
sudo systemctl start patroni.service

# Watch it clone
sudo journalctl -u patroni.service -f

