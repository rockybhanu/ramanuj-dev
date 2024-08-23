---
title: "Real-Time Data Streaming with Kafka, Debezium, and OpenSearch: A Step-by-Step Guide"
date: 2024-08-23
draft: false
ShowToc: true
---
### Building a Scalable Data Pipeline: From PostgreSQL to OpenSearch with Kafka and Debezium
---
#### Introduction

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

### Conclusion

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

Now that PostgreSQL is set up, it is ready to accept connections from Debezium for change data capture (CDC).

---