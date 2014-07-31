pgpool-II-installer
===================

Version
-------

1.0 beta1

Overview
--------

This is the package of scripts to create [pgpool-II](http://www.pgpool.net)'s installer.  
[NOTICE] You should get RPM packages of pgpool-II and pgpoolAdmin by yourself.

### What the installer for pgpool can do:
* Install pgpool-II and pgpoolAdmin into both of servers for pgpool-II and backend nodes for PostgreSQL by RPM.
* Generate config files for pgpool-II, pgpoolAdmin and PostgreSQL.
 * master-slave mode with streaming replication / pgpool's native replication
 * watchdog
 * load balance
 * health check
 * on memory query cache
 * etc...
* Generate the scripts for fail over and online recovery.
* Setup SSH connections without inputting passwords.


How to make the installer
--------------------------

### 1. Get RPM packages of pgpool-II and pgpoolAdmin.

    $ git clone https://github.com/sraoss/pgpool-II-installer
    $ cd pgpool-II-installer
    $ wget http://www.pgpool.net/download.php?f=pgpool-II-pg{pg_version}-{version}.pgdg.x86_64.rpm
    $ wget http://www.pgpool.net/download.php?f=pgpoolAdmin-{version}.pgdg.noarch.rpm

These RPM packages can be downloaded from [here](http://pgpool.net/mediawiki/index.php/Downloads).

### 2. Edit the config file for installer.

Edit lib/param.sh.

    $ edit lib/param.sh

#### Parameters

| parameter's name | example |  category   | description                     |
|------------------|---------|-------------|---------------------------------|
| PG_MAJOR_VERSION | 9.3     | PostgreSQL  | major version                   |
| MAJOR_VERSION    | 3.3     | pgpool-II   | major version                   |
| P_VERSION        | 3.3.3   | pgpool-II   | full version                    |
| P_RELEASE        | 1       | pgpool-II   | release number of RPM package   |
| A_VERSION        | 3.3.1   | pgpoolAdmin | full version                    |
| A_RELEASE        | 1       | pgpoolAdmin | release number of package       |

How to use the installer
------------------------

    $ su -

    # whoami
    root
    # cd /path/to/installer
    # ./install.sh

After answering some questions, installation and setup will start.

### (Advanced)

If you create the config file called "installer.conf" before you execute install.sh, install.sh uses the parameters in the file as the default value of questions by the script.

    $ cp installer.conf.sample installer.conf
    $ edit installer.conf

    # whoami
    root
    # cd /path/to/installer
    # ./install.sh

#### Parameters

| parameter's name           | example                   | category    | description                                              |
|----------------------------|---------------------------|-------------|----------------------------------------------------------|
| DEF_PGPOOL_WATCHDOG        | yes                       | pgpool-II   | use watchdog                                             |
| DEF_PGPOOL_HOST_ARR[0]     | pool-alice                | pgpool-II   | hostname of 1st pgpool server                            |
| DEF_PGPOOL_HOST_ARR[1]     | pool-bob                  | pgpool-II   | hostname of 2nd pgpool server (only when using watchdog) |
| DEF_REPLICATION_MODE       | stream                    | pgpool-II   | pgpool's replication mode                                |
| DEF_PGPOOL_WATCHDOG        | yes                       | pgpool-II   | use watchdog or not                                      |
| DEF_delegate_IP            | '192.168.1.123'           | pgpool-II   | virtual IP address (only when using watchdog)            |
| DEF_BACKEND_HOST_ARR[n]    | db-alice                  | PostgreSQL  | hostname of nth PostgrteSQL server                       |
| DEF_BACKEND_PORT_ARR[n]    | 5432                      | PostgreSQL  | port number of nth PostgreSQL server                     |
| DEF_PGDATA_ARR[n]          | /var/lib/pgsql/alice-data | PostgreSQL  | data directory of nth PostgreSQL server                  |
| DEF_ARCHIVE_DIR_ARR[n]     | /var/lib/pgsql/alice-arc  | PostgreSQL  | archive directory of nth PostgreSQL server               |
| NETMASK                    | 255.255.255.0             | PostgreSQL  | netmask                                                  |
| DEF_PG_ADMIN_USER          | admin                     | pgpoolAdmin | user for pgpoolAdmin                                     |
| DEF_PG_ADMIN_USER_PASSWORD | pgpool                    | pgpoolAdmin | password for pgpoolAdmin's user                          |
