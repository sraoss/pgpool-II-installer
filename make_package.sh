#!/bin/sh

# ---------------------------------------------------------------------
# configuration
# ---------------------------------------------------------------------

CENTOS_VERSION=6
ARCHITECTURE=x86_64

MAJOR_VERSION=3.4
P_VERSION=3.4.1
P_RELEASE=2
P_RPM_VERSION=${P_VERSION}-${P_RELEASE}

A_VERSION=3.4.1
A_RELEASE=2
A_RPM_VERSION=${A_VERSION}-${A_RELEASE}

PG_MAJOR_VERSION=9.4
PG_MAJOR_VERSION_WO_DOT=${PG_MAJOR_VERSION/./}

# ---------------------------------------------------------------------
# prepare
# ---------------------------------------------------------------------

rm -rf editted/*

# ---------------------------------------------------------------------
# download RPMs
# ---------------------------------------------------------------------

echo
echo "- download RPM"
echo

BASE_URL=http://www.pgpool.net/yum/rpms/${MAJOR_VERSION}/redhat/rhel-${CENTOS_VERSION}-${ARCHITECTURE}/
PGPOOL_PG=pgpool-II-pg${PG_MAJOR_VERSION_WO_DOT}

rm -f *.rpm
wget ${BASE_URL}/${PGPOOL_PG}-${P_RPM_VERSION}pgdg.rhel${CENTOS_VERSION}.${ARCHITECTURE}.rpm
wget ${BASE_URL}/${PGPOOL_PG}-extensions-${P_RPM_VERSION}pgdg.rhel${CENTOS_VERSION}.${ARCHITECTURE}.rpm
wget ${BASE_URL}/pgpoolAdmin-${A_RPM_VERSION}pgdg.rhel${CENTOS_VERSION}.noarch.rpm

echo
ls *.rpm

# ---------------------------------------------------------------------
# get sources for pgpool for installer
# ---------------------------------------------------------------------

echo
echo "- create lib/versions.sh "
echo

# scripts
cat > lib/version.sh <<EOT
#!/bin/sh

# CentOS
CENTOS_VERSION=${CENTOS_VERSION}

# PostgreSQL
PG_MAJOR_VERSION=${PG_MAJOR_VERSION}

# pgpool-II
MAJOR_VERSION=${MAJOR_VERSION}
P_VERSION=${P_VERSION}
P_RELEASE=${P_RELEASE}

# pgpoolAdmin
A_VERSION=${A_VERSION}
A_RELEASE=${A_RELEASE}
EOT

cat lib/version.sh
