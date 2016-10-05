#This has been adapted from the kali-cleaner by THIS GUY
#Kudos to him for the difficult bit.

#!/bin/bash
echo -e
echo -e
GRAY="\033[1;30m"
RED="\033[0;31m"
ENDCOLOR="\033[0m"
echo -e $GRAY"  ====================================================  "$ENDCOLOR
echo -e $GRAY" ===                                                === "$ENDCOLOR
echo -e $GRAY"==               "$RED"Linux-cleanser by px3l"$GRAY"               =="$ENDCOLOR
echo -e $GRAY" ===                                                === "$ENDCOLOR
echo -e $GRAY"  ====================================================  "$ENDCOLOR
echo -e
echo -e
                                                                                                                                                                                                                                         
OLDCONF=$(dpkg -l|grep "^rc"|awk '{print $2}')
CURKERNEL=$(uname -r|sed 's/-*[a-z]//g'|sed 's/-386//g')
LINUXPKG="linux-(image|headers|debian-modules|restricted-modules)"
METALINUXPKG="linux-(image|headers|restricted-modules)-(generic|i386|server|common|rt|xen)"
OLDKERNELS=$(dpkg -l|awk '{print $2}'|grep -E $LINUXPKG|grep -vE $METALINUXPKG|grep -v $CURKERNEL)

YELLOW="\033[1;33m"
RED="\033[0;31m"
ENDCOLOR="\033[0m"
 
if [ $USER != root ]; then
echo -e $RED"[Linux-cleanser]:Error: must be root"
echo -e $YELLOW"[Linux-cleanser]:Exiting..."$ENDCOLOR
echo -e
exit 0
fi

echo -e $YELLOW"[Linux-cleanser]:Flushing local cache from the retrieved package files..."$ENDCOLOR
sudo apt-get clean

echo -e $YELLOW"[Linux-cleanser]:Clearing non-necessary packages..."$ENDCOLOR
sudo apt-get autoclean

echo -e $YELLOW"[Linux-cleanser]:Removing redundant dependencies..."$ENDCOLOR
sudo apt-get -y autoremove

echo -e $YELLOW"[Linux-cleanser]:Cleaning apt cache..."$ENDCOLOR
sudo aptitude clean

echo -e $YELLOW"[Linux-cleanser]:Found old config files: "$ENDCOLOR $OLDCONF
echo -e $YELLOW"[Linux-cleanser]:Removing old config files..."$ENDCOLOR
sudo aptitude purge $OLDCONF

echo -e $YELLOW"[Linux-cleanser]:Found old kernel files: "$ENDCOLOR $OLDKERNELS
echo -e $YELLOW"[Linux-cleanser]:Removing old kernels..."$ENDCOLOR
sudo aptitude purge $OLDKERNELS

echo -e $YELLOW"[Linux-cleanser]:Emptying the trash..."$ENDCOLOR
rm -rf /home/*/.local/share/Trash/*/** &> /dev/null
rm -rf /root/.local/share/Trash/*/** &> /dev/null

echo -e $YELLOW"[Linux-cleanser]:Script Finished!"$ENDCOLOR
echo -e
echo -e $RED"Cleansing complete."$ENDCOLOR
echo -e
