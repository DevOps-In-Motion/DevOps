# get the 1st column of stdout command
your-command | awk 'NR>1 {print $1}'

# LFCS Command Cheat Sheet
### ----- Essential Commands ---- ###

# reindex commands 
sudo mandb

# Linux/Unix command that searches the manual page descriptions for keywords. 
# It's useful when you know what you want to do but don't know the exact command name.
apropos "NFS mounts"

hostnamectl # change the static hostname of your Linux system
# That will show a lot more status messages and help
# you debug why this connection is failing.
ssh -v alex@localhost
ls -la /home/bob/data/ # Find hidden files in a given directory
touch /home/bob/myfile # Create a file name myfile in the /home/bob/ directory
apropos "NFS mounts"
# Search the manual page names and descriptions for
# keywords.

findmnt /dev/vda1 # Show mount options used with /dev/vda1
umount /mnt # Manually unmount filesystems
mount -o ro,noexec,nosuid \
/dev/vdb1 /mnt
# Mount /dev/vdb1 into the /mnt/ directory, use mount
# options: ro,noexec,nosuid


# Stage all the files with the .cpp extension to prepare  them for a future commit
git add *.cpp
git commit -m "Message" # Commit the files with the commit message
git branch testing # Create a branch with the name testing
git checkout master # Check out to master branch
git branch --delete testing # Delete the testing branch
git log --raw # Check for the file modified in the latest commit
git merge "branch name" # Merge the branch to the master branch
git pull origin master # Pull in the latest commits from the remote repository
git push origin master # Push changes to master branch of remote repository
git clone "repository" # Clone the repo


### ----- Operations Deployment ---- ###
shutdown +120 # Schedule this system to power off two hours later from now
grub-install /dev/vda # Install grub to /dev/vda
systemctl get-default # Find out what is the system's current default boot target
shutdown -c
systemctl daemon-reload # Reload systemd manager configuration

# See all processes running on the system, along with their
# nice values
ps lax

sleep 10 # Sleep for 10 seconds
renice 9 <PID> # Assign a nice value of 9 to process
lsof -p 1 # List all files that are opened by process with PID 1
pgrep -a rpcbind # Identify the PID of the process named rpcbind
kill -SIGHUP <pid> # Send the SIGHUP signal to PID

# Under `/var/log` directory, search for all files containing the
# `reboot` string
grep -r --text 'reboot' \
  /var/log/

# Identify the CPU and Memory usage by only the process
# having PID 1
# [command] & # Running command in the background
ps u 1

crontab -l # See the crontab for theroot user

# Force anacron to rerun all jobs, regardless of when they
# were last executed
anacron -n -f

atq # List currently scheduled jobs under current user
atrm <jobid> # Remove the job with JOBID
apt search "apache http \
server" # Search for package
apt install apache2 # Install the Apache web server
dpkg --search /bin/ls # Find out the name of the package that "/bin/ls" belongs to.
dpkg --listfiles coreutils | \
grep ^/bin # list the files that belong to coreutils package

# Uninstall the package ziptool and its dependency
# package(s) from the system.
apt-get remove \
  --auto-remove -y ziptool

free --mega # Show the memory on this system (in megabytes)
uptime # Show how long this system is up
lscpu # Show CPU architecture information from sysfs
xfs_repair /dev/vdb # Check /dev/vdb XFS filesystem for errors
sysctl -w \
  kernel.modules_disabled \
  =1 # Turn on kernel.modules_disabled kernel runtime parameter
ls -Z /bin/sudo # Check out the SELinux label for the file stored at /bin/sudo

# Change the SELinux context of /var/index.html file to
# httpd_sys_content_t
chcon -t \
  httpd_sys_content_t \
  /var/index.html

# Temporarily change the SELinux status to Permissive on
# this system
setenforce 0

semanage user -l # Identify the SELinux Roles for staff_u SELinux user

# Restore the correct (default) labels for every file and
# subdirectory in the /var/log directory
restorecon -R /var/log/






### ----- Networking ---- ###
ss -tunlp
# Show processes on our system are listening for incoming
# network connections, on the TCP and UDP protocols
ip a
# Displays information about interfaces, devices, routing, and
# tunnels
ip route show # Display the IPv4 routing table of a router
ip a add 192.168.9.3/24 \
  dev eth1 # Add a temporary extra IP to the eth1 interface
netplan apply
# Applies the current netplan configuration to a running
# system
netstat -tulpn # Get the list of all incoming open ports on this system
timedatectl # Check for the Time zone
timedatectl set-timezone \
  America/New_York # Set the time zone to America, New York
ufw enable # Turn on UFW
ufw allow 22 # Allow SSH on port 22
ufw deny 443/tcp
# Deny incoming traffic to this machine on port 443, through
# the TCP protocol
ufw delete deny 443/tcp
# Delete a firewall rule denying incoming traffic to this
# machine on port 443, through the TCP protocol
ufw status numbered # List numbered firewall rules
ufw allow from \
  207.45.232.181
# Allow all traffic that is coming from the following IP address
# 207.45.232.181
ufw allow from \
  10.11.12.0/24
# Allow all traffic that is coming from any IP in this network
# range: 10.11.12.0 to 10.11.12.255 (i.e 10.11.12.0/24)
ufw delete 8 # Delete a numberd firewall rule


### ----- Storage ---- ###
lsblk # Display block devices, such as disks or partitions
mkswap /dev/vdb3
# Format a partition as swap space. Where /dev/vdb3
# is the partition we want to format
swapon --show # Identify the swapfile
fdisk /dev/vdb # Update primary partitions on /dev/vdb
mkswap /dev/vdb2 # Format the /dev/vdb2 partition as swap
swapon /dev/vdb2 # Active swap for /dev/vdb2 partition
swapoff /dev/vdb2 # Stop the /dev/vdb2 partition as swap
cfdisk
# To create, delete, and modify partitions on a disk
# device
mkfs.xfs -L "DataDisk" /dev/vdb
# To create an xfs filesystem with the label "DataDisk"
# on /dev/vdb
mkfs.ext4 -N 2048 /dev/vdc
# To create an ext4 filesystem with a number of 2048
# inodes on /dev/vdc
mount /dev/vdb /mnt # Mount /dev/vdb in the /mnt/ directory
umount /mnt
# Unmount the filesystem mounted in the /mnt/
# directory
xfs_admin -L "SwapFS" /dev/vdb # Change the label for /dev/vdb filesystem to SwapFS
findmnt /dev/vda1 # Show mount options used with /dev/vda1
exportfs -r # To reexport the /etc/exports configuration
pvcreate /dev/vdb /dev/vdc
# Add these two disks as PVs (Physical Volumes) to
# LVM: /dev/vdb, /dev/vdc
pvs
# Display a list of Physical Volumes (PVs) used by
# LVM
pvremove /dev/vdc # Remove the /dev/vdc physical volume from LVM
vgcreate volume1 /dev/vdb
# Create a Volume Group (VG) named volume1 which
# created on Physical Volume: /dev/vdb
vgextend volume1 /dev/vdc
# Increases a volume group's capacity by adding one
# or more free physical volumes
vgreduce volume1 /dev/vdc # Remove /dev/vdc from the volume group volume1
vgs # Displays all of the volume groups
lvcreate # Create a Logical Volume (LV)
lvresize --size 752M \
  volume1/smalldata
# Resize the Logical Volume called smalldata to 752
# MB (volume group called volume1)
mkfs.xfs /dev/volume1/smalldata
# Create an XFS filesystem on the logical volume
# called smalldata (volume group called volume1)
lvremove volume1/smalldata # Remove the Logical Volume called smalldata
getfacl archive # List the ACL permissions associated with archive file
mdadm --create /dev/md0 \
  --level=1 --raid-devices=2 \
  /dev/vdb /dev/vdc
# Create a level 1 RAID array, at /dev/md0, with two
# devices: /dev/vdb and /dev/vdc
setfacl --modify user:john:rw \
  specialfile
# Add an ACL permission to specialfile file so that the
# user called john can read and write to it
setfacl --remove user:john \
  pecialfile
# Remove the ACL permissions for the user called
# john for specialfile file
setfacl --modify group:mail:rx \
  specialfile
# Add an ACL permission for the group called mail. The
# mail group should get permissions to read and
# execute specialfile file.
setfacl --recursive --modify \
  user:john:rwx collection/
# Update ACL permissions for collection folder and all
# its contents, allowing the user john to read, write, and
# execute everything inside
xfs_quota -x -c 'limit bsoft=100m bhard=500m john' /dev/vda1

# Edit disk quotas for the user called john. Set a soft
# limit of 100 megabytes and hard limit of 500
# megabytes on /dev/vda1 partition


### ----- Scheduling ----- ###
# schedule the system to turnoff two hours from now
sudo shutdown +120 "System will shut down in 2 hours."
# cancel the shutdown
sudo shutdown -c


### ----- Startup ----- ###
# change the startup to GUI and not text based
sudo systemctl set-default graphical.target


### ----- Monitoring ----- ###
# There is a service unit that automatically starts up the SSH daemon. 
# Use the correct command to find out the PID 
# assigned to the process launched by this service.
# Save the PID in /home/bob/pid file.
# Find the PID of the SSH daemon service and save it to /home/bob/pid
systemctl show sshd
systemctl show --property MainPID sshd | cut -d'=' -f2 > /home/bob/pid

systemctl is-enabled sshd # displays if the sshd.service unit is enabled or disabled.

df / # Identify what % space of / partition is in use on our system
du -sh /bin/ # Show storage space of the /bin/ directory

nproc # Limit the number of processes a user can run
echo $MYVAR # Print the value of an environment variable
env # Print our current user environment


### ----- Archive ----- ###

# Create a compressed tar archive called archive.tar.gz from the directory dir1
tar -czvf archive.tar.gz dir1
tar -czvf ~/project/backups/system-backup.tar.gz -T backup-list.txt
# list all files verbosely
tar -tvf file.tar.gz > backup-contents.txt
# unpack only one file from a tar.gz
tar -f archive.tar.gz -x /path/to/file/in/archive
# extract archive to different location
tar -xf archive.tar -C /opt/files
bzip2 --keep /home/bob/file.txt
gzip games.txt

#uncompress
unxz lfcs.txt.xz
sort -du /home/bob/values.conf > /home/bob/values.sort


### ----- Security & Permissions ----- ###
chmod 0100 /home/bob/dir8
# Set permissions on /home/bob/dir8: user owner has execute, group and others have no permissions.

# Generate a key and certificate signing request
openssl req -newkey rsa:4096 \
  -keyout priv.key -out cert.csr 
openssl x509 -in my.crt -text # Identify the CN of certificate  


### ----- Users and Groups ---- ###
usermod -e \
  2030-03-01 jane # Set the jane user account to expire on March 1, 2030
usermod -e "" jane # Unexpire Jane's account and make sure it never expires again
useradd -s /bin/csh \
  -m jack
# Create a user account called jack with home directory and set its
# default login shell to be /bin/csh
userdel -r jack
# Delete the user account called jack and ensure his home directory
# is removed
chage --lastday 0 \
  jane
# Mark the password for jane as expired to force her to immediately
# change it the next time she logs in.

source ~/.bashrc # To refresh the current shell environment by re-reading
touch path/file # To create new, empty files
chmod u+x ./script.sh # Make script executable
usermod -a -G developers jane # Add the user jane to the group called developers
groupadd -g 9875 cricket
# Create a group named cricket and set its GID to
# 9875
groupmod -n soccer cricket
# Rename cricket group to soccer while preserving the
# same GID
useradd -G soccer sam --uid \
5322
# Create a user sam with UID 5322, also make it a
# member of soccer group.
usermod -g rugby sam # Update primary group of user sam and set it to rugby
usermod -L sam # Lock the user account called sam
groupdel appdevs # Delete the group called appdevs
chage -W 2 jane
# Make sure the user jane gets a warning at least 2
# days before the password expires
gpasswd -a trinity wheel
# Allow the user called trinity to execute any sudo
# command



### --- Processes --- ###
# The nohup command stands for "no hang up."
nohpup [COMMAND] -options
# You can redirect standard output with > and standard error with 2>&1.
# everything from stderr and stdout will go to name.log
nohup ./script > name.log 2>&1 & 
sudo ./script.sh > /home/bob/output.txt 2>&1
# everything from stdout ONLY will go to name.log
nohup ./script > name.log &
./script > name.log & # prob don't need nohup
# errors ONLY
sudo ./script.sh 2> /home/bob/output_errors.txt



### --- Services --- ###
# Command we can see what processes on our system are listening for 
# incoming network connections, on the TCP and UDP protocols.
sudo ss -tunlp 
ip a # check the network addresses and subnets
ip route show
# Find out what process is listening for incoming connections on port 22 and identify its PID.
sudo ss -tlnp | grep :22
sudo nano /etc/hosts # > add a new host configuration
# Add a temporary IP address to eth1 (will not persist after reboot)
sudo ip addr add 192.168.1.100/24 dev eth1

sudo chmod 600 /etc/netplan/99-custom.yaml
sudo netplan apply

