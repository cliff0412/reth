#!/bin/bash
set -e

echo "Using L1_RPC_URL: $L1_RPC_URL"
echo "Using PRIVATE_KEY: $PRIVATE_KEY"

sleep 20

cd /app/optimism/packages/contracts-bedrock
[ -f /app/optimism_build/artifact.json ] && rm /app/optimism_build/artifact.json
[ -f /app/optimism_build/state_dump.json ] && rm /app/optimism_build/state_dump.json

# Function to deploy and check for completion with timeout
deploy_contracts() {
    local resume_flag=$1
    local cmd="DEPLOYMENT_OUTFILE=deployments/artifact.json DEPLOY_CONFIG_PATH=deploy-config/devnetL1.json forge script -vvv scripts/deploy/Deploy.s.sol:Deploy --rpc-url $L1_RPC_URL --private-key $PRIVATE_KEY --broadcast --non-interactive"
    
    if [ "$resume_flag" = "true" ]; then
        cmd="$cmd --resume"
    fi
    
    echo "Running: $cmd"
    
    # Run with timeout and capture output
    local output
    output=$(timeout 120 bash -c "$cmd" 2>&1)
    local exit_code=$?

    # echo "Output: $output"
    
    if [ $exit_code -eq 124 ]; then
        echo "Deployment timed out after 30 minutes"
        echo "$output"
        return 1
    elif echo "$output" | grep -q "set up op chain"; then
        echo "Deployment completed successfully - found 'set up op chain' message"
        return 0
    else
        echo "Deployment output:"
        echo "$output"
        echo "Deployment may not have completed - 'set up op chain' not found"
        return 1
    fi
}


# echo "Deploying L1 contracts..."
# #   --rpc-url http://host.docker.internal:8545 \
# cd /app/optimism/packages/contracts-bedrock
# DEPLOYMENT_OUTFILE=deployments/artifact.json \
# DEPLOY_CONFIG_PATH=deploy-config/devnetL1.json \
# forge script scripts/deploy/Deploy.s.sol:Deploy \
#   --rpc-url $L1_RPC_URL \
#   --private-key $PRIVATE_KEY \
#   --broadcast \
#   --non-interactive \
#   --slow \
#   -v

# Try initial deployment
if ! deploy_contracts false; then
    echo "Initial deployment failed or incomplete, checking for indexing error..."
    
    # Check if the error was due to transaction indexing
    if grep -q "transaction indexing is in progress" /app/optimism/packages/contracts-bedrock/broadcast/Deploy.s.sol/*/run-latest.json 2>/dev/null || \
       grep -q "transaction indexing is in progress" /app/optimism/packages/contracts-bedrock/cache/Deploy.s.sol/*/run-latest.json 2>/dev/null; then
        
        echo "Transaction indexing error detected. Waiting 30 seconds and retrying..."
        sleep 30
        
        # Check if we have a deployment file to resume from
        if [ -f "/app/optimism/packages/contracts-bedrock/broadcast/Deploy.s.sol/32382/run-latest.json" ]; then
            echo "Found deployment file, retrying with --resume..."
            deploy_contracts true
        else
            echo "No deployment file found, retrying without --resume..."
            deploy_contracts false
        fi
    else
        echo "Deployment failed for reasons other than indexing. Exiting."
        exit 1
    fi
else
    echo "Initial Deployment completed successfully"
fi

# Wait for nonce to be greater than 50
echo "Waiting for nonce to be greater than 59..."
while true; do
    nonce=$(cast nonce 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url=$L1_RPC_URL)
    echo "Current nonce: $nonce"
    if [ "$nonce" -gt 59 ]; then
        echo "Nonce is now greater than 50, proceeding with deployment..."
        break
    fi
    echo "Nonce is $nonce, waiting 10 seconds..."
    sleep 10
done

echo "Generating state dump..."
FORK=latest \
STATE_DUMP_PATH=deployments/state_dump.json \
DEPLOY_CONFIG_PATH=deploy-config/devnetL1.json \
CONTRACT_ADDRESSES_PATH=deployments/artifact.json \
forge script scripts/L2Genesis.s.sol:L2Genesis --sig 'runWithStateDump()'

echo "Copying artifact..."
cp deployments/artifact.json /app/optimism_build/artifact.json
cp deployments/state_dump.json /app/optimism_build/state_dump.json

echo "Generating genesis files..."
# cat deployments/artifact.json
[ -f /app/optimism_build/genesis.json ] && rm /app/optimism_build/genesis.json
[ -f /app/optimism_build/rollup.json ] && rm /app/optimism_build/rollup.json
go run ../../op-node/cmd/main.go genesis l2 \
  --deploy-config=deploy-config/devnetL1.json \
  --l1-deployments=deployments/artifact.json \
  --l2-allocs=deployments/state_dump.json \
  --outfile.l2=/app/optimism_build/genesis.json \
  --outfile.rollup=/app/optimism_build/rollup.json \
  --l1-rpc=$L1_RPC_URL

echo "Deployment complete! Files available in /app/optimism_build"