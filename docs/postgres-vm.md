# Setting up Postgres on a VM

1. Update Package List and Install PostgreSQL

```bash
sudo apt update -y
sudo apt install postgresql postgresql-contrib -y
```

2. Start and Enable PostgreSQL Service

```bash
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

When you install PostgreSQL a default admin user “postgres” is created by the default. You must use it to log-in to your PostgreSQL database for the first time.

A `psql` command-line client tool is used to interact with the database engine. You should invoke it as a “postgres” user to start an interactive session with your local database.

```bash
sudo -u postgres psql
```

In addition to creating a postgres admin user for you, PostgreSQL installation also creates a default database named “postgres” and connects you to it automatically when you first launch psql.

Since the default “postgres” user does not have a password, you should set it yourself.

```bash
\password postgres
```

### Setup PostgreSQL server

It’s fun to play with the database locally, but eventually you will need to connect to it through a remote server.

When you install a PostgreSQL server, it is only accessible locally through the loopback IP address of your machine. However, you may change this setting in the PostgreSQL configuration file to allow remote access.

Let’s now exit the interactive psql session by typing exit, and access postgresql.conf configuration file of PostgreSQL version 14 by using vim text editor.

```bash
sudo vim /etc/postgresql/16/main/postgresql.conf
```

Uncomment and edit the listen_addresses attribute to start listening to start listening to all available IP addresses.

```bash
listen_addresses = '*'
```

Now edit the PostgreSQL access policy configuration file.

```bash
sudo vim /etc/postgresql/16/main/pg_hba.conf
```

Append a new connection policy (a pattern stands for `[CONNECTION_TYPE][DATABASE][USER] [ADDRESS][METHOD]`) in the bottom of the file.

```bash
host all all 0.0.0.0/0 md5
```

It is now time to restart your PostgreSQL service to load your configuration changes.

```bash
systemctl restart postgresql
```

And make sure your system is listening to the 5432 port that is reserved for PostgreSQL.

```bash
ss -nlt | grep 5432
```

Now connect to the database via a IDE.
