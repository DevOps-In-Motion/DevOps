#!/bin/bash

# init variable
COST=75
ARRAY_EXAMPLE=("ITEM1" "ITEM2")

### ---- Conditionals ---- ###

if [] && [] || [] ; then

# -gt -lt -ge -le 
elif []; then

# 
else
  exit 1 # exit program
fi



### ---- Loops ---- ###

echo "Looping through an array:"
NAMES=("Alice" "Bob" "Charlie" "David")

for name in "${NAMES[@]}"; do
    echo "Hello, $name!"
done

echo 

echo "Looping through a range of numbers:"
for i in {1..5}; do
    echo "Number: $i"
done

#!/bin/bash

# Simple countdown using a while loop
count=5
echo "Countdown:"
while [ $count -gt 0 ]; do
  echo $count
  count=$((count - 1))
  sleep 1 # Wait for 1 second
done
echo "Blast off!"


# Count up to 5 using an until loop
count=1
echo "Counting up to 5:"
until [ $count -gt 5 ]; do
  echo $count
  count=$((count + 1))
  sleep 1 # Wait for 1 second
done

# break and continue example
#!/bin/bash

echo "Demonstration of break:"
for i in {1..10}; do
    if [ $i -eq 6 ]; then
        echo "Breaking the loop at $i"
        break
    fi
    echo $i
done

echo 

echo "Demonstration of continue (printing odd numbers):"
for i in {1..10}; do
    if [ $((i % 2 )) -eq 0 ]; then
        continue
    fi
    echo $i

done


### ---- functions ---- ###

#!/bin/bash

# this is a simple function 
greet() {
    echo "Hello, World!"
}

# Function that echoes a result
get_square() {
  echo $(($1 * $1))
}

# Function that modifies a global variable
RESULT=0
set_global_result() {
  RESULT=$(($1 * $1))
}

# Capture the echoed result
square_of_5=$(get_square 5)
echo "The square of 5 is $square_of_5"

# Use the function to modify the global variable
set_global_result 6
echo "The square of 6 is $RESULT"

### function var scope

# Global variable
GLOBAL_VAR="I'm global"

# Function with a local variable
demonstrate_scope() {
  local LOCAL_VAR="I'm local"
  echo "Inside function: GLOBAL_VAR = $GLOBAL_VAR"
  echo "Inside function: LOCAL_VAR = $LOCAL_VAR"
}

# Call the function
demonstrate_scope

echo "Outside function: GLOBAL_VAR = $GLOBAL_VAR"
echo "Outside function: LOCAL_VAR = $LOCAL_VAR"


### Advance functions

#!/bin/bash

ENGLISH_CALC() {
  local num1=$1
  local operation=$2
  local num2=$3
  local result

  case $operation in
    plus)
      result=$((num1 + num2))
      echo "$num1 + $num2 = $result"
      ;;
    minus)
      result=$((num1 - num2))
      echo "$num1 - $num2 = $result"
      ;;
    times)
      result=$((num1 * num2))
      echo "$num1 * $num2 = $result"
      ;;
    *)
      echo "Invalid operation. Please use 'plus', 'minus', or 'times'."
      return 1
      ;;
  esac
}

# Test the function
ENGLISH_CALC 3 plus 5
ENGLISH_CALC 5 minus 1
ENGLISH_CALC 4 times 6
ENGLISH_CALC 2 divide 2 # This should show an error message


### ---- Special Variables ---- ###
echo "Script Name: $0"
echo "First Argument: $1"
echo "Second Argument: $2"
echo "All Arguments: $@"
echo "Number of Arguments: $#"
echo "Process ID: $$"

echo "Running a successful command:"
ls /home
echo "Exit status: $?"

echo "Running a command that will fail:"
ls /nonexistent_directory
echo "Exit status: $?"

echo "Running a background process:"
sleep 2 &
echo "Process ID of last background command: $!"



# With "$@", each argument is treated as a separate entity. Arguments with spaces are preserved as single units.
# With "$*", all arguments are combined into a single string, separated by the first character of the IFS (Internal Field Separator) variable, which is usually a space.


# Trap example

#!/bin/bash

#!/bin/bash

cleanup_and_exit() {
  echo -e "\nSignal received! Cleaning up..."
  echo "Performing cleanup tasks..."
  # Add any necessary cleanup code here
  echo "Cleanup completed."
  echo "Exiting script gracefully."
  exit 0
}

trap cleanup_and_exit SIGINT SIGTERM

echo "This script will run until you press Ctrl+C."
echo "Press Ctrl+C to see the trap function in action and exit gracefully."

count=1
while true; do
  echo "Script is running... (iteration $count)"
  sleep 1
  ((count++))
done


filename="test_file.txt"
if [ -e "$filename" ]; then
  echo "$filename exists"
else
  echo "$filename does not exist"
fi


dirname="test_directory"
if [ -d "$dirname" ]; then
  echo "$dirname exists"
else
  echo "$dirname does not exist"
fi



# -r checks if the current user has a readable file.
filename="test_file.txt"
if [ -r "$filename" ]; then
  echo "You have read permission for $filename"
else
  echo "You do not have read permission for $filename"
fi