#On VM1 (Certificate Authority):
# Create CA directory
sudo mkdir -p /opt/elasticsearch/certs/ca
cd /opt/elasticsearch/certs/ca

# Generate CA private key
sudo openssl genrsa -out ca.key 4096

# Generate CA certificate
sudo openssl req -new -x509 -key ca.key -out ca.crt -days 3650 \
  -subj "/C=EG/ST=Cairo/L=Cairo/O=LinkDev/CN=Elasticsearch CA"

# Create certificate for each node
for node in node1 node2 node3; do
  # Generate private key
  sudo openssl genrsa -out ${node}.key 2048
  
  # Create CSR
  sudo openssl req -new -key ${node}.key -out ${node}.csr \
    -subj "/C=EG/ST=Cairo/L=Cairo/O=LinkDev/CN=${node}.linkdev.net"
  
  # Sign certificate
  sudo openssl x509 -req -in ${node}.csr -CA ca.crt -CAkey ca.key \
    -CAcreateserial -out ${node}.crt -days 3650
  
  # Create PKCS12 keystore (for Elasticsearch)
  sudo openssl pkcs12 -export -in ${node}.crt -inkey ${node}.key \
    -out ${node}.p12 -passout pass:password -name "elasticsearch"
  
  # Create JKS keystore
  sudo keytool -importkeystore -deststorepass password -destkeypass password \
    -destkeystore ${node}.jks -srckeystore ${node}.p12 -srcstoretype PKCS12 \
    -srcstorepass password -alias "elasticsearch"
done

#You need to create a truststore.jks that contains the CA certificate, which all nodes will trust. Here's the complete process:

# Create truststore.jks - THIS IS THE MISSING STEP!
echo "Creating truststore.jks..."
sudo keytool -import -trustcacerts -alias ca \
  -file ca.crt \
  -keystore truststore.jks \
  -storepass password -noprompt

echo "Verifying truststore contents..."
sudo keytool -list -v -keystore truststore.jks -storepass password


# Copy certificates to other nodes
vm1=192.168.100.57
vm2=192.168.100.58
vm3=192.168.100.59
for vm in vm2 vm3; do
  sudo scp ca.crt node*.crt node*.key node*.jks \
    root@${vm}:/opt/elasticsearch/certs/
done