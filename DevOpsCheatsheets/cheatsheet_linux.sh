# 
whoami

# display sys information
uname -a



# retreive the user and group 
id

# top command for monitoring
top

# create empty file
touch <filename>

# append file using commands
<command> >> <filename>

# list files with long information and owner:group permissions
ls -ld

# create an archieve of files and compress them
ls ./ | grep 2023 | tar -czf old_logs.tar.gz -T -

tar -czf old_logs.tar.gz -T *_2023-*.log

# show the difference in two files: 
## where it shows what changes need to be made to file1 to make it identical to file2.
diff <file1> <file2> 



### ----- Accounts and Permissions ----- ###

# read all the users
cat /etc/group

sudo useradd <username> -m # -m creates home
sudo userdel
sudo passwd <username>
sudo usermod -aG <username> <group-to-be-added>

# change to rw for owner and none for group or user? 
chmod 600
# change the owner to the group
sudo chown :5003 /path/to/directory
sudo chmod g+s 
# change the owner of the file to a group
sudo chmod 2770 /dir



### ----- Monitoring ----- ###
# processes for all users
ps aux

# "Task Manager"
top

# display uptime
uptime

# show kernal msgs
sudo dmesg

# check the process id of a named process
pgrep

# information
ps -p <id> -o pid,ppid,cmd

# kill a process by id
pkill <name>
kill -9 <PID>

### --- Processes --- ###
# The nohup command stands for "no hang up."
nohpup [COMMAND] -options
# You can redirect standard output with > and standard error with 2>&1.
# everything from stderr and stdout will go to name.log
nohup ./script > name.log 2>&1 & 


### ----- Networking ----- ###
# network configuration
ip addr
# 
ifconfig
# ping with count 
ping 8.8.8.8 -c 3
# socket statistics
ss
ss -tlnp | grep 8000
ss --tcp

# firewalls
sudo ufw enable 
sudo ufw deny [PORT]
sudo ufw allow [PORT]
# firewall status
sudo ufw status 



### ----- System repos ----- ###

sudo apt update
sudo apt install 
apt show [PACKAGE]
sudo apt remove [PACKAGE]
# deletes orphan packages
sudo apt autoremove


### ----- Backups ----- ###
tar -czvf ~/project/backups/system-backup.tar.gz -T backup-list.txt
# list all files verbosely
tar -tvf file.tar.gz > backup-contents.txt
# unpack only one file from a tar.gz
tar -f archive.tar.gz -x /path/to/file/in/archive

# -- automated backups -- #
# [minute] [hour] [day_of_month] [month] [day_of_week] [command]
# opens the crontab file 
crontab -e 


read -p "Enter your age: " age



### ----- Security Enhanced Linux ----- ###
# To view available booleans and their current states, use: 
sudo semanage boolean -l
# modify value 
sudo semanage boolean --modify --on boolean_name
# For example, to enable the boolean that allows HTTPD to access home directories:
sudo semanage boolean --modify --on httpd_enable_homedirs
# display the current boolean values for all SELinux policy booleans on the system
getsebool -a


### ----- Scripting ----- ###


### ----- File Testing ----- ###





#!/bin/bash

# System Information Script
# Comprehensive commands for gathering system details

echo "=== SYSTEM INFORMATION ==="
echo

# Operating System Information
echo "--- OS Information ---"
uname -a                    # All system information
uname -s                    # Kernel name
uname -r                    # Kernel release
uname -m                    # Machine hardware
cat /etc/os-release         # Distribution info (Linux)
hostnamectl                 # System hostname and OS info
echo

# CPU Information
echo "--- CPU Information ---"
lscpu                       # CPU architecture info
cat /proc/cpuinfo           # Detailed CPU info
nproc                       # Number of processing units
grep "model name" /proc/cpuinfo | head -1
echo

# Memory Information
echo "--- Memory Information ---"
free -h                     # Human-readable memory usage
cat /proc/meminfo           # Detailed memory info
vmstat                      # Virtual memory statistics
echo

# Disk Information
echo "--- Disk Information ---"
df -h                       # Disk space usage (human-readable)
df -i                       # Inode usage
lsblk                       # List block devices
fdisk -l                    # Partition information (requires root)
du -sh /*                   # Directory sizes
echo

# Network Information
echo "--- Network Information ---"
ip addr show                # IP addresses (modern)
ifconfig                    # Network interfaces (legacy)
ip route show               # Routing table
hostname -I                 # All IP addresses
netstat -tuln               # Active connections
ss -tuln                    # Socket statistics (modern alternative)
echo

# Process Information
echo "--- Process Information ---"
ps aux                      # All running processes
top -bn1 | head -20         # Process snapshot
pgrep -l bash               # Find processes by name
pidof systemd               # Get PID of process
echo

# System Load and Uptime
echo "--- System Load ---"
uptime                      # System uptime and load
cat /proc/loadavg           # Load average
w                           # Who is logged in and system load
echo

# Hardware Information
echo "--- Hardware Information ---"
lshw -short                 # Hardware summary (requires root)
lspci                       # PCI devices
lsusb                       # USB devices
dmidecode -t system         # DMI/SMBIOS info (requires root)
echo

# Storage I/O
echo "--- Disk I/O Statistics ---"
iostat                      # CPU and I/O statistics
iotop -bn1                  # I/O usage by process (requires root)
echo

# User Information
echo "--- User Information ---"
whoami                      # Current user
id                          # User ID and groups
who                         # Logged in users
last                        # Last logged in users
cat /etc/passwd             # All users
echo

# System Services
echo "--- System Services ---"
systemctl list-units --type=service --state=running  # Running services
service --status-all        # All services status (legacy)
echo

# Environment Variables
echo "--- Environment Variables ---"
env                         # All environment variables
printenv                    # Print environment
echo $PATH                  # Path variable
echo

# Date and Time
echo "--- Date/Time Information ---"
date                        # Current date and time
timedatectl                 # Time and date settings
echo

# Kernel Modules
echo "--- Loaded Kernel Modules ---"
lsmod                       # List loaded modules
modinfo <module_name>       # Module information
echo

# File System Information
echo "--- File System ---"
mount | column -t           # Mounted file systems
cat /proc/mounts            # Currently mounted file systems
findmnt                     # List all mount points
echo

# System Logs (last few entries)
echo "--- Recent System Logs ---"
journalctl -n 20            # Last 20 journal entries
dmesg | tail -20            # Last 20 kernel messages
echo

# Battery Information (for laptops)
echo "--- Battery Status ---"
upower -i /org/freedesktop/UPower/devices/battery_BAT0 2>/dev/null
acpi -b 2>/dev/null         # Battery info
echo

# Temperature Sensors
echo "--- Temperature ---"
sensors 2>/dev/null         # Hardware sensors (requires lm-sensors)
cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null
echo

echo "=== END OF REPORT ==="



#!/bin/bash

# Comprehensive Guide to Linux "d" Commands
# Common commands starting with 'd'

echo "=== DISK & FILESYSTEM COMMANDS ==="
echo

# df - Disk Filesystem usage
echo "--- df (disk free) ---"
echo "Shows disk space usage of file systems"
df -h                       # Human-readable format
df -i                       # Show inode information
df -T                       # Show filesystem type
df -h /home                 # Specific directory
echo

# du - Disk Usage
echo "--- du (disk usage) ---"
echo "Estimates file/directory space usage"
du -sh /var/log             # Summary, human-readable
du -h --max-depth=1 /home   # One level deep
du -ah /tmp                 # All files with sizes
du -c *.log                 # Total with grand total
echo

# dd - Data Definition/Convert and copy
echo "--- dd (data duplicator) ---"
echo "Low-level copying and conversion"
echo "Examples (DO NOT RUN without understanding):"
echo "  dd if=/dev/sda of=/dev/sdb bs=4M    # Clone disk"
echo "  dd if=/dev/zero of=testfile bs=1M count=100  # Create 100MB file"
echo "  dd if=/dev/urandom of=random.dat bs=1M count=10  # Random data"
echo "  dd if=input.iso of=/dev/sdb bs=4M status=progress  # Burn ISO"
echo

echo "=== SYSTEM & KERNEL COMMANDS ==="
echo

# dmesg - Display message (kernel ring buffer)
echo "--- dmesg (display message) ---"
echo "Shows kernel messages"
dmesg | tail -20            # Last 20 messages
dmesg -T                    # Human-readable timestamps
dmesg -l err,warn           # Only errors and warnings
dmesg -w                    # Follow mode (like tail -f)
echo

# dmidecode - DMI table decoder
echo "--- dmidecode (DMI decode) ---"
echo "Display hardware information from BIOS"
echo "Requires root access:"
echo "  sudo dmidecode -t system     # System information"
echo "  sudo dmidecode -t bios       # BIOS information"
echo "  sudo dmidecode -t processor  # CPU information"
echo "  sudo dmidecode -t memory     # RAM information"
echo

# dstat - System statistics
echo "--- dstat (versatile statistics tool) ---"
echo "Shows system resource statistics"
echo "Example: dstat -cdngy          # CPU, disk, net, page, system stats"
echo

echo "=== DIRECTORY & FILE COMMANDS ==="
echo

# dirname - Directory name
echo "--- dirname (directory name) ---"
echo "Strips last component from path"
dirname /usr/local/bin/script.sh    # Returns: /usr/local/bin
echo

# date - Display/set date and time
echo "--- date ---"
date                        # Current date and time
date +%Y-%m-%d              # Format: 2025-10-10
date +%s                    # Unix timestamp
date -d "2 days ago"        # Relative dates
date -d @1609459200         # Convert timestamp
echo

# diff - Difference between files
echo "--- diff ---"
echo "Compare files line by line"
echo "  diff file1.txt file2.txt     # Show differences"
echo "  diff -u file1.txt file2.txt  # Unified format"
echo "  diff -r dir1/ dir2/          # Recursive directory compare"
echo

# dir - List directory contents
echo "--- dir ---"
echo "List directory (alternative to ls)"
dir                         # Basic listing
dir -l                      # Long format
echo

echo "=== PROCESS & DEBUGGING COMMANDS ==="
echo

# dpkg - Debian Package manager
echo "--- dpkg (Debian package) ---"
echo "Debian/Ubuntu package management"
echo "  dpkg -l                      # List installed packages"
echo "  dpkg -L packagename          # List files in package"
echo "  dpkg -i package.deb          # Install .deb package"
echo "  dpkg -r packagename          # Remove package"
echo

# du - Already covered above

# deluser/delgroup
echo "--- deluser/delgroup ---"
echo "Remove user or group from system"
echo "  sudo deluser username        # Delete user"
echo "  sudo delgroup groupname      # Delete group"
echo

echo "=== NETWORK COMMANDS ==="
echo

# dig - DNS lookup
echo "--- dig (domain information groper) ---"
echo "DNS lookup utility"
echo "  dig example.com              # Query DNS"
echo "  dig @8.8.8.8 example.com     # Use specific DNS server"
echo "  dig example.com MX           # Mail exchange records"
echo "  dig -x 8.8.8.8               # Reverse DNS lookup"
echo

# dhclient - DHCP client
echo "--- dhclient ---"
echo "DHCP client for obtaining network configuration"
echo "  sudo dhclient -r             # Release IP"
echo "  sudo dhclient eth0           # Request IP for eth0"
echo

echo "=== DATABASE COMMANDS ==="
echo

# db_* commands - Database utilities
echo "--- database commands ---"
echo "Berkeley DB utilities:"
echo "  db_dump                      # Dump database to text"
echo "  db_load                      # Load database from text"
echo "  db_stat                      # Database statistics"
echo

echo "=== TEXT & DOCUMENT COMMANDS ==="
echo

# dos2unix/unix2dos
echo "--- dos2unix/unix2dos ---"
echo "Convert line endings"
echo "  dos2unix file.txt            # DOS to Unix (CRLF to LF)"
echo "  unix2dos file.txt            # Unix to DOS (LF to CRLF)"
echo

# dict - Dictionary lookup
echo "--- dict ---"
echo "Dictionary lookup client"
echo "  dict word                    # Look up definition"
echo

echo "=== DEVICE & HARDWARE COMMANDS ==="
echo

# df - Already covered

# dumpkeys - Dump keyboard mapping
echo "--- dumpkeys ---"
echo "Display keyboard translation tables"
echo "  sudo dumpkeys                # Show current keymap"
echo

echo "=== DOWNLOAD & TRANSFER ==="
echo

# docker - Container platform
echo "--- docker ---"
echo "Container management (if installed)"
echo "  docker ps                    # List running containers"
echo "  docker images                # List images"
echo "  docker run imagename         # Run container"
echo

echo "=== MISCELLANEOUS ==="
echo

# declare - Declare variables
echo "--- declare ---"
echo "Bash builtin for variable attributes"
declare -i num=10           # Integer variable
declare -r CONST="value"    # Read-only variable
declare -a array=(1 2 3)    # Array
declare -A assoc=([key]=val) # Associative array
declare -p num              # Show variable attributes
echo

# dpkg-query
echo "--- dpkg-query ---"
echo "Query dpkg database"
echo "  dpkg-query -l                # List packages"
echo "  dpkg-query -W                # Show package info"
echo

# dc - Desk calculator
echo "--- dc (desk calculator) ---"
echo "Reverse-polish calculator"
echo "  echo '5 3 + p' | dc         # Calculate 5+3"
echo

# done - Bash keyword
echo "--- done ---"
echo "Bash keyword to close loops (for, while, until)"
echo

# disown - Job control
echo "--- disown ---"
echo "Remove jobs from shell's job table"
echo "  disown %1                    # Disown job 1"
echo "  disown -a                    # Disown all jobs"
echo

# dvd+rw-* - DVD burning tools
echo "--- DVD burning tools ---"
echo "  dvd+rw-format                # Format DVD+RW"
echo "  dvd+rw-mediainfo             # Show DVD media info"
echo

echo "=== SYSTEM DAEMON COMMANDS ==="
echo

# daemon - Run process as daemon
echo "--- daemon ---"
echo "Turn process into daemon"
echo

# dbus - Message bus system
echo "--- dbus-* commands ---"
echo "D-Bus message bus commands"
echo "  dbus-send                    # Send D-Bus message"
echo "  dbus-monitor                 # Monitor D-Bus messages"
echo

echo "=== END OF D COMMANDS REFERENCE ==="