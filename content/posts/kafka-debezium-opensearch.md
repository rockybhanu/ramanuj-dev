---
title: "Real-Time Data Streaming with Kafka, Debezium, and OpenSearch: A Step-by-Step Guide"
date: 2024-08-23
draft: false
ShowToc: true
---
### Introduction

In this guide, I'll walk you through setting up a real-time data streaming pipeline using Kafka, Debezium, and OpenSearch. We'll use Kubernetes to manage our deployment, with the Strimzi operator handling Kafka-related components. This step-by-step tutorial will help you create a scalable and efficient data ingestion system for real-time analytics.

---

### Step 1: Setting Up the Strimzi Operator

To begin, we need a Kubernetes cluster where we have administrative access. This access allows us to create namespaces and manage resources efficiently. We'll start by setting up the Strimzi operator, which is essential for managing Apache Kafka clusters within Kubernetes.

#### 1.1 Create a Namespace for Kafka

First, let's create a dedicated namespace for our Kafka resources. This isolation helps in managing and organizing Kubernetes resources effectively.

```bash
kubectl create ns kafka
```

#### 1.2 Install the Strimzi Operator

Next, we'll install the Strimzi operator into the `kafka` namespace. The Strimzi operator simplifies the deployment, management, and scaling of Kafka clusters on Kubernetes. Use the following command to install the latest version of Strimzi:

```bash
kubectl create -f 'https://strimzi.io/install/latest?namespace=kafka' -n kafka
```

This command sets up the necessary Custom Resource Definitions (CRDs) and deploys the operator pod in the `kafka` namespace. The operator will then manage the lifecycle of Kafka clusters based on the custom resources you define.

> **Note:** It's a good practice to use the latest version of the Strimzi operator. While this guide is compatible with the latest updates, staying current ensures you benefit from improvements in Kafka binaries and cluster management capabilities.

---

With the Strimzi operator installed, you're now ready to move on to setting up a Kafka cluster. The operator will help manage the complexity of Kafka deployment, scaling, and maintenance within your Kubernetes environment.

---

### Step 2: Setting Up PostgreSQL on Kubernetes

In this step, we will set up PostgreSQL on Kubernetes. For change data capture (CDC) with Kafka using Debezium, we need PostgreSQL configured with a specific plugin. Although many users deploy PostgreSQL using the official container image, it doesn't come preloaded with the required decoder plugin. We'll use the `decoderbufs` plugin, which uses Protocol Buffers for efficient data encoding.

#### 2.1 Choosing the Right Plugin

There are two popular plugins for CDC with PostgreSQL:

1. **pgoutput**: Comes preloaded with standard PostgreSQL installations (version 10+).
2. **decoderbufs**: Needs to be installed separately and offers efficient data encoding using Protocol Buffers.

In this guide, we will use the `decoderbufs` plugin because it provides better performance by reducing network bandwidth and storage requirements. However, for cloud environments like AWS, you might consider using `pgoutput` due to its native support.

> **Tip:** If you prefer to build your own Docker image based on the latest official PostgreSQL, feel free to do so. Alternatively, you can use the Docker image provided by the Debezium community, which includes the `decoderbufs` plugin pre-installed:
> - Dockerfile: [Debezium PostgreSQL Dockerfile](https://github.com/debezium/container-images/blob/main/postgres/16/Dockerfile)
> - Container Image: [Debezium PostgreSQL Image](https://hub.docker.com/r/debezium/postgres)

#### 2.2 High-Level Steps to Install PostgreSQL

1. Create a PersistentVolumeClaim (PVC) for storing PostgreSQL data.
2. Create a PostgreSQL configuration file and store it in a ConfigMap.
3. Create a Kubernetes Secret for database username and password.
4. Deploy PostgreSQL as a StatefulSet.

Let's dive into each step in detail:

#### 2.3 Create a PersistentVolumeClaim (PVC)

To store PostgreSQL data, create a PVC with the following configuration:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pv-claim
  namespace: postgres
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
  storageClassName: rook-cephfs-retain-fs
```

> **Note:** Adjust the `storageClassName` according to your cluster's storage setup or leave it blank if a default storage class is defined.

#### 2.4 Create PostgreSQL Configuration File

Create a configuration file named `replica-postgres.conf` with the following content:

```conf
# LOGGING
log_min_error_statement = fatal

# CONNECTION
listen_addresses = '*'

# MODULES
shared_preload_libraries = 'decoderbufs'

# REPLICATION
wal_level = logical             # minimal, archive, hot_standby, or logical (change requires restart)
max_wal_senders = 5             # max number of walsender processes (change requires restart)
#wal_keep_segments = 4          # in logfile segments, 16MB each; 0 disables
#wal_sender_timeout = 60s       # in milliseconds; 0 disables
max_replication_slots = 1       # max number of replication slots (change requires restart)
```

This configuration is sourced from the [Debezium PostgreSQL image](https://hub.docker.com/r/debezium/postgres). I've increased `max_wal_senders` to support more concurrent connections, ensuring standby connections are available when needed.

#### 2.5 Create a ConfigMap for PostgreSQL Configuration

Create a ConfigMap using the configuration file created in the previous step:

```bash
kubectl create configmap -n postgres postgres-config --from-file=replica-postgres.conf
```

#### 2.6 Create a Secret for Database Credentials

Create a Kubernetes Secret to store the PostgreSQL database credentials:

```bash
kubectl create secret generic postgres-secret --from-literal PGDATA=/k8s/postgres/pgdata --from-literal POSTGRES_DB=postgres --from-literal POSTGRES_PASSWORD=<ENTER_YOUR_PASSWORD> --from-literal POSTGRES_USER=<ENTER_YOUR_USER_NAME>
```

Replace `<ENTER_YOUR_PASSWORD>` and `<ENTER_YOUR_USER_NAME>` with your desired PostgreSQL username and password.

#### 2.7 Deploy PostgreSQL as a StatefulSet

Deploy PostgreSQL using a StatefulSet with the following configuration:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  serviceName: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - args:
        - -c
        - config_file=/etc/postgresql/postgresql.conf
        envFrom:
        - secretRef:
            name: postgres-secret
        image: debezium/postgres:16
        name: postgres
        ports:
        - containerPort: 5432
          protocol: TCP
        resources:
          requests:
            cpu: "2000m"
            memory: "4Gi"
          limits:
            cpu: "3000m"
            memory: "6Gi"
        volumeMounts:
        - mountPath: /k8s/postgres
          name: postgredb
        - mountPath: /etc/postgresql/postgresql.conf
          subPath: replica-postgres.conf
          name: conf
      dnsPolicy: ClusterFirst
      restartPolicy: Always
      schedulerName: default-scheduler
      securityContext: {}
      terminationGracePeriodSeconds: 30
      volumes:
      - name: postgredb
        persistentVolumeClaim:
          claimName: postgres-pv-claim
      - name: conf
        configMap:
          name: postgres-config
  updateStrategy:
    rollingUpdate:
      partition: 0
    type: RollingUpdate
```

> **Ensure** you have enough memory and CPU resources available as specified in the StatefulSet. Adjust these values if necessary to fit your environment.

---

Now that PostgreSQL is set up, it is ready to accept connections from Debezium for change data capture (CDC).

---

### Step 3: Setting Up OpenSearch and OpenSearch Dashboard on Kubernetes

In this step, we will set up OpenSearch and OpenSearch Dashboard, which will serve as our search and visualization tool for data ingested from PostgreSQL. OpenSearch, an open-source fork of Elasticsearch by AWS, and OpenSearch Dashboard (forked from Kibana) will help us perform real-time search and analytics on our data.

#### 3.1 Create a Namespace for OpenSearch

To organize our Kubernetes resources, we'll create a dedicated namespace for OpenSearch and OpenSearch Dashboard. Run the following command to create the `opensearch` namespace:

```bash
kubectl create ns opensearch
```

#### 3.2 Install OpenSearch Using Helm

Using Helm, the Kubernetes package manager, provides a straightforward way to deploy OpenSearch on our cluster. Helm charts simplify the deployment process by packaging all necessary Kubernetes resources and configurations.

1. **Add the OpenSearch Helm Repository**:

   First, make sure you have access to the OpenSearch Helm charts. You can find more information on how to use Helm with OpenSearch [here](https://opensearch.org/docs/latest/install-and-configure/install-opensearch/helm/).

2. **Configure Persistence**:

   OpenSearch requires persistent storage for indexing and data storage. Update the persistence section in the Helm chart's `values.yaml` file. You can find more configuration options in the [OpenSearch Helm chart repository](https://github.com/opensearch-project/helm-charts/tree/main/charts/opensearch).

   Here's an example configuration snippet for persistence:

   ```yaml
   persistence:
     enabled: true
     size: 100Gi
     storageClass: rook-cephfs-retain-fs
   ```

3. **Install OpenSearch**:

   Use the following command to install OpenSearch using Helm:

   ```bash
   helm install opensearch opensearch --set extraEnvs[0].name=OPENSEARCH_INITIAL_ADMIN_PASSWORD,extraEnvs[0].value=<YOUR_OPENSEARCH_ADMIN_PASSWORD> -n opensearch
   ```

   Replace `<YOUR_OPENSEARCH_ADMIN_PASSWORD>` with your desired admin password. This command will deploy OpenSearch with default settings, and you can customize it by modifying the `values.yaml` file according to your requirements.

#### 3.3 Install OpenSearch Dashboard Using Helm

Now, let's set up the OpenSearch Dashboard to visualize our data. OpenSearch Dashboard is a powerful tool for creating visualizations and monitoring data in real-time.

1. **Configure Ingress for OpenSearch Dashboard**:

   Unlike OpenSearch, the dashboard doesn't need persistent storage. Instead, you'll most likely access it via a web interface, so configuring an ingress resource is essential. Below is an example configuration for `values.yaml` to enable ingress:

   ```yaml
   ingress:
     enabled: true
     ingressClassName: nginx
     annotations:
       cert-manager.io/cluster-issuer: letsencrypt-prod
     hosts:
       - host: opensearch.ramanuj.dev
         paths:
           - path: /
     tls:
       - secretName: opensearch-dashboard-tls
         hosts:
           - opensearch.ramanuj.dev
   ```

   Adjust the hostname and TLS settings according to your environment. This setup allows you to access the dashboard securely over HTTPS.

2. **Install OpenSearch Dashboard**:

   Use the Helm command below to install OpenSearch Dashboard, pointing to the OpenSearch service:

   ```bash
   helm install opensearch-dashboard opensearch-dashboard --set opensearchHosts="https://opensearch-cluster-master:9200" -n opensearch
   ```

   This command installs OpenSearch Dashboard and configures it to connect to the OpenSearch instance running in the same namespace.

#### 3.4 Access OpenSearch Dashboard

Wait a few moments for all the services to start. You can check the status of your pods, PVCs, services, and ingress using the following commands:

```bash
kubectl get pods -n opensearch
kubectl get pvc -n opensearch
kubectl get svc -n opensearch
kubectl get ingress -n opensearch
```

Once everything is up and running, access the OpenSearch Dashboard via the configured URL:

```text
https://opensearch.ramanuj.dev
```

Replace the URL with your actual ingress hostname. If you see the OpenSearch Dashboard login screen, congratulations! You've successfully set up OpenSearch and OpenSearch Dashboard.

---

With OpenSearch and OpenSearch Dashboard set up, you are now equipped to visualize and analyze real-time data streams. Next, we'll configure Debezium and Kafka Connect to capture changes from PostgreSQL and send them to OpenSearch.

---

### Step 4: Setting Up a Kafka Cluster Using Strimzi

With the Strimzi operator installed and the PostgreSQL and OpenSearch components set up, the next step is to configure a Kafka cluster. We will leverage the Custom Resource Definitions (CRDs) provided by Strimzi to create and manage our Kafka cluster. This setup will use a dual-role, single-node configuration, where the node will act both as a controller and a broker.

#### 4.1 Configuring the Kafka Cluster

To set up our Kafka cluster, we will use the `Kafka` and `KafkaNodePool` CRDs installed by the Strimzi operator. We'll create a YAML configuration file named `cluster-setup.yaml` to define these resources. In this example, we will use Kafka version 3.7.1, and the Strimzi operator version is 0.42.0. Your versions might vary based on the latest Strimzi release, but the setup process will remain the same.

#### 4.2 Creating the Kafka and KafkaNodePool Resources

Here's the YAML file (`cluster-setup.yaml`) for setting up the Kafka cluster:

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: dual-role
  namespace: kafka
  labels:
    strimzi.io/cluster: ramanuj-kafka-cluster
spec:
  replicas: 1
  roles:
    - controller
    - broker
  storage:
    type: jbod
    volumes:
      - id: 0
        type: persistent-claim
        size: 100Gi
        deleteClaim: false
        kraftMetadata: shared
  resources:
    requests:
      cpu: "4"
      memory: "8Gi"
    limits:
      cpu: "4"
      memory: "8Gi"
---

apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
namespace: kafka
metadata:
  name: ramanuj-kafka-cluster
  annotations:
    strimzi.io/node-pools: enabled
    strimzi.io/kraft: enabled
spec:
  kafka:
    version: 3.7.1
    metadataVersion: 3.7-IV4
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
      - name: tls
        port: 9093
        type: internal
        tls: true
    config:
      offsets.topic.replication.factor: 1
      transaction.state.log.replication.factor: 1
      transaction.state.log.min.isr: 1
      default.replication.factor: 1
      min.insync.replicas: 1
  entityOperator:
    topicOperator: {}
    userOperator: {}
```

In this configuration:
- The `KafkaNodePool` resource defines a single node (`replicas: 1`) with dual roles (`controller` and `broker`). It uses persistent storage with 100Gi of disk space.
- The `Kafka` resource specifies the Kafka cluster name (`ramanuj-kafka-cluster`), enables Strimzi node pools and Kraft mode, and configures listeners for internal communication.

> **Note:** The above YAML file assumes that the `kafka` namespace has already been created when you installed the Strimzi operator. Adjust the memory and CPU resources as necessary based on your Kubernetes cluster's capacity.

#### 4.3 Applying the Kafka Cluster Configuration

To create the Kafka and KafkaNodePool resources, apply the configuration using the following command:

```bash
kubectl apply -f cluster-setup.yaml
```

This command will create the Kafka cluster and associated components defined in the `cluster-setup.yaml` file.

#### 4.4 Verifying the Kafka Cluster Deployment

Once the configuration is applied, verify that the Kafka cluster and node pool have been set up correctly. You can check the status of the Kafka resources using the following commands:

```bash
kubectl get kafka -n kafka
kubectl get kafkanodepool -n kafka
```

The output should look similar to this:

```plaintext
NAME                    DESIRED KAFKA REPLICAS   DESIRED ZK REPLICAS   READY   METADATA STATE   WARNINGS
ramanuj-kafka-cluster                                                  True    KRaft
```

```plaintext
NAME        DESIRED REPLICAS   ROLES                     NODEIDS
dual-role   1                  ["controller","broker"]   [0]
```

Additionally, you should see the following pods running in the `kafka` namespace:

- `ramanuj-kafka-cluster-dual-role-0`: This is the Kafka broker/controller pod.
- `ramanuj-kafka-cluster-entity-operator-<suffix>`: This pod handles topic and user management.

You can verify the pod status using:

```bash
kubectl get pods -n kafka
```

The output should indicate that the Kafka cluster is up and running, confirming a successful deployment.

---

Now that the Kafka cluster is set up and operational, we can proceed to configure Debezium to capture changes from our PostgreSQL database and route them through Kafka to OpenSearch. Stay tuned for the next steps!

---

### Step 5: Setting Up Kafka Connect with Debezium and OpenSearch Connectors

With our Kafka cluster, PostgreSQL database, and OpenSearch instances ready, it's time to set up Kafka Connect to facilitate the data flow. In this step, we'll configure Kafka Connect to capture change data from PostgreSQL using the Debezium connector and push it to OpenSearch using the OpenSearch sink connector.

#### 5.1 Preparing the Environment

Before proceeding with connector configurations, ensure you have the necessary PostgreSQL credentials set up from previous steps. You can use the same credentials or create new ones specifically for Kafka Connect.

In this guide, we use a table named `customer_records`, which contains 127 columns and approximately 1 million records at the time of writing. The table should have a primary key column named `id` of type `varchar` with UUIDs as unique identifiers. This setup ensures that each record update in OpenSearch is accurately reflected, keeping the data synchronized.

#### 5.2 Setting Up Kafka Connect Cluster

We will deploy a Kafka Connect cluster configured with both the Debezium PostgreSQL source connector and the OpenSearch sink connector. Below is the YAML configuration file (`kafka-connect.yaml`) for setting up the Kafka Connect cluster:

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnect
metadata:
  name: ramanuj-connect-cluster
  namespace: kafka
  annotations:
    strimzi.io/use-connector-resources: "true"  
spec:
  version: 3.7.1
  replicas: 1
  bootstrapServers: ramanuj-kafka-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092
  externalConfiguration:
    volumes:
    - name: postgres-secret
      secret:
        secretName: postgres-source-connector-secret
    - name: opensearch-secret
      secret:
        secretName: opensearch-sink-connector-secret
    - name: opensearch-truststore-secret
      secret:
        secretName: opensearch-truststore-secret
  config:
    config.providers: file
    config.providers.file.class: org.apache.kafka.common.config.provider.FileConfigProvider
    config.storage.topic: connect-cluster-configs
    offset.storage.topic: connect-cluster-offsets
    status.storage.topic: connect-cluster-status
    config.storage.replication.factor: 1
    offset.storage.replication.factor: 1
    status.storage.replication.factor: 1
  resources:
    requests:
      cpu: "2000m"
      memory: "4Gi"
    limits:
      cpu: "3000m"
      memory: "6Gi"
  jvmOptions:
    -Xms: "2G"
    -Xmx: "4G"
  build:
    output:
      type: docker
      image: padminisys/ramanuj-db-opensearch-connector:v1
      pushSecret: docker-padminisys-secret
    plugins:
      - name: debezium-postgres-connector
        artifacts:
          - type: "tgz"
            url: "https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/2.7.1.Final/debezium-connector-postgres-2.7.1.Final-plugin.tar.gz"
      - name: opensearch-sink-connector
        artifacts:
          - type: "zip"
            url: "https://github.com/Aiven-Open/opensearch-connector-for-apache-kafka/releases/download/v3.1.1/opensearch-connector-for-apache-kafka-3.1.1.zip"
  template:
    connectContainer:
      env:
        - name: CONNECT_HEAP_OPTS
          value: "-Xms2G -Xmx4G"
```

In this setup:
- **External Configuration**: Secrets for PostgreSQL and OpenSearch are mounted to manage sensitive information.
- **Plugins**: Debezium PostgreSQL connector and OpenSearch sink connector plugins are defined for Kafka Connect using the `build` feature.
- **Resources**: Dedicated CPU and memory resources are allocated to ensure efficient performance.

#### 5.3 Creating Secrets for OpenSearch

Create secrets required for connecting to OpenSearch:

1. **OpenSearch Credentials**:

   Create a file named `opensearch.properties` with the following content:

   ```plaintext
   user=<ENTER_YOUR_USER_NAME>
   password=<ENTER_YOUR_PASSWORD>
   ```

   Then create the secret:

   ```bash
   kubectl create secret generic opensearch-sink-connector-secret --from-file=opensearch.properties
   ```

2. **Truststore for OpenSearch**:

   Follow these steps to create the truststore:
   - Copy the `esnode.pem` file from the OpenSearch master pod.
   - Convert it to a JKS file using Java tools:

     ```bash
     openssl x509 -outform der -in esnode.pem -out esnode.der
     keytool -importcert -alias opensearch -keystore esnode.jks -file esnode.der
     ```

   - Create the Kubernetes secret:

     ```bash
     kubectl -n kafka create secret generic opensearch-truststore-secret --from-file=esnode.jks
     ```

#### 5.4 Deploying Kafka Connect Cluster

Apply the Kafka Connect configuration:

```bash
kubectl apply -f kafka-connect.yaml
```

Verify the deployment:

```bash
kubectl get kafkaconnect -n kafka
```

The output should indicate that the Kafka Connect cluster is ready.

#### 5.5 Configuring the Debezium PostgreSQL Source Connector

Create a file named `debezium-postgres-connector.yaml` with the following content:

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnector
metadata:
  name: debezium-postgres-connector
  namespace: kafka
  labels:
    strimzi.io/cluster: ramanuj-connect-cluster
spec:
  class: io.debezium.connector.postgresql.PostgresConnector
  tasksMax: 1
  config:
    connector.class: io.debezium.connector.postgresql.PostgresConnector
    database.hostname: postgres.postgres.svc.cluster.local
    database.port: "5432"
    database.user: ${file:/opt/kafka/external-configuration/postgres-secret/postgres.properties:user}
    database.password: ${file:/opt/kafka/external-configuration/postgres-secret/postgres.properties:password}
    database.dbname: crm
    topic.prefix: crm_cdc
    database.server.name: crm
    table.include.list: public.customer_records
    database.history.kafka.bootstrap.servers: ramanuj-kafka-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092
    database.history.kafka.topic: schema-changes.customer_records
    include.schema.changes: "false"
    plugin.name: decoderbufs
    transforms: unwrap,insertKey
    transforms.unwrap.type: io.debezium.transforms.ExtractNewRecordState
    transforms.insertKey.type: org.apache.kafka.connect.transforms.ValueToKey
    transforms.insertKey.fields: id
    key.converter: org.apache.kafka.connect.storage.StringConverter
    value.converter: org.apache.kafka.connect.json.JsonConverter
    value.converter.schemas.enable: true
    value.converter.decimal.format: numeric
```

Apply the configuration:

```bash
kubectl apply -f debezium-postgres-connector.yaml
```

#### 5.6 Configuring the OpenSearch Sink Connector

Create a file named `opensearch-sink-connector.yaml`:

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnector
metadata:
  name: opensearch-sink-connector
  namespace: kafka
  labels:
    strimzi.io/cluster: ramanuj-connect-cluster
spec:
  class: io.aiven.kafka.connect.opensearch.OpensearchSinkConnector
  tasksMax: 1
  config:
    topics: crm_cdc.public.customer_records
    connection.url: https://opensearch-cluster-master.opensearch.svc.cluster.local:9200
    connection.username: ${file:/opt/kafka/external-configuration/opensearch-secret/opensearch.properties:user}
    connection.password: ${file:/opt/kafka/external-configuration/opensearch-secret/opensearch.properties:password}
    ssl.truststore.location: /opt/kafka/external-configuration/opensearch-truststore-secret/esnode.jks
    ssl.truststore.password: ${file:/opt/kafka/external-configuration/opensearch-secret/opensearch.properties:password}
    security.protocol: SSL
    ssl.endpoint.identification.algorithm: ""
    key.ignore: "false"
    schema.ignore: "false"
    connect.timeout.ms: 10000
    read.timeout.ms: 10000
    value.converter: org.apache.kafka.connect.json.JsonConverter
    type.name: crm_cdc.public.customer_records
    key.converter: org.apache.kafka.connect.storage.StringConverter
    errors.retry.timeout: "60000"
    errors.retry.delay.max.ms: "5000"
    errors.log.enable: "true"
    errors.log.include.messages: "true"
    errors.deadletterqueue.topic.name: "crm-cdc-customer-records-dlq"
    errors.dead

letterqueue.context.headers.enable: "true"
```

Apply the configuration:

```bash
kubectl apply -f opensearch-sink-connector.yaml
```

Verify the connectors:

```bash
kubectl get kafkaconnector -n kafka
```

The output should show both the Debezium PostgreSQL connector and the OpenSearch sink connector as ready, indicating successful deployment.

#### 5.7 Testing the Data Flow

With the entire setup in place, test the end-to-end data flow by inserting or updating records in the PostgreSQL database. You should see the changes reflected in OpenSearch in real-time, demonstrating the effectiveness of this data streaming pipeline.

---

Thank you for following along with this guide. By now, you should have a fully functional real-time data ingestion pipeline from PostgreSQL to OpenSearch using Kafka and Debezium. Feel free to explore the data in OpenSearch Dashboard and create insightful visualizations and queries.

---
