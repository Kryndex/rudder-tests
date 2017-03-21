#!/bin/sh

# Various cleanups to apply on the Vagrant boxes we use.
# no set -e since some things are expected to fail

postclean() {
  ### THINGS TO DO ON AN ALREADY CLEAN BOX
  if type curl >/dev/null 2>/dev/null
  then
    curl -s -o /usr/local/bin/rudder-setup https://www.rudder-project.org/tools/rudder-setup
    curl -s -o /usr/local/bin/ncf-setup https://www.rudder-project.org/tools/ncf-setup
  else
    wget -q -O /usr/local/bin/rudder-setup https://www.rudder-project.org/tools/rudder-setup
    wget -q -O /usr/local/bin/ncf-setup https://www.rudder-project.org/tools/ncf-setup
  fi
  
  chmod +x /usr/local/bin/rudder-setup /usr/local/bin/ncf-setup
  cp /vagrant/scripts/ncf /usr/local/bin/
  cp /vagrant/scripts/lib.sh /usr/local/bin/
  cp /vagrant/scripts/version-test.sh /usr/local/bin/
  chmod +x /usr/local/bin/ncf
  
  id > /tmp/xxx
}

# bos is clean
if [ -f /root/clean ]
then
  postclean
  exit 0
fi


### THINGS TO DO ON A DIRTY BOX

# force DNS server to an always valid one (all)
cat << EOF > /etc/resolv.conf
# /etc/resolv.conf, built by rtf (Rudder Test Framwork)
options rotate
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

chattr +i /etc/resolv.conf /etc/resolvconf/run/resolv.conf 2>/dev/null

# remove "stdin: not a tty" error on some box
[ -e /root/.profile ] && sed -e 's/^mesg n$/tty -s \&\& mesg n/g' /root/.profile > /root/.profile2 2>/dev/null && mv /root/.profile2 /root/.profile

# Enable SELinux (all)
if [ -f /etc/sysconfig/selinux ]
then
  setenforce 1 2>/dev/null
  sed -i -e 's/^SELINUX=.*/SELINUX=enabled/' /etc/sysconfig/selinux
fi

# French keyboard on console
if [ -f /etc/sysconfig/keyboard ]
then
  cat > /etc/sysconfig/keyboard <<EOF
KEYTABLE="fr"
MODEL="pc105+inet"
LAYOUT="fr"
KEYBOARDTYPE="pc"
EOF
elif [ -f /etc/default/keyboard ]
then
  cat >/etc/default/keyboard <<EOF
XKBMODEL="pc105"
XKBLAYOUT="fr"
XKBVARIANT="latin9"
XKBOPTIONS=""

BACKSPACE="guess"
EOF
fi
loadkeys fr

# force root password to root
sed -e 's|^root.*|root:$6$5.6rg6Xl$be5jxAm7/HyoL.3xmgwZRv7XkyqChB1vc.v7VgMeX7Di8C3TtKSgt5DmTFE0PsJxTI8d4eAtE5IRFToFsn4vF/:16638:0:99999:7:::|' /etc/shadow > /etc/shadow2 && mv /etc/shadow2 /etc/shadow

# Disable firewall (RHEL)
if [ -f /etc/redhat-release ]
then
  chkconfig iptables off 2>/dev/null
  chkconfig firewalld off 2>/dev/null
  service iptables stop 2>/dev/null
  service firewalld stop 2>/dev/null
fi

# Setup Debian / Ubuntu packaging (debian/ubuntu)
if type apt-get 2>/dev/null
then
  export DEBIAN_FRONTEND=noninteractive  

  # pre answer interactive questions from oracle
  cat << EOF | debconf-set-selections
sun-java6-bin   shared/accepted-sun-dlj-v1-1    boolean true
sun-java6-jre   shared/accepted-sun-dlj-v1-1    boolean true
oracle-java8-installer  shared/present-oracle-license-v1-1  note 
oracle-java8-installer  shared/accepted-oracle-license-v1-1 boolean true
oracle-java8-installer  shared/error-oracle-license-v1-1  error 
oracle-java8-installer  oracle-java8-installer/not_exist  error 
oracle-java8-installer  oracle-java8-installer/local  string  
EOF

  # Replace repos by archive for Debian Squeeze
  grep -e "^6\." /etc/debian_version > /dev/null
  squeeze=$?
  if [ $squeeze -eq 0 ] ;
  then
    echo "deb http://archive.debian.org/debian/ squeeze main" > /etc/apt/sources.list
  fi

  apt-get update

  # make sure lsb_release command is available
  apt-get install --force-yes -y lsb-release

  # Old Ubuntu releases need to use the old-releases mirror instead of the default one
  if hash lsb_release 2>/dev/null && [ "$(lsb_release -cs)" = "quantal" ]
  then
    echo "deb http://old-releases.ubuntu.com/ubuntu/ quantal main restricted universe" > /etc/apt/sources.list
    echo "deb http://old-releases.ubuntu.com/ubuntu/ quantal-updates main restricted universe" > /etc/apt/sources.list
    apt-get update
  fi

  if hash service 2>/dev/null
  then
    :
  else
    apt-get install --force-yes -y sysvconfig
  fi

  apt-get install --force-yes -y apt-transport-https

  # specific to debian7 / rudder server 2.11.6-4
  apt-get install --force-yes -y libltdl7
fi

# Setup SLES packaging (suse)
if [ -f /etc/SuSE-release ]
then

  # Get the running SLES version
  SLES_VERSION=`grep "VERSION" /etc/SuSE-release|sed "s%VERSION\ *=\ *\(.*\)%\1%"`
  SLES_SERVICEPACK=`grep "PATCHLEVEL" /etc/SuSE-release|sed "s%PATCHLEVEL\ *=\ *\(.*\)%\1%"`

  ln -s /usr/sbin/update-alternatives /usr/sbin/alternatives
  if [ "$(uname -m)" = "x86_64" ]
  then

    if [ ${SLES_VERSION} -eq 12 ] && [ ${SLES_SERVICEPACK} -ge 1 ]
    then
      # do not preinstall java on sles12
      true
    else
      echo "Installing JDK8" 
      wget -q -O /tmp/jdk.rpm https://www.normation.com/tarball/java/jdk-8u101-linux-x86_64.rpm
      rpm -iv /tmp/jdk.rpm | grep '^.$' || true
    fi

    rm -f /etc/zypp/repos.d/*.repo

    # Add the repositories corresponding to the running SLES version
    if [ ${SLES_VERSION} -eq 11 ] && [ ${SLES_SERVICEPACK} -eq 1 ]
    then
      zypper ar -f "http://ci.normation.com/sles-repo/SLES-11-SP1-DVD-x86_64-GM-DVD1/" "SLES_11_SP1_DVD1" > /dev/null
      zypper ar -f "http://ci.normation.com/sles-repo/SLES-11-SP1-64-SDK-DVD1/"        "SLES_11_SP1_DVD2" > /dev/null
    fi

    if [ ${SLES_VERSION} -eq 11 ] && [ ${SLES_SERVICEPACK} -eq 3 ]
    then
      zypper ar -f "http://ci.normation.com/sles-repo/SLES-11-SP3-DVD-x86_64-GM-DVD1/" "SLES_11_SP3_DVD1" > /dev/null
      zypper ar -f "http://ci.normation.com/sles-repo/SLES-11-SP3-DVD-x86_64-GM-DVD2/" "SLES_11_SP3_DVD2" > /dev/null
    fi

    if [ ${SLES_VERSION} -eq 12 ] && [ ${SLES_SERVICEPACK} -eq 1 ]
    then
      zypper ar -f "http://ci.normation.com/sles-repo/SLES-12-SP1-DVD-x86_64-GM-DVD1/" "SLES_12_SP1_DVD1" > /dev/null
      zypper ar -f "http://ci.normation.com/sles-repo/SLES-12-SP1-DVD-x86_64-GM-DVD2/" "SLES_12_SP1_DVD2" > /dev/null
      # preinstall mod_wsgi
      zypper --non-interactive install apache2 | grep '^.$'
      rpm -iv http://download.opensuse.org/repositories/Apache:/Modules/SLE_12_SP1/x86_64/apache2-mod_wsgi-4.5.2-58.1.x86_64.rpm
    fi

  else
    if [ ${SLES_VERSION} -eq 12 ] && [ ${SLES_SERVICEPACK} -ge 1 ]
    then
      true
    else
      echo "Installing JDK8"
      wget -q -O /tmp/jdk.rpm http://www.normation.com/tarball/java/jdk-8u101-linux-i586.rpm
      rpm -iv /tmp/jdk.rpm | grep '^.$' || true
    fi
  fi

fi


# add common usefull packages
if type apt-get 2> /dev/null
then
  export DEBIAN_FRONTEND=noninteractive
  PM_INSTALL="apt-get -y install"
elif type yum 2> /dev/null
then
  # Fix Centos5 issue installing, which install both architecture, this has no effects on other distros
  echo "multilib_policy=best" >> /etc/yum.conf
  PM_INSTALL="yum -y install"
elif type zypper 2> /dev/null
then
  PM_INSTALL="zypper --non-interactive install"
elif [ -x /opt/csw/bin/pkgutil ] 2> /dev/null
then
  PM_INSTALL="/opt/csw/bin/pkgutil --install --parse --yes"
else
  PM_INSTALL="echo TODO install "
fi
# this can be very long, we should make it optional

# package that should exist everywhere
${PM_INSTALL} zsh vim less curl binutils rsync
${PM_INSTALL} git || ${PM_INSTALL} git-core
# install that may fail
${PM_INSTALL} htop ldapscripts uuid-runtime tree nano

# add common useful files
for user in root vagrant
do
  home=`getent passwd ${user} | cut -d: -f6`
  shopt -s dotglob 2>/dev/null || true
  rsync -a /vagrant/scripts/files/ "${home}"/
done

# Clean vagrant-cachier cached files for rudder packages 
if [ -d "/tmp/vagrant-cache" ]
then
    find /tmp/vagrant-cache -name 'Rudder' -type d | xargs rm -rf
    find /tmp/vagrant-cache -name 'rudder*' -o -name 'ncf*' | xargs rm -f
fi

postclean
exit 0
