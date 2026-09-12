# 1. Start from the prebuilt Node/Claude base image
FROM gendosu/claude-code-docker:latest

# 2. Switch to root to perform privileged system installation
USER root

# 3. Update apt packages and install OpenSSH cleanly
RUN apt-get update && apt-get install -y --no-install-recommends \
        sudo \
        iproute2 \
        nano \
        git \
        iputils-ping \
        net-tools \
        curl \
        dnsutils \
        vim \
        openssh-server \
        openssh-client \
    && rm -rf /var/lib/apt/lists/*

# 4. Create the standard runtime directory required by sshd
RUN mkdir /var/run/sshd

# 5. Set up SSH Configuration (Change "yoursecurepassword" to a real secret)
RUN echo 'node:yoursecurepassword' | chpasswd \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Copy your local scripts into the container's system binary path
COPY scripts/create_ubuntu_users.sh /usr/local/bin/create_ubuntu_users.sh
COPY scripts/cleanup_ubuntu_users.sh /usr/local/bin/cleanup_ubuntu_users.sh
COPY scripts/custom_bashrc.tmpl ./custom_bashrc.tmpl

# Ensure the scripts are executable
RUN sed -i 's/\r$//' /usr/local/bin/create_ubuntu_users.sh
RUN sed -i 's/\r$//' /usr/local/bin/cleanup_ubuntu_users.sh
RUN sed -i 's/\r$//' ./custom_bashrc.tmpl
RUN chmod +x /usr/local/bin/create_ubuntu_users.sh /usr/local/bin/cleanup_ubuntu_users.sh

# 6. Expose the standard SSH port inside the container
EXPOSE 22

ENTRYPOINT []

# 7. Start the SSH server when the container starts
CMD ["/usr/sbin/sshd", "-D"]
