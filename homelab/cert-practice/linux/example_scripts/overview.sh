#!/bin/bash

# Globals
NAMES=("Alice" "Bob" "Charlie" "David")


# Function with a local variable
demonstrate_scope() {
  local LOCAL_VAR="I'm local"
  echo "Inside function: GLOBAL_VAR = $GLOBAL_VAR"
  echo "Inside function: LOCAL_VAR = $LOCAL_VAR"
}

# Call the function
demonstrate_scope

