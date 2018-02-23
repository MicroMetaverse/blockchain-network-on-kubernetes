#!/bin/bash

if [ -d "${PWD}/configFiles" ]; then
    KUBECONFIG_FOLDER=${PWD}/configFiles
else
    echo "Configuration files are not found."
    exit
fi

# KUBECONFIG_FOLDER=${PWD}

echo -e "\nCreating volume"
if [ "$(kubectl get pvc | grep shared-pvc | awk '{print $2}')" != "Bound" ]; then
    echo "The Persistant Volume does not seem to exist or is not bound"
    echo "Creating Persistant Volume"
        
    echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/createVolume.yaml"
    kubectl create -f ${KUBECONFIG_FOLDER}/createVolume.yaml
    sleep 5
    if [ "kubectl get pvc | grep shared-pvc | awk '{print $3}'" != "shared-pv" ]; then
        echo "Success creating Persistant Volume"
    else
        echo "Failed to create Persistant Volume"
    fi
else
    echo "The Persistant Volume exists, not creating again"
fi

echo -e "\nCopying artifacts into persistant volume"
echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/copyArtifactsJob.yaml"
kubectl create -f ${KUBECONFIG_FOLDER}/copyArtifactsJob.yaml

sleep 5
pod=$(kubectl get pods  --show-all --selector=job-name=copyartifacts --output=jsonpath={.items..metadata.name})
kubectl cp ./artifacts $pod:/shared

echo "Waiting for 10 more seconds for copying artifacts to avoid any network delay"
sleep 10
JOBSTATUS=$(kubectl get jobs |grep "copyartifacts" |awk '{print $3}')
while [ "${JOBSTATUS}" != "1" ]; do
    echo "Waiting for copyartifacts job to complete"
    sleep 1;
    PODSTATUS=$(kubectl get pods --show-all| grep "copyartifacts" | awk '{print $3}')
        if [ "${PODSTATUS}" == "Error" ]; then
            echo "There is an error in copyartifacts job. Please check logs."
            exit 1
        fi
    JOBSTATUS=$(kubectl get jobs |grep "copyartifacts" |awk '{print $3}')
done
echo "Copy artifacts job completed"


echo -e "\nGenerating the required artifacts for Blockchain network"
echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/generateArtifactsJob.yaml"
kubectl create -f ${KUBECONFIG_FOLDER}/generateArtifactsJob.yaml

JOBSTATUS=$(kubectl get jobs |grep utils|awk '{print $3}')
while [ "${JOBSTATUS}" != "1" ]; do
    echo "Waiting for generateArtifacts job to complete"
    sleep 1;
    # UTILSLEFT=$(kubectl get pods --show-all | grep utils | awk '{print $2}')
    UTILSSTATUS=$(kubectl get pods --show-all | grep "utils" | awk '{print $3}')
    if [ "${UTILSSTATUS}" == "Error" ]; then
            echo "There is an error in utils job. Please check logs."
            exit 1
    fi
    # UTILSLEFT=$(kubectl get pods --show-all | grep utils | awk '{print $2}')
    JOBSTATUS=$(kubectl get jobs |grep utils|awk '{print $3}')
done


echo -e "\nCreating Services for blockchain network"
echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/blockchain-services.yaml"
kubectl create -f ${KUBECONFIG_FOLDER}/blockchain-services.yaml


echo -e "\nCreating new Deployment to create four peers in network"
echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/peersDeployment.yaml"
kubectl create -f ${KUBECONFIG_FOLDER}/peersDeployment.yaml

echo "Checking if all deployments are ready"

NUMPENDING=$(kubectl get deployments | grep blockchain | awk '{print $5}' | grep 0 | wc -l | awk '{print $1}')
while [ "${NUMPENDING}" != "0" ]; do
    echo "Waiting on pending deployments. Deployments pending = ${NUMPENDING}"
    NUMPENDING=$(kubectl get deployments | grep blockchain | awk '{print $5}' | grep 0 | wc -l | awk '{print $1}')
    sleep 1
done

echo "Waiting for 15 seconds for peers and orderer to settle"
sleep 15

echo -e "\nCreating channel transaction artifact and a channel"
echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/create_channel.yaml"
kubectl create -f ${KUBECONFIG_FOLDER}/create_channel.yaml

JOBSTATUS=$(kubectl get jobs |grep createchannel |awk '{print $3}')
while [ "${JOBSTATUS}" != "1" ]; do
    echo "Waiting for createchannel job to be completed"
    sleep 1;
    if [ "$(kubectl get pods --show-all| grep createchannel | awk '{print $3}')" == "Error" ]; then
        echo "Create Channel Failed"
        exit 1
    fi
    JOBSTATUS=$(kubectl get jobs |grep createchannel |awk '{print $3}')
done
echo "Create Channel Completed Successfully"


echo -e "\nCreating joinchannel job"
echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/join_channel.yaml"
kubectl create -f ${KUBECONFIG_FOLDER}/join_channel.yaml

JOBSTATUS=$(kubectl get jobs |grep joinchannel |awk '{print $3}')
while [ "${JOBSTATUS}" != "1" ]; do
    echo "Waiting for joinchannel job to be completed"
    sleep 1;
    if [ "$(kubectl get pods --show-all| grep joinchannel | awk '{print $3}')" == "Error" ]; then
        echo "Join Channel Failed"
        exit 1
    fi
    JOBSTATUS=$(kubectl get jobs |grep joinchannel |awk '{print $3}')
done
echo "Join Channel Completed Successfully"


echo -e "\nCreating installchaincode job"
echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/chaincode_install.yaml"
kubectl create -f ${KUBECONFIG_FOLDER}/chaincode_install.yaml

JOBSTATUS=$(kubectl get jobs |grep chaincodeinstall |awk '{print $3}')
while [ "${JOBSTATUS}" != "1" ]; do
    echo "Waiting for chaincodeinstall job to be completed"
    sleep 1;
    if [ "$(kubectl get pods --show-all| grep chaincodeinstall | awk '{print $3}')" == "Error" ]; then
        echo "Chaincode Install Failed"
        exit 1
    fi
    JOBSTATUS=$(kubectl get jobs |grep chaincodeinstall |awk '{print $3}')
done
echo "Chaincode Install Completed Successfully"


echo -e "\nCreating chaincodeinstantiate job"
echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/chaincode_instantiate.yaml"
kubectl create -f ${KUBECONFIG_FOLDER}/chaincode_instantiate.yaml

JOBSTATUS=$(kubectl get jobs |grep chaincodeinstantiate |awk '{print $3}')
while [ "${JOBSTATUS}" != "1" ]; do
    echo "Waiting for chaincodeinstantiate job to be completed"
    sleep 1;
    if [ "$(kubectl get pods --show-all| grep chaincodeinstantiate | awk '{print $3}')" == "Error" ]; then
        echo "Chaincode Instantiation Failed"
        exit 1
    fi
    JOBSTATUS=$(kubectl get jobs |grep chaincodeinstantiate |awk '{print $3}')
done
echo "Chaincode Instantiation Completed Successfully"
sleep 15
echo -e "\nNetwork Setup Completed !!"