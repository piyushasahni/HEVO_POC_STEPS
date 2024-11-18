
# PostgreSQL Data Integration with Hevo and Snowflake

This repository provides a comprehensive guide to setting up a data integration pipeline using a PostgreSQL container on an EC2 instance, connecting it as a source to the Hevo Data Platform, and loading data into Snowflake. The step-by-step instructions include configuring PostgreSQL, preparing data files, integrating with Hevo, and ensuring smooth data transfer into Snowflake.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Step 1: Setting Up PostgreSQL Container on EC2](#step-1-setting-up-postgresql-container-on-ec2)
  - [Installing Docker on EC2](#installing-docker-on-ec2)
  - [Running PostgreSQL Container](#running-postgresql-container)
  - [Configuring PostgreSQL](#configuring-postgresql)
- [Step 2: Connecting PostgreSQL to Hevo Data Platform](#step-2-connecting-postgresql-to-hevo-data-platform)
  - [Granting User Permissions](#granting-user-permissions)
  - [Creating Sample Tables](#creating-sample-tables)
  - [Loading Data into PostgreSQL](#loading-data-into-postgresql)
- [Step 3: Loading Data into Snowflake using Hevo](#step-3-loading-data-into-snowflake-using-hevo)
  - [Setting Up Hevo Pipeline](#setting-up-hevo-pipeline)
  - [Configuring Snowflake as the Destination](#configuring-snowflake-as-the-destination)
  - [Data Transfer and Verification](#data-transfer-and-verification)
- [Step 4: Setting Up dbt with Snowflake](#step-4-setting-up-dbt-with-snowflake)
  - [Installing and Configuring dbt](#installing-and-configuring-dbt)
  - [Creating and Managing Models](#creating-and-managing-models)

---

## Prerequisites

Ensure you have the following prerequisites before proceeding:
- AWS EC2 instance with Ubuntu
- Docker installed on the EC2 instance
- Hevo Data Platform account
- Snowflake account
- Data files to be loaded (in CSV format)

---

## Step 1: Setting Up PostgreSQL Container on EC2

### Installing Docker on EC2

1. Update system packages and install Docker's GPG key:
    ```bash
    sudo apt-get update
    sudo apt-get install ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    ```
2. Add Docker's repository to the APT sources:
    ```bash
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    ```
3. Install Docker:
    ```bash
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    ```

### Running PostgreSQL Container

Run the PostgreSQL container using the following command:
```bash
docker run --name <POSTGRES_CONTAINER_NAME> -e POSTGRES_USER=<POSTGRES_USER> -e POSTGRES_PASSWORD=<POSTGRES_PASSWORD> -e POSTGRES_DB=<POSTGRES_DB> -p 5432:5432 -d postgres
```

### Configuring PostgreSQL

1. Access the PostgreSQL container:
    ```bash
    sudo docker exec -it <POSTGRES_CONTAINER_NAME> /bin/bash
    ```
2. Navigate to the PostgreSQL configuration directory:
    ```bash
    cd /var/lib/postgresql/data/
    ```
3. Edit the `postgresql.conf` file to set `wal_level` to `logical`, configure `wal_sender_timeout`, and specify replication settings:
    ```bash
    nano postgresql.conf
    ```
    Ensure the following lines are present:
    ```
    wal_level = logical
    max_replication_slots = 4
    max_wal_senders = 4
    wal_sender_timeout = 0
    ```
4. Edit the `pg_hba.conf` file to allow connections from Hevo's IP addresses and configure additional replication settings:
    ```bash
    nano pg_hba.conf
    ```
    Add the following lines, replacing `<HEVO_IP_ADDRESS>` with the IP addresses provided by Hevo for your region:
    ```
    local   replication     <POSTGRES_USER>    peer
    host    replication     <POSTGRES_USER>    127.0.0.1/0    md5
    host    replication     <POSTGRES_USER>    ::1/0          md5
    host    replication     <POSTGRES_USER>    <HEVO_IP_ADDRESS>/32    md5
    host    all             <POSTGRES_USER>    <HEVO_IP_ADDRESS>/32    md5
    ```
    *Note: Hevo's IP addresses vary by region. Refer to [Hevo's documentation](https://docs.hevodata.com/sources/dbfs/databases/postgresql/generic-postgresql/) to obtain the correct IP addresses for your region.*
5. Restart the PostgreSQL container to apply changes:
    ```bash
    sudo docker restart <POSTGRES_CONTAINER_NAME>
    ```

---

## Step 2: Connecting PostgreSQL to Hevo Data Platform

### Granting User Permissions

1. Connect to the PostgreSQL database:
    ```bash
    sudo docker exec -it <POSTGRES_CONTAINER_NAME> /bin/bash
    psql -U <POSTGRES_USER> -d <POSTGRES_DB>
    ```
2. Execute the following SQL commands to grant necessary permissions and replication access:
    ```sql
    CREATE SCHEMA <POSTGRES_SCHEMA>;
    GRANT CONNECT ON DATABASE <POSTGRES_DB> TO <POSTGRES_USER>;
    GRANT USAGE ON SCHEMA <POSTGRES_SCHEMA> TO <POSTGRES_USER>;
    GRANT SELECT ON ALL TABLES IN SCHEMA <POSTGRES_SCHEMA> TO <POSTGRES_USER>;
    ALTER DEFAULT PRIVILEGES IN SCHEMA <POSTGRES_SCHEMA> GRANT SELECT ON TABLES TO <POSTGRES_USER>;
    ALTER USER <POSTGRES_USER> WITH REPLICATION;
    ```

### Creating Sample Tables

Create sample tables to be used for data loading:
```sql
CREATE TABLE <POSTGRES_SCHEMA>.raw_customers (
    id SERIAL PRIMARY KEY,
    first_name TEXT,
    last_name TEXT
);

CREATE TABLE <POSTGRES_SCHEMA>.raw_orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES hevo_schema.raw_customers(id),
    order_date DATE,
    status TEXT
);

CREATE TABLE <POSTGRES_SCHEMA>.raw_payments (
    id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES hevo_schema.raw_orders(id),
    payment_method TEXT,
    amount INTEGER
);
```

### Loading Data into PostgreSQL

1. Copy CSV files into the container:
    ```bash
    sudo docker cp raw_customers.csv <POSTGRES_CONTAINER_NAME>:/root/raw_customers.csv
    sudo docker cp raw_orders.csv <POSTGRES_CONTAINER_NAME>:/root/raw_orders.csv
    sudo docker cp raw_payments.csv <POSTGRES_CONTAINER_NAME>:/root/raw_payments.csv
    ```
2. Load data into the tables:
    ```sql
    \COPY <POSTGRES_SCHEMA>.raw_customers (id, first_name, last_name)
    FROM '/root/raw_customers.csv'
    DELIMITER ','
    CSV HEADER;

    \COPY <POSTGRES_SCHEMA>.raw_orders (id, user_id, order_date, status)
    FROM '/root/raw_orders.csv'
    DELIMITER ','
    CSV HEADER;

    \COPY <POSTGRES_SCHEMA>.raw_payments (id, order_id, payment_method, amount)
    FROM '/root/raw_payments.csv'
    DELIMITER ','
    CSV HEADER;
    ```

---

## Step 3: Loading Data into Snowflake using Hevo

### Setting Up Hevo Pipeline

1. Log in to your Hevo Data Platform account.
2. Create a new pipeline and configure PostgreSQL as the source using the connection details:
   - Host: Your EC2 instance's public IP
   - Port: 5432
   - Database: `<POSTGRES_DB>`
   - Username: `<POSTGRES_USER>`
   - Password: `<POSTGRES_PASSWORD>`

### Configuring Snowflake as the Destination

1. In Hevo, select Snowflake as the destination and provide the following configuration details:
   - **Snowflake URL**: `<YOUR_SNOWFLAKE_URL>`
   - **Database**: `<YOUR_SNOWFLAKE_DATABASE>`
   - **Warehouse**: `<YOUR_SNOWFLAKE_WAREHOUSE>`
   - **Schema**: `<YOUR_SNOWFLAKE_SCHEMA>`
   - **Username**: `<YOUR_SNOWFLAKE_USERNAME>`
   - **Password**: `<YOUR_SNOWFLAKE_PASSWORD>`
2. Set the data ingestion frequency according to your requirements.

### Data Transfer and Verification

1. Map the source tables from PostgreSQL to target tables in Snowflake (OR) Use Automapping capability of Hevo data platform.
2. Verify that the data is transferred correctly by querying the Snowflake tables.


## Step 4: Setting Up dbt with Snowflake

This guide provides instructions to set up and configure dbt (Data Build Tool) with Snowflake for data modeling and management.

## Installing and Configuring dbt

1. Update and install necessary packages:
    ```bash
    sudo apt-get update
    sudo apt-get install -y python3-pip python3-venv git
    ```
2. Create and activate a virtual environment for dbt:
    ```bash
    python3 -m venv dbt-env
    source dbt-env/bin/activate
    ```
3. Install dbt for Snowflake:
    ```bash
    pip install dbt-snowflake
    ```
4. Clone the repository for the dbt project:
    ```bash
    git clone <GITHUB REPO URL>
    cd <GITHUB REPO NAME>
    ```
5. Initialize a dbt project:
    ```bash
    dbt init <PROJECT NAME>
    ```
    When prompted:
    - Account: Enter your Snowflake account (e.g., `<VALUE>.us-east-1`)
    - Role (dev role): `<ROLE>`
    - Threads: Enter `1`

6. Edit the `dbt_project.yml` file to connect dbt to Snowflake:
    ```bash
    touch dbt_project.yml
    nano dbt_project.yml
    ```
    Example configuration:
    ```yaml
    name: '<PROJECT NAME>'
    version: '1.0.0'
    profile: '<PROJECT NAME>'
    target-path: "target"  # directory which will store compiled SQL files
    clean-targets:
      - "target"
      - "dbt_modules"

    models:
      <PROJECT NAME>:
        +materialized: view  # or 'table' if you want to create tables
    ```

7. Test the dbt setup:
    ```bash
    dbt debug
    ```

## Creating and Managing Models

1. Create a new model file:
    ```bash
    touch customer_aggregation.sql
    nano customer_aggregation.sql
    ```
2. Add SQL logic to the model file:
    ```sql
    WITH customer_orders AS (
    SELECT
        c.id AS customer_id,
        c.first_name,
        c.last_name,
        MIN(o.order_date) AS first_order,
        MAX(o.order_date) AS most_recent_order,
        COUNT(o.id) AS number_of_orders
    FROM {{ source('<SCHEMA>', 'raw_customers') }} c
    LEFT JOIN {{ source('<SCHEMA>', 'raw_orders') }} o
    ON c.id = o.user_id
    GROUP BY c.id, c.first_name, c.last_name
    ),
    customer_lifetime_value AS (
        SELECT
            o.user_id AS customer_id,
            SUM(p.amount) AS customer_lifetime_value
        FROM {{ source('<SCHEMA>', 'raw_orders') }} o
        LEFT JOIN {{ source('<SCHEMA>', 'raw_payments') }} p
        ON o.id = p.order_id
        GROUP BY o.user_id
    )
    SELECT
        co.customer_id,
        co.first_name,
        co.last_name,
        co.first_order,
        co.most_recent_order,
        co.number_of_orders,
        clv.customer_lifetime_value
    FROM customer_orders co
    LEFT JOIN customer_lifetime_value clv
    ON co.customer_id = clv.customer_id;
    ```

3. Run dbt models:
    ```bash
    cd ~/<GITHUB REPO NAME>
    dbt run
    ```

4. Organize models and schema:
    ```bash
    mkdir models
    mv customer_aggregation.sql models/
    touch models/schema.yml
    nano models/schema.yml
    ```
5. Example `schema.yml` configuration:
    ```yaml
    version: 2

    sources:
      - name: <PROJECT NAME>
        database: <DB NAME>  # Your Snowflake database name
        schema: <SCHEMA>  # Your Snowflake schema name
        tables:
          - name: raw_customers
          - name: raw_orders
          - name: raw_payments
    ```

6. Run dbt models with schema:
    ```bash
    dbt run
    ```
