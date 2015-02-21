#! /usr/bin/env bash
###
# Script: mc.sh
# Use: Automate minecraft administrative tasks
# Author by: livErD69
# Based off work by Talisker, assumes Ubuntu/Debian.
# Creation date: 11/07/11
# Update date: 02/21/15
###
. /etc/profile
. ~/.profile
# Variables to edit
WORLD=yellowstone
OLDWORLD=michigan
WEBDIR=/var/www
MCUSER=minecraft
MCVER="1.8.3"
# Shouldn't need to edit these
NEWWORLD="$WORLD"
ARCHDIR=$WEBDIR/archive
MAPDIR=$WEBDIR/map
MCHOME=/home/$MCUSER
SCRIPTDIR=/$MCHOME/scripts
SERVERHOME=$MCHOME/server
NOW=$(date +"%y%m%d%H%M")
TARFILE="$WORLD"_"$NOW"
OVDIR=$MCHOME/overviewer
OVTMP=$OVDIR/_tmp
OVTMPWORLD=$OVTMP/world
OVTMPOUTPUT=$OVTMP/output
OVCFG=$SCRIPTDIR/overviewer.cfg
UPSTART=/etc/init/minecraft.conf 

case "$1" in
  setup)
	echo "making $MCUSER user"
	sudo adduser $MCUSER
	echo "cloning overviewer from git"
	cd $MCHOME
    git clone https://github.com/overviewer/Minecraft-Overviewer.git overviewer
	echo "creating all directory structures"
	mkdir -p $WEBDIR $ARCHDIR $ARCHDIR/$WORLD $MAPDIR $MCHOME $SCRIPTDIR $SERVERHOME $OVDIR $OVTMP $OVTMPWORLD $OVTMPOUTPUT
	echo "Creating upstart file"
cat << EOF > $UPSTART
description "start and stop the minecraft-server"

start on runlevel [2345]
stop on runlevel [^2345]

console log

chdir $SERVERHOME

# Standard MC
exec /usr/bin/java -Xms2048M -Xmx2048M -jar minecraft_server.$MCVER.jar nogui

setuid $MCUSER
setgid $MCUSER

respawn
respawn limit 20 5
EOF
	
	echo "Creating Overviewer config"
cat << EOF > $OVCFG
worlds["$WORLD"] = "$OVTMPWORLD"

renders["$WORLD.day"] = {
	"world": "$WORLD",
	"title": "daytime",
	"rendermode": smooth_lighting,
	"imgformat": "jpg",
	"imgquality": 80,
}

renders["$WORLD.cave"] = {
	"world": "$WORLD",
	"title": "cave",
	"rendermode": cave,
	"imgformat": "jpg",
	"imgquality": 80,
}

# Leave this commented out until you unlock the nether realm!
#renders["$WORLD.nether"] = {
#	"world": "$WORLD",
#	"title": "nether",
#	"rendermode": nether_smooth_lighting,
#	"imgformat": "jpg",
#	"imgquality": 80,
#	"dimension": "nether",
#}

# Leave this commented out until you unlock the end realm!
#renders["$WORLD.end"] = {
#    "world": "$WORLD",
#    "title": "end",
#    "rendermode": smooth_lighting,
#    "imgformat": "jpg",
#    "imgquality": 80,
#    "dimension": "end",
#}

outputdir = "$OVTMPOUTPUT"
texturepath = "$MCHOME/.minecraft/versions/$MCVER/$MCVER.jar"
EOF
	
	echo "Setting permissions on $MCUSER home & webdir"
	sudo chown -R $MCUSER: $MCHOME
	sudo chown -R $MCUSER: $WEBDIR
	echo "All done, make sure to install java, and a web server!"
  ;;
  backup-world)
	# Use the TMP copy, so as to not mess with the running world
	echo "creating tar file..."
	cd $OVTMP
	tar -zcvf $TARFILE.tgz world/ ; mv -f $TARFILE.tgz $ARCHDIR/$WORLD/$TARFILE.tgz
	echo "cleaning up old tar files..."
	find "$ARCHDIR/$WORLD/" -mtime +60 -delete
  ;;
  rename-world)
	sudo service minecraft stop
	### Rename the world in the config file
	echo "Updating world name from $OLDWORLD to $NEWWORLD"
	sed -i "s/$OLDWORLD/$NEWWORLD/g" $SERVERHOME/server.properties
	### Update web dir for backup archive and make final backup
	echo "Making Final backup and a new archive dir, CLEAN OLDWORLD MANUALLY!"
	cd $SERVERHOME
	tar -zcvf "$OLDWORLD"_Final.tgz $OLDWORLD ; mv -f "$OLDWORLD"_Final.tgz $ARCHDIR
	mkdir $ARCHDIR/$NEWWORLD
	### Update Overviewer config
	echo "Updating Overviewer config file to use $NEWWORLD instead of $OLDWORLD"
	sed -i "s/$OLDWORLD/$NEWWORLD/g" $OVCFG
	### Flush Overviewer ~tmp directories and web dir
	echo "Flushing overviewer.  Please run update-map to regenerate!"
	rm -rf $OVTMPWORLD/*
	rm -rf $OVTMPOUTPUT/*
	rm -rf $MAPDIR/*
  ;;
  update-map)
	echo "copying world..."
	rsync --delete --delay-updates -a $SERVERHOME/$WORLD/ $OVTMPWORLD
	### If hosted use: wget -m -nH --cut-dirs=1 $URLPASS
	cd $OVDIR
	### I render the map into a temp directory, so that things don't get wonky
	### if you try to use the map while an update is getting generated
	echo "generating map..."
	nice -n 19 $OVDIR/overviewer.py --config=$OVCFG
	### Old way: ./overviewer.py --rendermodes=lighting,smooth-lighting,cave $TMPWORLD $TMPOUTPUT
	### when the map is done, I rsync it over to the web dir
	echo "copying to web dir..."
	rsync --delete --delay-updates -a $OVTMPOUTPUT/ $MAPDIR
  ;;
  upgrade-mc)
	cd $SERVERHOME
	mv minecraft_server.jar minecraft_server.old 2> /dev/null
	wget https://s3.amazonaws.com/Minecraft.Download/versions/$MCVER/minecraft_server.$MCVER.jar
	chown -R $MCUSER: $MCHOME
  ;;
  upgrade-map)
	#Update the Overviewer
	cd $OVDIR
	git clone https://github.com/overviewer/Minecraft-Overviewer.git overviewer
	git fetch
	python setup.py build  
	#Fetch latest jar for texturing, copy to the places and set permissions
	cd $MCHOME
	wget https://s3.amazonaws.com/Minecraft.Download/versions/$MCVER/$MCVER.jar -P $MCHOME/.minecraft/versions/$MCVER/
	chown -R $MCUSER: $MCHOME
  ;;
  *)
	echo "Usage: ./mc.sh {setup|backup-world|rename-world|update-map|upgrade-mc|upgrade-map}"
	exit 1
  ;;
esac

exit 0
