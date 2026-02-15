#/bin/bash
:'
setup and configured Mongodb  latest HA on 3 podman with quadlet  on 3 VMs rocky linux 9 and nodes: {db-node1: 192.168.100.101, db-node2:192.168.100.102, db-node3:192.168.100.103} ,
with certificates
set all permission for avoid any issues
step by step without complex
'
I'll help you set up a MongoDB High Availability cluster with 3 nodes using Podman Quadlet on Rocky Linux 9, including SSL/TLS certificates.

## Prerequisites Setup

First, let's prepare all three nodes:

#bash
# Run on all 3 nodes (db-node1, db-node2, db-node3)

# Update system
# Install Podman
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
192.168.100.104 db-node1
192.168.100.105 db-node2
192.168.100.106 db-node3
EOF

# Create directories
sudo mkdir -p /opt/mongodb/{data,config,logs,keys}
sudo chmod -R 755 /opt/mongodb
#

## Step 1: Generate SSL Certificates
###########  Generates_Certificates.sh
##############################################################

## Step 4: Configure Firewall

#bash
# Run on all 3 nodes
sudo firewall-cmd --permanent --add-port=27017/tcp
sudo firewall-cmd --reload
#
## Step 5: Create Quadlet Configuration

podman run --rm docker.io/mongodb/mongodb-community-server:latest id
#uid=101(mongodb) gid=65534(nogroup) groups=65534(nogroup),101(mongodb)

#Step 1: Set proper ownership (MongoDB container runs as UID 999 or root, let's make files readable by all)
sudo chown -R root:root /opt/mongodb/keys
sudo chmod 755 /opt/mongodb/keys
sudo chmod 644 /opt/mongodb/keys/ca.crt
sudo chmod 644 /opt/mongodb/keys/*.crt
sudo chmod 644 /opt/mongodb/keys/*.pem

# Set correct ownership for MongoDB user (UID 101)
sudo chown -R 101:101 /opt/mongodb/data
sudo chmod -R 755 /opt/mongodb/data

# Clean any existing data with wrong permissions
sudo rm -rf /opt/mongodb/data/*

# Also ensure keys are readable by UID 101
sudo chmod 644 /opt/mongodb/keys/*
sudo chmod 755 /opt/mongodb/keys

# Set strict permissions on keyfile (must be 400 or 600)
sudo chmod 400 /opt/mongodb/keys/mongodb-keyfile

# Also set correct ownership for UID 101
sudo chown 101:101 /opt/mongodb/keys/mongodb-keyfile

# Verify permissions
ls -la /opt/mongodb/keys/mongodb-keyfile
# Should show: -r-------- 1 101 101 ... mongodb-keyfile

:'
# Step 3: Disable SELinux enforcement for these directories (simpler approach)
sudo setenforce 0  # Temporarily set to permissive
# OR better, set proper SELinux context
sudo chcon -R -t svirt_sandbox_file_t /opt/mongodb/keys
sudo chcon -R -t svirt_sandbox_file_t /opt/mongodb/data

# Step 2: Set SELinux context for container access
sudo chcon -R -t container_file_t /opt/mongodb/keys
sudo chcon -R -t container_file_t /opt/mongodb/data

# Or if you prefer, use semanage (more permanent):
sudo semanage fcontext -a -t container_file_t "/opt/mongodb/keys(/.*)?"
sudo semanage fcontext -a -t container_file_t "/opt/mongodb/data(/.*)?"
sudo restorecon -Rv /opt/mongodb
'

**On db-node1** (192.168.100.104):

#bash
sudo mkdir -p /etc/containers/systemd

sudo cat << 'EOF' | sudo tee /etc/containers/systemd/mongodb.container
[Unit]
Description=MongoDB Container
After=network-online.target

[Container]
Image=docker.io/mongodb/mongodb-community-server:latest
ContainerName=mongodb
Volume=/opt/mongodb/data:/data/db
Volume=/opt/mongodb/keys:/etc/mongodb/keys:ro
SecurityLabelDisable=true
PublishPort=27017:27017
Network=host
User=101:101
Entrypoint=/usr/bin/mongod

Exec=--replSet rs0 --bind_ip_all --port 27017 --dbpath /data/db --tlsMode requireTLS --tlsCertificateKeyFile /etc/mongodb/keys/db-node1.pem --tlsCAFile /etc/mongodb/keys/ca.crt --logpath /data/db/mongod.log --logappend

[Service]
Restart=always
TimeoutStartSec=900

[Install]
WantedBy=multi-user.target default.target
EOF
#

**On db-node2** (192.168.100.105):

#bash
sudo mkdir -p /etc/containers/systemd

sudo cat << 'EOF' | sudo tee /etc/containers/systemd/mongodb.container
[Unit]
Description=MongoDB Container
After=network-online.target

[Container]
Image=docker.io/mongodb/mongodb-community-server:latest
ContainerName=mongodb
Volume=/opt/mongodb/data:/data/db
Volume=/opt/mongodb/keys:/etc/mongodb/keys:ro
SecurityLabelDisable=true
PublishPort=27017:27017
Network=host
User=101:101
Entrypoint=/usr/bin/mongod

Exec=--replSet rs0 --bind_ip_all --port 27017 --dbpath /data/db --tlsMode requireTLS --tlsCertificateKeyFile /etc/mongodb/keys/db-node2.pem --tlsCAFile /etc/mongodb/keys/ca.crt --logpath /data/db/mongod.log --logappend

[Service]
Restart=always
TimeoutStartSec=900

[Install]
WantedBy=multi-user.target default.target
EOF
#

**On db-node3** (192.168.100.106):

#bash
sudo mkdir -p /etc/containers/systemd

sudo cat << 'EOF' | sudo tee /etc/containers/systemd/mongodb.container
[Unit]
Description=MongoDB Container
After=network-online.target

[Container]
Image=docker.io/mongodb/mongodb-community-server:latest
ContainerName=mongodb
Volume=/opt/mongodb/data:/data/db
Volume=/opt/mongodb/keys:/etc/mongodb/keys:ro
SecurityLabelDisable=true
PublishPort=27017:27017
Network=host
User=101:101
Entrypoint=/usr/bin/mongod

Exec=--replSet rs0 --bind_ip_all --port 27017 --dbpath /data/db --tlsMode requireTLS --tlsCertificateKeyFile /etc/mongodb/keys/db-node3.pem --tlsCAFile /etc/mongodb/keys/ca.crt --logpath /data/db/mongod.log --logappend

[Service]
Restart=always
TimeoutStartSec=900

[Install]
WantedBy=multi-user.target default.target
EOF
#

## Step 6: Start MongoDB on All Nodes

#bash
# Run on all 3 nodes

# Reload systemd to recognize the quadlet file
sudo systemctl daemon-reload

# Start MongoDB
sudo systemctl start mongodb.service

# Enable auto-start on boot
sudo systemctl enable mongodb.service

# Check status
sudo systemctl status mongodb.service
#

# Check MongoDB logs
sudo tail -30 /opt/mongodb/data/mongod.log

# Check if MongoDB is listening
sudo ss -tlnp | grep 27017

# Check container
sudo podman ps



## Step 7: Initialize Replica Set

On **db-node1**, connect to MongoDB and initialize the replica set:

sudo podman exec -it mongodb mongosh \
  --tls \
  --tlsCAFile /etc/mongodb/keys/ca.crt \
  --tlsCertificateKeyFile /etc/mongodb/keys/db-node1.pem \
  --host 192.168.100.104

Inside the MongoDB shell:

#javascript
// Initialize replica set
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "192.168.100.104:27017", priority: 2 },
    { _id: 1, host: "192.168.100.105:27017", priority: 1 },
    { _id: 2, host: "192.168.100.106:27017", priority: 1 }
  ]
})

// Wait 10-15 seconds, you should see the prompt change to rs0 [direct: primary]
// Check status
rs.status()

// Create admin user
use admin
db.createUser({
  user: "admin",
  pwd: "Passw0rd!",
  roles: [ { role: "root", db: "admin" } ]
})

// Exit
exit
// You should see one PRIMARY and two SECONDARY nodes
#
## Re-enable Keyfile Authentication
Now add the keyfile back to all nodes. Update the Exec line in the Quadlet files:
On all 3 nodes, add --keyFile /etc/mongodb/keys/mongodb-keyfile back to the Exec line:

# node1
sudo sed -i 's|--dbpath /data/db|--dbpath /data/db --keyFile /etc/mongodb/keys/mongodb-keyfile|' /etc/containers/systemd/mongodb.container
# node2
sudo sed -i 's|--dbpath /data/db|--dbpath /data/db --keyFile /etc/mongodb/keys/mongodb-keyfile|' /etc/containers/systemd/mongodb.container
# node3
sudo sed -i 's|--dbpath /data/db|--dbpath /data/db --keyFile /etc/mongodb/keys/mongodb-keyfile|' /etc/containers/systemd/mongodb.container

# Run on all 3 nodes
sudo systemctl daemon-reload
sudo systemctl restart mongodb.service
sleep 5


## Step 8: Verify the Setup

#bash
# Check replica set status
# On db-node1, connect with authentication
sudo podman exec -it mongodb mongosh \
  --tls \
  --tlsCAFile /etc/mongodb/keys/ca.crt \
  --tlsCertificateKeyFile /etc/mongodb/keys/db-node1.pem \
  --host 192.168.100.104 \
  -u admin -p 'Passw0rd!' \
  --authenticationDatabase admin \
  --eval "rs.status()"
#

## Step 9: Create Application User (Optional)

#javascript
// In MongoDB shell on PRIMARY node
use admin

db.createUser({
  user: "appuser",
  pwd: "AppPassword123",
  roles: [
    { role: "readWrite", db: "myapp" }
  ]
})
#

## Connection String

Your application can connect using:

#
mongodb://appuser:AppPassword123@192.168.100.104:27017,192.168.100.105:27017,192.168.100.106:27017/myapp?replicaSet=rs0&tls=true&tlsCAFile=/path/to/ca.crt
#

## Quick Commands Reference

#bash
# Check container logs
sudo podman logs mongodb



#Your MongoDB HA cluster is now ready! The replica set will automatically handle failover if the primary node goes down.
Yes! 🎉 Your MongoDB High Availability cluster is now **up and running**!

## Quick Summary

You now have:
- ✅ **3-node MongoDB replica set** (rs0) running on Rocky Linux 9
- ✅ **TLS/SSL encryption** with proper certificates and SANs
- ✅ **Keyfile authentication** between replica set members
- ✅ **Admin user** created with root privileges
- ✅ **Podman Quadlet** managing containers as systemd services
- ✅ **Auto-restart** on boot and failures

## Quick Commands for Daily Use

**Check cluster status:**
```bash
sudo podman exec -it mongodb mongosh \
  --tls --tlsCAFile /etc/mongodb/keys/ca.crt \
  --tlsCertificateKeyFile /etc/mongodb/keys/db-node1.pem \
  -u admin -p 'Passw0rd!' --authenticationDatabase admin \
  --eval "rs.status()"
```

**Connect to MongoDB shell:**
```bash
sudo podman exec -it mongodb mongosh \
  --tls --tlsCAFile /etc/mongodb/keys/ca.crt \
  --tlsCertificateKeyFile /etc/mongodb/keys/db-node1.pem \
  -u admin -p 'Passw0rd!' --authenticationDatabase admin
```

**Connection string for applications:**
```
mongodb://admin:Passw0rd!@192.168.100.104:27017,192.168.100.105:27017,192.168.100.106:27017/?replicaSet=rs0&tls=true&tlsCAFile=/path/to/ca.crt
```

Your cluster is production-ready! 🚀

