# Base Image: Use an Ubuntu-based image
FROM ubuntu:20.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive

# Install necessary dependencies
RUN apt-get update && apt-get install -y \
    openjdk-8-jdk \
    wget \
    ssh \
    rsync \
    r-base \
    r-base-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    git \
    pkg-config \
    python3 \
    python3-pip \
    nano

# Set up Hadoop
WORKDIR /opt
RUN wget -qO- https://downloads.apache.org/hadoop/common/hadoop-3.3.6/hadoop-3.3.6.tar.gz | tar -xz && \
    mv hadoop-3.3.6 hadoop

# Set Hadoop environment variables
ENV HADOOP_HOME=/opt/hadoop
ENV PATH=$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH
ENV JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64

RUN groupadd -r hadoop && useradd -r -m -g hadoop hdfs
# Change ownership of Hadoop directory to hdfs
RUN chown -R hdfs:hadoop /opt/hadoop

# Create .ssh directory for hdfs user and set permissions
RUN mkdir -p /home/hdfs/.ssh && \
    chown -R hdfs:hadoop /home/hdfs/.ssh && \
    chmod 700 /home/hdfs/.ssh

# Install SSH server
RUN apt-get install -y openssh-server && \
    mkdir -p /var/run/sshd && \
    echo 'hdfs:password' | chpasswd && \
    chmod 755 /var/run/sshd

# Allow SSH login for hdfs user
RUN echo 'hdfs ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Create SSH directory and set permissions
RUN [ -d /var/run/sshd ] || mkdir -p /var/run/sshd && \
    echo 'root:password' | chpasswd && \
    chmod 755 /var/run/sshd

RUN ssh-keygen -A

# Configure SSH for Hadoop (Generate SSH keys for hdfs)
USER hdfs
RUN ssh-keygen -t rsa -P '' -f /home/hdfs/.ssh/id_rsa && \
    cat /home/hdfs/.ssh/id_rsa.pub >> /home/hdfs/.ssh/authorized_keys && \
    chmod 600 /home/hdfs/.ssh/authorized_keys

# Switch back to root to modify the system configuration
USER root
RUN echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config

# Install RHadoop dependencies
RUN R -e "install.packages(c('Rcpp', 'digest', 'RJSONIO', 'functional', 'stringr', 'httr', 'plyr', 'devtools'), repos='http://cran.rstudio.com/')"

# Install Hadoop Streaming and rmr2
RUN R -e "install.packages('rhdfs', repos='http://cran.rstudio.com/')"
RUN R -e "install.packages('rmr2', repos='http://cran.rstudio.com/')"

RUN chown -R hdfs:hadoop /opt/hadoop

ENV HDFS_NAMENODE_USER=hdfs
ENV HDFS_DATANODE_USER=hdfs
ENV HDFS_SECONDARYNAMENODE_USER=hdfs

RUN echo "export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64" >> /opt/hadoop/etc/hadoop/hadoop-env.sh

# Also set JAVA_HOME explicitly in other Hadoop config files
RUN echo "export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64" >> /opt/hadoop/etc/hadoop/yarn-env.sh
RUN echo "export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64" >> /opt/hadoop/etc/hadoop/mapred-env.sh

# Make sure the hdfs user can access these files
RUN chown -R hdfs:hadoop /opt/hadoop/etc/hadoop

# Format Hadoop Namenode and start services
RUN echo "export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64" >> /home/hdfs/.bashrc && \
    echo "export HADOOP_HOME=/opt/hadoop" >> /home/hdfs/.bashrc && \
    echo "export PATH=$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH" >> /home/hdfs/.bashrc

# Also add them to profile for non-interactive sessions
RUN echo "export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64" >> /home/hdfs/.profile && \
    echo "export HADOOP_HOME=/opt/hadoop" >> /home/hdfs/.profile && \
    echo "export PATH=$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH" >> /home/hdfs/.profile

RUN chown hdfs:hadoop /home/hdfs/.bashrc /home/hdfs/.profile

# Expose ports for Hadoop Web UI
EXPOSE 9870 8088 22

# Start Hadoop services

RUN mkdir -p /opt/hadoop/logs && \
    chown -R hdfs:hadoop /opt/hadoop/logs

# Add this to your Dockerfile before the CMD instruction

# Configure core-site.xml with proper fs.defaultFS setting
RUN mkdir -p /tmp/hadoop-config && \
    echo '<?xml version="1.0" encoding="UTF-8"?>' > /tmp/hadoop-config/core-site.xml && \
    echo '<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>' >> /tmp/hadoop-config/core-site.xml && \
    echo '<configuration>' >> /tmp/hadoop-config/core-site.xml && \
    echo '  <property>' >> /tmp/hadoop-config/core-site.xml && \
    echo '    <name>fs.defaultFS</name>' >> /tmp/hadoop-config/core-site.xml && \
    echo '    <value>hdfs://localhost:9000</value>' >> /tmp/hadoop-config/core-site.xml && \
    echo '  </property>' >> /tmp/hadoop-config/core-site.xml && \
    echo '  <property>' >> /tmp/hadoop-config/core-site.xml && \
    echo '    <name>hadoop.tmp.dir</name>' >> /tmp/hadoop-config/core-site.xml && \
    echo '    <value>/tmp/hadoop-${user.name}</value>' >> /tmp/hadoop-config/core-site.xml && \
    echo '  </property>' >> /tmp/hadoop-config/core-site.xml && \
    echo '</configuration>' >> /tmp/hadoop-config/core-site.xml && \
    cp /tmp/hadoop-config/core-site.xml /opt/hadoop/etc/hadoop/core-site.xml

# Configure hdfs-site.xml
RUN echo '<?xml version="1.0" encoding="UTF-8"?>' > /tmp/hadoop-config/hdfs-site.xml && \
    echo '<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>' >> /tmp/hadoop-config/hdfs-site.xml && \
    echo '<configuration>' >> /tmp/hadoop-config/hdfs-site.xml && \
    echo '  <property>' >> /tmp/hadoop-config/hdfs-site.xml && \
    echo '    <name>dfs.replication</name>' >> /tmp/hadoop-config/hdfs-site.xml && \
    echo '    <value>1</value>' >> /tmp/hadoop-config/hdfs-site.xml && \
    echo '  </property>' >> /tmp/hadoop-config/hdfs-site.xml && \
    echo '  <property>' >> /tmp/hadoop-config/hdfs-site.xml && \
    echo '    <name>dfs.namenode.name.dir</name>' >> /tmp/hadoop-config/hdfs-site.xml && \
    echo '    <value>/opt/hadoop/data/namenode</value>' >> /tmp/hadoop-config/hdfs-site.xml && \
    echo '  </property>' >> /tmp/hadoop-config/hdfs-site.xml && \
    echo '  <property>' >> /tmp/hadoop-config/hdfs-site.xml && \
    echo '    <name>dfs.datanode.data.dir</name>' >> /tmp/hadoop-config/hdfs-site.xml && \
    echo '    <value>/opt/hadoop/data/datanode</value>' >> /tmp/hadoop-config/hdfs-site.xml && \
    echo '  </property>' >> /tmp/hadoop-config/hdfs-site.xml && \
    echo '</configuration>' >> /tmp/hadoop-config/hdfs-site.xml && \
    cp /tmp/hadoop-config/hdfs-site.xml /opt/hadoop/etc/hadoop/hdfs-site.xml

# Create necessary directories
RUN mkdir -p /opt/hadoop/data/namenode /opt/hadoop/data/datanode && \
    chown -R hdfs:hadoop /opt/hadoop/data && \
    chmod 750 /opt/hadoop/data/namenode /opt/hadoop/data/datanode

# Add format namenode step (will run on first startup if needed)
RUN echo '#!/bin/bash' > /opt/start-hadoop.sh && \
    echo 'export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64' >> /opt/start-hadoop.sh && \
    echo 'if [ ! -d "/opt/hadoop/data/namenode/current" ]; then' >> /opt/start-hadoop.sh && \
    echo '  echo "Formatting namenode for first run..."' >> /opt/start-hadoop.sh && \
    echo '  $HADOOP_HOME/bin/hdfs namenode -format -force' >> /opt/start-hadoop.sh && \
    echo 'fi' >> /opt/start-hadoop.sh && \
    echo '$HADOOP_HOME/sbin/start-dfs.sh' >> /opt/start-hadoop.sh && \
    echo '$HADOOP_HOME/sbin/start-yarn.sh' >> /opt/start-hadoop.sh && \
    echo 'echo "Hadoop services started"' >> /opt/start-hadoop.sh && \
    echo 'tail -f /dev/null' >> /opt/start-hadoop.sh && \
    chmod +x /opt/start-hadoop.sh && \
    chown hdfs:hadoop /opt/start-hadoop.sh

# Update the CMD to use the new startup script
USER root
CMD ["/bin/bash", "-c", "/usr/sbin/sshd && su - hdfs -c '/opt/start-hadoop.sh'"]