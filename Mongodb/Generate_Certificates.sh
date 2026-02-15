cd /opt/mongodb/keys

# Generate CA private key
sudo openssl genrsa -out ca.key 4096
sudo openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 \
  -out ca.crt -subj "/CN=MongoDB-CA/O=MyOrg/C=US"

# Generate certificates with SANs for each node
# Node 1
sudo openssl genrsa -out db-node1.key 4096

cat > db-node1.cnf <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name

[req_distinguished_name]

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = db-node1
DNS.2 = localhost
IP.1 = 192.168.100.104
IP.2 = 127.0.0.1
EOF

sudo openssl req -new -key db-node1.key -out db-node1.csr \
  -subj "/CN=db-node1/O=MyOrg/C=US" -config db-node1.cnf

sudo openssl x509 -req -in db-node1.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out db-node1.crt -days 3650 -sha256 \
  -extensions v3_req -extfile db-node1.cnf

sudo cat db-node1.key db-node1.crt > db-node1.pem

# Node 2
sudo openssl genrsa -out db-node2.key 4096

cat > db-node2.cnf <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name

[req_distinguished_name]

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = db-node2
DNS.2 = localhost
IP.1 = 192.168.100.105
IP.2 = 127.0.0.1
EOF

sudo openssl req -new -key db-node2.key -out db-node2.csr \
  -subj "/CN=db-node2/O=MyOrg/C=US" -config db-node2.cnf

sudo openssl x509 -req -in db-node2.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out db-node2.crt -days 3650 -sha256 \
  -extensions v3_req -extfile db-node2.cnf

sudo cat db-node2.key db-node2.crt > db-node2.pem

# Node 3
sudo openssl genrsa -out db-node3.key 4096

cat > db-node3.cnf <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name

[req_distinguished_name]

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = db-node3
DNS.2 = localhost
IP.1 = 192.168.100.106
IP.2 = 127.0.0.1
EOF

sudo openssl req -new -key db-node3.key -out db-node3.csr \
  -subj "/CN=db-node3/O=MyOrg/C=US" -config db-node3.cnf

sudo openssl x509 -req -in db-node3.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out db-node3.crt -days 3650 -sha256 \
  -extensions v3_req -extfile db-node3.cnf

sudo cat db-node3.key db-node3.crt > db-node3.pem


# On db-node1
sudo openssl rand -base64 756 | sudo tee /opt/mongodb/keys/mongodb-keyfile
sudo chmod 400 /opt/mongodb/keys/mongodb-keyfile

# From db-node1, copy to db-node2
sudo scp -r /opt/mongodb/keys/* root@192.168.100.105:/opt/mongodb/keys/

# From db-node1, copy to db-node3
sudo scp -r /opt/mongodb/keys/* root@192.168.100.106:/opt/mongodb/keys/



# Set permissions
sudo chmod 644 /opt/mongodb/keys/*.crt
sudo chmod 644 /opt/mongodb/keys/*.pem
sudo chmod 400 /opt/mongodb/keys/mongodb-keyfile
sudo chown 101:101 /opt/mongodb/keys/mongodb-keyfile