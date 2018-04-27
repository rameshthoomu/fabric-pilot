#!/bin/bash

parseCreds() {
    if [ -z ${CREDS_FILE} ]; then
        echo "Creds file not passed."
        exit 1
    else
        export CORE_PEER_NETWORKID=$(cat ${CREDS_FILE} | jq '."x-networkId"' | tr -d "\"")
        ORGID=$(cat ${CREDS_FILE} | jq '."organizations" | keys | .[0]')
        export CORE_PEER_LOCALMSPID=$(cat ${CREDS_FILE} | jq ".[\"organizations\"][$ORGID][\"mspid\"]" | tr -d "\"")
        CA_KEY=$(cat ${CREDS_FILE} | jq ".[\"organizations\"][$ORGID][\"certificateAuthorities\"][0]")
        export CA_NAME=$(cat ${CREDS_FILE} | jq ".[\"certificateAuthorities\"][$CA_KEY][\"caName\"]" | tr -d "\"")
        export CA_ENROLL_ID=$(cat ${CREDS_FILE} | jq ".[\"certificateAuthorities\"][$CA_KEY][\"registrar\"][0][\"enrollId\"]")
        export CA_ENROLLSECRET=$(cat ${CREDS_FILE} | jq ".[\"certificateAuthorities\"][$CA_KEY][\"registrar\"][0][\"enrollSecret\"]")
        export CA_PROTOCOL=$(cat ${CREDS_FILE} | jq ".[\"certificateAuthorities\"][$CA_KEY][\"url\"]" | tr -d "\"" | tr -d "/" | cut -d: -f1)
        export CA_HOST=$(cat ${CREDS_FILE} | jq ".[\"certificateAuthorities\"][$CA_KEY][\"url\"]" | tr -d "\"" | tr -d "/" | cut -d: -f2)
        export CA_PORT=$(cat ${CREDS_FILE} | jq ".[\"certificateAuthorities\"][$CA_KEY][\"url\"]" | tr -d "\"" | tr -d "/" | cut -d: -f3)
        export CA_URL="${CA_HOST}:${CA_PORT}"
        export CA_TLS_CACERT=$(cat ${CREDS_FILE} | jq ".[\"certificateAuthorities\"][$CA_KEY][\"tlsCACerts\"][\"pem\"]" | tr -d "\"")
	export ORDERERS_ALL=$(cat ${CREDS_FILE} | jq '.["orderers"][]["url"]' | tr -d "\"")
	export ORDERERS_ALL=${ORDERERS_ALL//grpcs:\/\//}
	export ORDERERS_ALL=${ORDERERS_ALL//grpc:\/\//}
	export ORDERERS_ENV=""
	local i=1
	for orderer in ${ORDERERS_ALL[*]}; do
		export ORDERER_ENV+="      - ORDERER_${i}=${orderer}
"
		i=$((i+1))
	done
    fi

	if [ -z "${ADMIN_CERT}" ]; then
        export ADMINENROLLMENT="&& fabric-ca-client enroll -u ${CA_PROTOCOL}://${CA_ENROLL_ID}:${CA_ENROLLSECRET}@${CA_URL} --tls.certfiles /mnt/certs/catlscacert/catlscacert.pem --caname ${CA_NAME} --mspdir /mnt/crypto/adminenrollment && cp /mnt/crypto/adminenrollment/signcerts/*.pem /mnt/crypto/peer/peer/msp/admincerts && mkdir -p /mnt/crypto/adminenrollment/admincerts/ && cp /mnt/crypto/adminenrollment/signcerts/*.pem /mnt/crypto/adminenrollment/admincerts/ && echo \"ADMIN PRIVATE KEY:\" && cat /mnt/crypto/adminenrollment/keystore/*"
    fi
}

setPeerLoglevel() {
    export CORE_LOGGING_LEVEL=${CORE_LOGGING_LEVEL:-debug}
}

setPeerGossip() {
    BOOTSTRAP_ADDRESS=${1}
    export CORE_PEER_GOSSIP_BOOTSTRAP=${BOOTSTRAP_ADDRESS}
    export CORE_PEER_GOSSIP_ORGLEADER=true
}

generateTLSCerts() {

	TLS_SUBJECT=${TLS_SUBJECT:-"/C=US/ST=North Carolina/L=Raleigh/O=IBM/OU=ROOT CA/CN=blockchain.com"}

	TLS_FOLDER=${PWD}/mnt/certs/tls/

	# cleanup old stuff
	# this includes deleting all the old certs and csrs
	rm -rf ${TLS_FOLDER}/*

	mkdir -p ${TLS_FOLDER}

	# make text files for ca to track issued certs
	touch index.txt
	echo '01' > serial.txt

	# generate ca key and cert
	#echo "openssl req -x509 -config openssl-ca.cnf -newkey rsa:4096 -sha256 -nodes -out ${TLS_FOLDER}/cacert.pem -outform PEM -subj ${TLS_SUBJECT}"
	openssl req -x509 -config openssl-ca.cnf -newkey rsa:4096 -sha256 -nodes -out ${TLS_FOLDER}/cacert.pem -keyout ${TLS_FOLDER}/cakey.pem -outform PEM -subj "${TLS_SUBJECT}"

	#peerlocal
	#echo "openssl req -config openssl-server.cnf -newkey rsa:2048 -sha256 -nodes -out ${TLS_FOLDER}/servercert.csr -outform PEM -keyout ${TLS_FOLDER}/peer-key.pem -subj \"${TLS_SUBJECT}\""
	openssl req -config openssl-server.cnf -newkey rsa:2048 -sha256 -nodes -out ${TLS_FOLDER}/servercert.csr -outform PEM -keyout ${TLS_FOLDER}/peer-key.pem -subj "${TLS_SUBJECT}"
	#echo "openssl ca -batch -config openssl-ca.cnf -policy signing_policy -extensions signing_req -keyfile ${TLS_FOLDER}/cakey.pem -cert ${TLS_FOLDER}/cacert.pem -out ${TLS_FOLDER}/peer-cert.pem -infiles ${TLS_FOLDER}/servercert.csr"
	openssl ca -batch -config openssl-ca.cnf -policy signing_policy -extensions signing_req -keyfile ${TLS_FOLDER}/cakey.pem -cert ${TLS_FOLDER}/cacert.pem -out ${TLS_FOLDER}/peer-cert.pem -infiles ${TLS_FOLDER}/servercert.csr

	echo -e "${CA_TLS_CACERT}" >> ${TLS_FOLDER}/cacert_new.pem
	cat ${TLS_FOLDER}/cacert.pem >> ${TLS_FOLDER}/cacert_new.pem
	mv ${TLS_FOLDER}/cacert_new.pem ${TLS_FOLDER}/cacert.pem

	rm index.txt*
	rm serial.txt*
	rm *.pem
}

setPeerTLS() {
    if [ "${GENERATE_TLS_CERTS}" != "true" ]; then
        echo "I will not generate TLS Certificates"
    else
	generateTLSCerts
    fi

    export CORE_PEER_TLS_ENABLED=true
    export CORE_PEER_TLS_CERT_FILE=/mnt/certs/tls/peer-cert.pem
    export CORE_PEER_TLS_KEY_FILE=/mnt/certs/tls/peer-key.pem
    export CORE_PEER_TLS_ROOTCERT_FILE=/mnt/certs/tls/cacert.pem
}

setPeerCouchDB() {
    # COUCHDB_ADDRESS=${1}
    # COUCHDB_USERNAME=${2}
    # COUCHDB_PASSWORD=${3}
    if [ -z "${COUCHDB_ADDRESS}" ] || [ -z "${COUCHDB_USERNAME}" ] || [ -z "${COUCHDB_PASSWORD}" ]; then
        echo "CouchDB is not used"
    else
        export CORE_LEDGER_STATE_STATEDATABASE=CouchDB
        export CORE_LEDGER_STATE_COUCHDBCONFIG_COUCHDBADDRESS=${COUCHDB_ADDRESS}
        export CORE_LEDGER_STATE_COUCHDBCONFIG_USERNAME=${COUCHDB_USERNAME}
        export CORE_LEDGER_STATE_COUCHDBCONFIG_PASSWORD=${COUCHDB_PASSWORD}
        export CORE_LEDGER_STATE_COUCHDBCONFIG_MAXRETRIESONSTARTUP=20
    fi
}

setPeerDefaults() {
    export CORE_PEER_ADDRESSAUTODETECT=false
    export CORE_PEER_FILESYSTEMPATH=/mnt/data/peer/
    export CORE_PEER_ID=fabric-peer
    export FABRIC_CFG_PATH=/etc/hyperledger/fabric/
    export CORE_PEER_ADDRESS=fabric-peer.blockchain.com:7051
    export CORE_PEER_LISTENADDRESS=0.0.0.0:7051
    export CORE_PEER_EVENTS_ADDRESS=0.0.0.0:7052
    export CORE_PEER_CHAINCODELISTENADDRESS=fabric-peer.blockchain.com:7053
    export CORE_PEER_PROFILE_ENABLED=true
    export CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
    export CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE=blockchain.com
    export CORE_PEER_MSPCONFIGPATH=/mnt/crypto/peer/peer/msp
    export CORE_PEER_FILESYSTEMPATH=/mnt/data/peer/
    export USER_ID=$(id -u ${USER})
    export GROUP_ID=$(id -g ${USER})
}

PrintHelp() {
    echo "The arguments are not correct."
    exit 1
}

# Parse the input arguments
Parse_Arguments() {
    export GENERATE_TLS_CERTS=true
    while [ $# -gt 0 ]; do
        case $1 in
            --gossip-bootstrap | -gb)
                shift
                export CORE_PEER_GOSSIP_BOOTSTRAP=${1}
                ;;
            --gossip-orgleader | -gl)
                export CORE_PEER_GOSSIP_ORGLEADER=true
                ;;
            --user-tls-certs | -t)
                export GENERATE_TLS_CERTS=false
                ;;
            --user-tls-subject | -ts)
                shift
                export TLS_SUBJECT="$1"
                ;;
            --couchdb-address | -cdba)
                shift
                export COUCHDB_ADDRESS=${1}
                ;;
            --couchdb-user | -cdbu)
                shift
                export COUCHDB_USERNAME=${1}
                ;;
            --couchdb-password | -cdbb)
                shift
                export COUCHDB_PASSWORD=${1}
                ;;
            --loglevel | -l)
                shift
                export CORE_LOGGING_LEVEL=${1}
                ;;
            --creds-file | -c)
                shift
                export CREDS_FILE=${1}
                ;;
            --admin-cert | -a)
                shift
                if [ -f ${1} ]; then
                    echo "Admin cert is a file"
                    export ADMIN_CERT=$(cat ${1})
                    export ADMIN_CERT=$(echo "${ADMIN_CERT//$'\n'/\r\n}\r\n")
                else
                    echo "Admin cert is passed as-is"
                    export ADMIN_CERT=${1}
                fi
                ;;
            --help | -h)
                PrintHelp
                ;;
        esac
        shift
    done

}

generateDockerCompose() {
    cat <<EOB
version: "2"

networks:
  blockchain.com:
    external:
      name: blockchain.com

services:
  enrollment:
    image: ibmblockchain/fabric-peer-x86_64:1.1.0
    command: bash -c 'mkdir -p /mnt/certs/catlscacert && mkdir -p /mnt/crypto/peer/peer/msp && echo -e \$\${CA_TLS_CACERT} > /mnt/certs/catlscacert/catlscacert.pem && cat /mnt/certs/catlscacert/catlscacert.pem && fabric-ca-client enroll -u ${CA_PROTOCOL}://${CA_ENROLL_ID}:${CA_ENROLLSECRET}@${CA_URL} --tls.certfiles /mnt/certs/catlscacert/catlscacert.pem --caname ${CA_NAME} --mspdir /mnt/crypto/peer/peer/msp && mkdir -p /mnt/crypto/peer/peer/msp/admincerts/ && echo -e \$\${ADMIN_CERT} > /mnt/crypto/peer/peer/msp/admincerts/cert.pem ${ADMINENROLLMENT}'
#    command: bash -c 'sleep 1 && mkdir -p /mnt/certs/catlscacert && mkdir -p /mnt/crypto/peer/peer/msp && echo -e $${CA_TLS_CACERT} > /mnt/certs/catlscacert/catlscacert.pem && while true; do sleep 100; done;'
    environment:
      - CA_TLS_CACERT=${CA_TLS_CACERT}
      - ADMIN_CERT=${ADMIN_CERT}
      - GROUP_ID=${GROUP_ID}
      - USER_ID=${USER_ID}
      - USERNAME=peer
      #- FABRIC_CA_CLIENT_HOME=
    networks:
      - blockchain.com
    volumes:
      - ${PWD}/mnt:/mnt

  fabric-peer:
    hostname: fabric-peer
    image: ibmblockchain/fabric-peer-x86_64:1.1.0
    command: sh -c 'sleep 10 && peer node start'
    ports:
      # GRPC port
      - 7051:7051
      # Events port
      - 7052:7052
      # Couchdb port
      - 5984:5984
      # Chaincode listen port
      - 7053:7053
    environment:
      - CORE_PEER_ADDRESSAUTODETECT=${CORE_PEER_ADDRESSAUTODETECT}
      - CORE_PEER_NETWORKID=${CORE_PEER_NETWORKID}
      - CORE_PEER_ADDRESS=${CORE_PEER_ADDRESS}
      - CORE_PEER_LISTENADDRESS=${CORE_PEER_LISTENADDRESS}
      - CORE_PEER_EVENTS_ADDRESS=${CORE_PEER_EVENTS_ADDRESS}
      - CORE_PEER_CHAINCODELISTENADDRESS=${CORE_PEER_CHAINCODELISTENADDRESS}
      - CORE_PEER_GOSSIP_BOOTSTRAP=${CORE_PEER_GOSSIP_BOOTSTRAP}
      - CORE_PEER_GOSSIP_ORGLEADER=${CORE_PEER_GOSSIP_ORGLEADER}
      - CORE_PEER_PROFILE_ENABLED=true
      - CORE_VM_ENDPOINT=${CORE_VM_ENDPOINT}
      - CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE=${CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE}
      - CORE_PEER_LOCALMSPID=${CORE_PEER_LOCALMSPID}
      - CORE_PEER_MSPCONFIGPATH=${CORE_PEER_MSPCONFIGPATH}
      - CORE_LOGGING_LEVEL=${CORE_LOGGING_LEVEL}
      - CORE_PEER_FILESYSTEMPATH=${CORE_PEER_FILESYSTEMPATH}
      - CORE_PEER_ID=${CORE_PEER_ID}
      - CORE_PEER_TLS_ENABLED=${CORE_PEER_TLS_ENABLED}
      - CORE_PEER_TLS_CERT_FILE=${CORE_PEER_TLS_CERT_FILE}
      - CORE_PEER_TLS_KEY_FILE=${CORE_PEER_TLS_KEY_FILE}
      - CORE_PEER_TLS_ROOTCERT_FILE=${CORE_PEER_TLS_ROOTCERT_FILE}
      - CORE_LEDGER_STATE_STATEDATABASE=${CORE_LEDGER_STATE_STATEDATABASE}
      - CORE_LEDGER_STATE_COUCHDBCONFIG_COUCHDBADDRESS=${CORE_LEDGER_STATE_COUCHDBCONFIG_COUCHDBADDRESS}
      - CORE_LEDGER_STATE_COUCHDBCONFIG_USERNAME=${CORE_LEDGER_STATE_COUCHDBCONFIG_USERNAME}
      - CORE_LEDGER_STATE_COUCHDBCONFIG_PASSWORD=${CORE_LEDGER_STATE_COUCHDBCONFIG_PASSWORD}
      - CORE_LEDGER_STATE_COUCHDBCONFIG_MAXRETRIESONSTARTUP=${CORE_LEDGER_STATE_COUCHDBCONFIG_MAXRETRIESONSTARTUP}
      - FABRIC_CFG_PATH=${FABRIC_CFG_PATH}
      - GROUP_ID=${GROUP_ID}
      - USER_ID=${USER_ID}
      - USERNAME=peer
${ORDERER_ENV}
    volumes:
      - ${PWD}/mnt/:/mnt
      - /var/run:/host/var/run/
    networks:
      - blockchain.com
    labels:
      - container_name=fabric-peer
EOB

}

if [ -d "${PWD}/mnt" ]; then
	echo "Deleting and recreating ${PWD}/mnt"
	sudo rm -rf ${PWD}/mnt
	mkdir ${PWD}/mnt
fi

Parse_Arguments $@
parseCreds
setPeerLoglevel
setPeerGossip
setPeerTLS
setPeerCouchDB
setPeerDefaults
generateDockerCompose > docker-compose.yml

echo ""
echo "Successfully created docker-compose.yml"
echo ""
echo "Please create docker-network using:"
echo "docker network create blockchain.com"
echo ""
echo "You can list docker networks by running 'docker network ls'"
echo ""
echo "Start the peer: docker-compose up -d"
