#!/bin/sh

# Help
[ "$1" = "--help" ] && { echo Usage: $0 core.gz mycore.gz ; exit 0 ; }

# Tests
[ ! -e "$1" ] && { echo need existing core.gz path as first parameter. ; exit 1 ; }
[ ! -n "$2" ] && { echo need output gz name as parameter \(e.g. mycore.gz\). ; exit 1 ; }
[ `id -u` -ne 0 ] && { echo must be root. ; exit 1 ; }
[ -z "`which advdef`" ] && { echo install advcomp. ; exit 1 ; }
[ "`which find`" != "/usr/local/bin/find" ] && { echo install findutils. ; exit 1 ; }

# Source tc functions
. /etc/init.d/tc-functions

# Vars
TCKERNEL=`uname -r`
WORKDIR=`pwd`
TCEDIR="/etc/sysconfig/tcedir"
OLDSIZE=0
SRCFSNAME=`basename $1`
SRCFSSIZE=`ls -l $1 | awk '{print $5}'`
DESTFSNAME=`basename $2`
	
# Starting 
echo "${YELLOW}Using initramfs ${WHITE}$SRCFSNAME [ `dc $SRCFSSIZE 1000000 div p | sed 's%\([0-9]*\.[0-9]\{2\}\).*%\1%'` MB ].${YELLOW}" 
[ -f "$2" ] && { echo Removing old target file. ; rm -f "$2" ; }
tgztemp=`mktemp -d -p $WORKDIR`
chmod -R ugo+rwx $tgztemp
cp $1 $tgztemp/
cd $tgztemp
zcat $SRCFSNAME | cpio -i -H newc -d 2>/dev/null
find . -name *.ko.gz | sed 's%^\./%%g' > $WORKDIR/$SRCFSNAME.modlist
rm $SRCFSNAME

# Copying extension modules
for mod_ext_dir in `find /tmp/tcloop -maxdepth 1 -type d -name "*$TCKERNEL*"` ; do
  if [ -d "$mod_ext_dir/usr/local/lib/modules/$TCKERNEL" ] || [ -d "$mod_ext_dir/lib/modules/$TCKERNEL" ]; then
    short_dir=`basename $mod_ext_dir`
    mod_ext_size=`ls -l $TCEDIR/optional/$short_dir.tcz | awk '{print $5}'`
    OLDSIZE=`echo "$OLDSIZE $mod_ext_size add p" | dc`
    mkdir -p usr/local/tce.installed 2>/dev/null
    echo "Including modules from: ${WHITE}`basename $mod_ext_dir`${YELLOW}."
    touch usr/local/tce.installed/`basename $mod_ext_dir` && chown tc:staff usr/local/tce.installed/`basename $mod_ext_dir`
    cp -apfr $mod_ext_dir/usr/local/lib/modules/$TCKERNEL/* lib/modules/$TCKERNEL/ 2>/dev/null
    cp -apfr $mod_ext_dir/lib/modules/$TCKERNEL/* lib/modules/$TCKERNEL/ 2>/dev/null
  fi
done

# Removing unneeded modules
for mod_file in `find lib/modules/$TCKERNEL -name *.ko.gz` ; do
  sstr="$(basename $mod_file | sed -e 's%.ko.gz%%' -e 's%-%_%g' )"
  loaded=$(lsmod | grep -e "^$sstr[[:space:]]\{1\}")
  [ -z "$loaded" ] && rm -f $mod_file || echo "Saving ${RED}`basename $mod_file`${YELLOW}."
done

# Remove empty directories
find lib/modules/$TCKERNEL -type d -empty | xargs rm -rf

# Running depmod
/sbin/depmod -a -b $tgztemp $TCKERNEL || echo depmod failed.

# Packing new gz
[ -d "usr/local/tce.installed" ] && find usr/local/tce.installed/ -name "*$TCKERNEL" | sed 's%^\./%%g' > $WORKDIR/$DESTFSNAME.modlist
find . -name *.ko.gz | sed 's%^\./%%g' >> $WORKDIR/$DESTFSNAME.modlist
find | cpio -o -H newc | gzip -2 > $WORKDIR/temp.gz.$$
cd $WORKDIR
advdef -z4 temp.gz.$$ 1>/dev/null 2>&1
mv temp.gz.$$ $2
rm -rf $tgztemp

# Summary
OLDSIZE=$(echo "$OLDSIZE `ls -l $1 | awk '{print $5}'` add 1000000 div p" | dc | sed 's%\([0-9]*\.[0-9]\{2\}\).*$%\1%')
NEWSIZE=$(echo "`ls -l $2 | awk '{print $5}'` 1000000 div p" | dc | sed 's%\([0-9]*\.[0-9]\{2\}\).*$%\1%')
echo "Summary of used and saved space:"
echo "-------------------------------------------"
echo "${WHITE}Before :   $SRCFSNAME + mod exts   :  $OLDSIZE MB"
echo "${GREEN}After${WHITE}  :   ${GREEN}$DESTFSNAME${WHITE}            :  ${GREEN}$NEWSIZE MB"
echo "${YELLOW}-------------------------------------------${NORMAL}"
