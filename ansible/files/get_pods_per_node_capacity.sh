#!/bin/bash

# requires: package bc (yum install -y bc)
# input:    optional: RESERVED_NODES (integer) Default: 2
# returns:  pod soft limit of cluster

# This variable defines how many nodes can disappear before we have a problem
RESERVED_NODES=2

# overwrite RESERVED_NODES with first parameter if provided and a number
if ! [ -z "$1" ]
  then
  # argument supplied
  re='^[0-9]+$'
  if ! [[ $1 =~ $re ]] ; then
     echo "error: Not a number" >&2; exit 1
  else
    RESERVED_NODES=$1
  fi
fi

# Counting variables
TOTAL_NODES=$(oc get node --no-headers --selector='purpose=workingnode' | wc -l)

TOTAL_POD_CAPACITY=0 # Holds the sum of "max-pods"
TOTAL_PODS=0 # Holds the total number of pods consuming resources

# Only include worker
for node in $(oc get node --no-headers --selector='purpose=workingnode' -o=custom-columns=NAME:.metadata.name)
do
        # Get "describe node" output
        DESCRIBE_NODE_OUTPUT=$(oc describe node ${node})

        # Get max-pods for node
        MAX_PODS=$(echo "$DESCRIBE_NODE_OUTPUT" | grep pods | awk '{ print $2 }' | head -n1)
        TOTAL_POD_CAPACITY=$(expr $TOTAL_POD_CAPACITY + $MAX_PODS)

        # tail is necessary because headers are printed, even though --no-headers is specified
        # Discard "Listing matched pods on node ..." with shell redirection
        # pods in state 'Error' and 'Completed' are not taken into account
        NUMBER_OF_PODS=$(oadm manage-node ${node} --list-pods --no-headers 2>/dev/null | tail -n+2 | awk '$3 != "Error" && $3 != "Completed"' | wc -l)
        # Resources
        CAPACITY_OUTPUT=$(echo "$DESCRIBE_NODE_OUTPUT" | grep "Capacity" -A 3)
        ALLOCATED_OUTPUT=$(echo "$DESCRIBE_NODE_OUTPUT" | grep "Allocated resources" -A 5 | grep "CPU Requests" -A 2 | grep -v "\-\-\-" | grep -v "CPU Requests")

        # Calculate summaries
        TOTAL_PODS=$(expr $TOTAL_PODS + $NUMBER_OF_PODS)
        NODE_USAGE=$(echo "$NUMBER_OF_PODS*100 / $MAX_PODS*100 / 100" | bc) # Multiply by 100 for floating point

        #printf "\n%-25s %16s %25s %35s" ${node} "$NUMBER_OF_PODS / $MAX_PODS ($NODE_USAGE%)"
done

# Calculate statistics
HARD_LIMIT=$(expr $TOTAL_POD_CAPACITY - $TOTAL_PODS)
SOFT_LIMIT=$(echo "$TOTAL_POD_CAPACITY - ( $RESERVED_NODES * ($TOTAL_POD_CAPACITY / $TOTAL_NODES) ) - $TOTAL_PODS" | bc)

#echo "TotalNodes=$TOTAL_NODES"
#echo "TotalPodCapacity=$TOTAL_POD_CAPACITY"
#echo "TotalPods=$TOTAL_PODS"
#echo "AvailablePodSoftLimit=$SOFT_LIMIT"
#echo "AvailablePodHardLimit=$HARD_LIMIT"

echo "$SOFT_LIMIT"
