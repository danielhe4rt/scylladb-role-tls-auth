# Define the roles
# ROLES = developer devops

# Define the CA constants
CA_CERT = root_cert
CA_KEY = root_key
SERIAL_FILE = root_cert.srl
DIRECTORY = certificates

# Define Docker ScyllaDB Nodes
NODES = ws-scylla-1 ws-scylla-2 ws-scylla-3

# Define ScyllaDB Authentication Types
SCYLLA_CONFIG_FILE=/etc/scylla/scylla.yaml
SCYLLA_CONFIG_PATH=/etc/scylla

default = scylla-default.yaml
role = scylla-role-auth.yaml
password = scylla-auth.yaml

# Generate key pairs and certificates for each role
.PHONY: root-cert

# Rule to generate the root certificate

.PHONY: root-cert
root-cert:
	echo "Generating root certificate"
	openssl genpkey -algorithm RSA -out "./${DIRECTORY}/${CA_KEY}.pem" -pkeyopt rsa_keygen_bits:2048
	openssl req -x509 -new -key "./${DIRECTORY}/${CA_KEY}.pem" -days 3650 -out "./${DIRECTORY}/${CA_CERT}.pem" -subj "/CN=cassandra"
	
.PHONY: user-cert
user-cert: 
	@echo "Generating root certificate for $(role)"
	openssl genpkey -algorithm RSA -out "./${DIRECTORY}/$(role)_key.pem" -pkeyopt rsa_keygen_bits:2048
	openssl req -new -key "./${DIRECTORY}/$(role)_key.pem" -out "./${DIRECTORY}/$(role).csr" -subj "/CN=$(role)"
	openssl x509 -req -in "./${DIRECTORY}/$(role).csr" -CA "./${DIRECTORY}/${CA_CERT}.pem" -CAkey "./${DIRECTORY}/${CA_KEY}.pem" -CAcreateserial -out "./${DIRECTORY}/$(role)_cert.pem" -days 365

.PHONY: truststore
truststore:
	@echo "Generating truststore"
	rm -f "./${DIRECTORY}/truststore.pem"
	cat ./${DIRECTORY}/*_cert.pem > ./${DIRECTORY}/truststore.pem
	openssl x509 -in "./${DIRECTORY}/truststore.pem" -text -noout



.PHONY: auth-type
auth-type:
	@echo "Setting up ScyllaDB authentication type"
	
	@if [ -z "$(auth)" ]; then \
		echo "No auth type selected. Try with: no-auth | password | role-cert"; \
		exit 1; \
	fi

	@if [ "$(auth)" != "default" ] && [ "$(auth)" != "password" ] && [ "$(auth)" != "role" ]; then \
		echo "Invalid auth type. Try with: no-auth | password | role-cert"; \
		exit 1; \
	fi

	@$(eval AUTH_TYPE=$(value $(auth)))

	@echo "Auth selected type: $(AUTH_TYPE)"

	@for node in ${NODES}; do \
		echo "Processing $$node..."; \
		docker exec -it $$node supervisorctl stop scylla; \
		docker exec -it $$node sed -i 's/# authenticator:/authenticator:/g' ${SCYLLA_CONFIG_FILE}; \
		docker exec -it $$node cat ${SCYLLA_CONFIG_FILE} | grep authenticator:; \
		docker exec -it $$node rm -f ${SCYLLA_CONFIG_FILE}; \
		docker exec -it $$node cp ${SCYLLA_CONFIG_PATH}/configs/$(AUTH_TYPE) ${SCYLLA_CONFIG_FILE}; \
		docker exec -it $$node cat ${SCYLLA_CONFIG_FILE} | grep authenticator:; \
		docker exec -it $$node supervisorctl start scylla; \
	done

# Clean up generated files
.PHONY: setup
setup:
	echo "Setting up the environment"
	rm -rf ./${DIRECTORY}
	mkdir -p ${DIRECTORY}
	@$(MAKE) root-cert 
	@$(MAKE) user-cert role=developer
	@$(MAKE) truststore
	@echo "\n\nDone! Now you can start your ScyllaDB cluster via docker-compose."


.PHONY: create-role-cql
create-role-cql:
	@echo "Creating role $(role) in docker-cql"
	for node in ${NODES}; do \
		echo "Processing $$node..."; \
		docker exec -it $$node cqlsh -u cassandra -p cassandra -e "CREATE ROLE IF NOT EXISTS $(role) WITH PASSWORD = '$(password)' AND LOGIN = true;"; \
	done

.PHONY: clean
clean:
	rm -rf ./${DIRECTORY}/*