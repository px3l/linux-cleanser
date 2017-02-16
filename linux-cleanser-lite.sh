#!/bin/bash

echo -e
echo -e
GRAY="\033[1;30m"
RED="\033[0;31m"
ENDCOLOR="\033[0m"
echo -e $GRAY"  ====================================================  "$ENDCOLOR
echo -e $GRAY" ===                                                === "$ENDCOLOR
echo -e $GRAY"==               "$RED"Linux-cleanser Lite by px3l"$GRAY"          =="$ENDCOLOR
echo -e $GRAY" ===                                                === "$ENDCOLOR
echo -e $GRAY"  ====================================================  "$ENDCOLOR
echo -e
echo -e

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

echo -e $YELLOW"[Linux-cleanser]:Emptying the trash..."$ENDCOLOR
rm -rf /home/*/.local/share/Trash/*/** &> /dev/null
rm -rf /root/.local/share/Trash/*/** &> /dev/null

echo -e $YELLOW"[Linux-cleanser]:Clearing all bash history..."$ENDCOLOR
rm ~/.bash_history

echo -e $YELLOW"[Linux-cleanser]:Script Finished!"$ENDCOLOR
echo -e
echo -e $RED"Cleansing complete."$ENDCOLOR
echo -e
