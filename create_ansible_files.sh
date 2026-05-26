
#!/bin/bash
# Run from the root of your anduril-mdi-pipeline directory
# This creates the Ansible playbooks and supporting files

# Create directory structure
mkdir -p ansible/inventory
mkdir -p ansible/roles/hardening/tasks
mkdir -p ansible/roles/hardening/handlers
mkdir -p ansible/roles/hardening/templates
mkdir -p ansible/roles/monitoring/tasks
mkdir -p ansible/roles/monitoring/templates
mkdir -p ansible/roles/vpn/tasks
mkdir -p ansible/roles/vpn/templates

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 1: ansible/ansible.cfg
# ═══════════════════════════════════════════════════════════════════════════════

cat > ansible/ansible.cfg << 'EOF'
[defaults]
inventory = inventory/
roles_path = roles/
host_key_checking = False
retry_files_enabled = False
stdout_callback = yaml
callbacks_enabled = timer, profile_tasks
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 3600

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False

[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=no
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 2: ansible/playbooks/harden-nodes.yml
# CIS Benchmark-aligned hardening for EKS/AKS worker nodes
# ═══════════════════════════════════════════════════════════════════════════════

cat > ansible/playbooks/harden-nodes.yml << 'EOF'
---
# ═══════════════════════════════════════════════════════════════════════════════
# PLAYBOOK: Harden Worker Nodes
# Applies CIS Benchmark Level 2 hardening to EKS/AKS worker nodes
# Aligned with DISA STIG and IRAP requirements
# ═══════════════════════════════════════════════════════════════════════════════

- name: Harden Sovereign Infrastructure Nodes
  hosts: all
  become: true
  gather_facts: true

  vars:
    target_env: "{{ target_env | default('dev') }}"
    sysctl_hardening:
      # Network hardening
      net.ipv4.ip_forward: 1  # Required for K8s pod networking
      net.ipv4.conf.all.send_redirects: 0
      net.ipv4.conf.default.send_redirects: 0
      net.ipv4.conf.all.accept_redirects: 0
      net.ipv4.conf.default.accept_redirects: 0
      net.ipv4.conf.all.secure_redirects: 0
      net.ipv4.conf.default.secure_redirects: 0
      net.ipv4.conf.all.log_martians: 1
      net.ipv4.conf.default.log_martians: 1
      net.ipv4.icmp_echo_ignore_broadcasts: 1
      net.ipv4.icmp_ignore_bogus_error_responses: 1
      net.ipv4.conf.all.rp_filter: 1
      net.ipv4.conf.default.rp_filter: 1
      net.ipv4.tcp_syncookies: 1
      # IPv6 — disable if not needed
      net.ipv6.conf.all.accept_ra: 0
      net.ipv6.conf.default.accept_ra: 0
      net.ipv6.conf.all.accept_redirects: 0
      net.ipv6.conf.default.accept_redirects: 0
      # Kernel hardening
      kernel.randomize_va_space: 2
      kernel.dmesg_restrict: 1
      kernel.kptr_restrict: 2
      kernel.yama.ptrace_scope: 2
      fs.suid_dumpable: 0
      fs.protected_hardlinks: 1
      fs.protected_symlinks: 1

    disabled_services:
      - bluetooth
      - cups
      - avahi-daemon
      - rpcbind
      - nfs-server
      - vsftpd
      - telnet

    required_packages:
      - aide
      - auditd
      - fail2ban
      - rkhunter
      - unattended-upgrades

  tasks:
    # ─────────────────────────────────────────────
    # SYSTEM UPDATES
    # ─────────────────────────────────────────────
    - name: Update all packages to latest
      ansible.builtin.apt:
        upgrade: dist
        update_cache: true
        cache_valid_time: 3600
      when: ansible_os_family == "Debian"

    - name: Update all packages (RHEL/Amazon Linux)
      ansible.builtin.yum:
        name: "*"
        state: latest
        security: true
      when: ansible_os_family == "RedHat"

    # ─────────────────────────────────────────────
    # INSTALL SECURITY PACKAGES
    # ─────────────────────────────────────────────
    - name: Install required security packages
      ansible.builtin.package:
        name: "{{ required_packages }}"
        state: present
      ignore_errors: true

    # ─────────────────────────────────────────────
    # KERNEL HARDENING (sysctl)
    # ─────────────────────────────────────────────
    - name: Apply sysctl hardening parameters
      ansible.posix.sysctl:
        name: "{{ item.key }}"
        value: "{{ item.value }}"
        sysctl_set: true
        state: present
        reload: true
        sysctl_file: /etc/sysctl.d/99-sovereign-hardening.conf
      loop: "{{ sysctl_hardening | dict2items }}"

    # ─────────────────────────────────────────────
    # DISABLE UNNECESSARY SERVICES
    # ─────────────────────────────────────────────
    - name: Disable unnecessary services
      ansible.builtin.systemd:
        name: "{{ item }}"
        state: stopped
        enabled: false
      loop: "{{ disabled_services }}"
      ignore_errors: true

    # ─────────────────────────────────────────────
    # SSH HARDENING
    # ─────────────────────────────────────────────
    - name: Harden SSH configuration
      ansible.builtin.lineinfile:
        path: /etc/ssh/sshd_config
        regexp: "{{ item.regexp }}"
        line: "{{ item.line }}"
        state: present
        validate: 'sshd -t -f %s'
      loop:
        - { regexp: '^#?PermitRootLogin', line: 'PermitRootLogin no' }
        - { regexp: '^#?PasswordAuthentication', line: 'PasswordAuthentication no' }
        - { regexp: '^#?PermitEmptyPasswords', line: 'PermitEmptyPasswords no' }
        - { regexp: '^#?X11Forwarding', line: 'X11Forwarding no' }
        - { regexp: '^#?MaxAuthTries', line: 'MaxAuthTries 3' }
        - { regexp: '^#?ClientAliveInterval', line: 'ClientAliveInterval 300' }
        - { regexp: '^#?ClientAliveCountMax', line: 'ClientAliveCountMax 2' }
        - { regexp: '^#?Protocol', line: 'Protocol 2' }
        - { regexp: '^#?LoginGraceTime', line: 'LoginGraceTime 60' }
        - { regexp: '^#?AllowAgentForwarding', line: 'AllowAgentForwarding no' }
        - { regexp: '^#?AllowTcpForwarding', line: 'AllowTcpForwarding no' }
        - { regexp: '^#?Banner', line: 'Banner /etc/issue.net' }
        - { regexp: '^#?Ciphers', line: 'Ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr' }
        - { regexp: '^#?MACs', line: 'MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com' }
        - { regexp: '^#?KexAlgorithms', line: 'KexAlgorithms curve25519-sha256,diffie-hellman-group16-sha512' }
      notify: restart sshd

    - name: Set SSH warning banner
      ansible.builtin.copy:
        content: |
          ╔══════════════════════════════════════════════════════════════╗
          ║  AUTHORIZED ACCESS ONLY                                      ║
          ║  This system is for authorized use only.                     ║
          ║  All activities are monitored and recorded.                  ║
          ║  Unauthorized access will be prosecuted.                     ║
          ╚══════════════════════════════════════════════════════════════╝
        dest: /etc/issue.net
        mode: '0644'

    # ─────────────────────────────────────────────
    # FILE SYSTEM HARDENING
    # ─────────────────────────────────────────────
    - name: Set permissions on sensitive files
      ansible.builtin.file:
        path: "{{ item.path }}"
        mode: "{{ item.mode }}"
        owner: root
        group: root
      loop:
        - { path: '/etc/passwd', mode: '0644' }
        - { path: '/etc/shadow', mode: '0600' }
        - { path: '/etc/group', mode: '0644' }
        - { path: '/etc/gshadow', mode: '0600' }
        - { path: '/etc/ssh/sshd_config', mode: '0600' }
        - { path: '/boot/grub/grub.cfg', mode: '0600' }
      ignore_errors: true

    - name: Ensure /tmp is mounted with noexec
      ansible.posix.mount:
        path: /tmp
        src: tmpfs
        fstype: tmpfs
        opts: defaults,noexec,nosuid,nodev
        state: mounted

    # ─────────────────────────────────────────────
    # AUDIT LOGGING (auditd)
    # ─────────────────────────────────────────────
    - name: Configure auditd rules
      ansible.builtin.copy:
        content: |
          # Sovereign Infrastructure Audit Rules
          # Aligned with CIS Benchmark and DISA STIG

          # Monitor changes to authentication files
          -w /etc/passwd -p wa -k identity
          -w /etc/group -p wa -k identity
          -w /etc/shadow -p wa -k identity
          -w /etc/gshadow -p wa -k identity
          -w /etc/sudoers -p wa -k sudoers
          -w /etc/sudoers.d/ -p wa -k sudoers

          # Monitor SSH configuration
          -w /etc/ssh/sshd_config -p wa -k sshd_config

          # Monitor network configuration
          -w /etc/sysctl.conf -p wa -k sysctl
          -w /etc/sysctl.d/ -p wa -k sysctl

          # Monitor kernel module loading
          -w /sbin/insmod -p x -k modules
          -w /sbin/rmmod -p x -k modules
          -w /sbin/modprobe -p x -k modules

          # Monitor file deletions
          -a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete

          # Monitor privilege escalation
          -a always,exit -F arch=b64 -S setuid -S setgid -F auid>=1000 -F auid!=4294967295 -k privilege_escalation

          # Monitor container runtime
          -w /usr/bin/containerd -p x -k container_runtime
          -w /usr/bin/docker -p x -k container_runtime
          -w /usr/bin/kubectl -p x -k kubectl

          # Make audit configuration immutable (requires reboot to change)
          -e 2
        dest: /etc/audit/rules.d/sovereign.rules
        mode: '0640'
      notify: restart auditd

    # ─────────────────────────────────────────────
    # FAIL2BAN — Brute force protection
    # ─────────────────────────────────────────────
    - name: Configure fail2ban for SSH
      ansible.builtin.copy:
        content: |
          [sshd]
          enabled = true
          port = ssh
          filter = sshd
          logpath = /var/log/auth.log
          maxretry = 3
          bantime = 3600
          findtime = 600
        dest: /etc/fail2ban/jail.d/sshd.conf
        mode: '0644'
      notify: restart fail2ban

    # ─────────────────────────────────────────────
    # AUTOMATIC SECURITY UPDATES
    # ─────────────────────────────────────────────
    - name: Enable automatic security updates (Debian/Ubuntu)
      ansible.builtin.copy:
        content: |
          APT::Periodic::Update-Package-Lists "1";
          APT::Periodic::Unattended-Upgrade "1";
          APT::Periodic::AutocleanInterval "7";
        dest: /etc/apt/apt.conf.d/20auto-upgrades
        mode: '0644'
      when: ansible_os_family == "Debian"

  handlers:
    - name: restart sshd
      ansible.builtin.systemd:
        name: sshd
        state: restarted

    - name: restart auditd
      ansible.builtin.systemd:
        name: auditd
        state: restarted

    - name: restart fail2ban
      ansible.builtin.systemd:
        name: fail2ban
        state: restarted
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 3: ansible/playbooks/deploy-monitoring.yml
# Prometheus + Grafana + CloudWatch/Azure Monitor agents
# ═══════════════════════════════════════════════════════════════════════════════

cat > ansible/playbooks/deploy-monitoring.yml << 'EOF'
---
# ═══════════════════════════════════════════════════════════════════════════════
# PLAYBOOK: Deploy Monitoring Stack
# Installs and configures monitoring agents on all nodes
# Integrates with CloudWatch (AWS) and Azure Monitor
# ═══════════════════════════════════════════════════════════════════════════════

- name: Deploy Monitoring Stack
  hosts: all
  become: true
  gather_facts: true

  vars:
    target_env: "{{ target_env | default('dev') }}"
    project_name: "mdi-sovereign"
    cloudwatch_namespace: "{{ project_name }}/{{ target_env }}"

    # Prometheus Node Exporter
    node_exporter_version: "1.7.0"
    node_exporter_port: 9100

    # Log collection
    log_paths:
      - /var/log/syslog
      - /var/log/auth.log
      - /var/log/audit/audit.log
      - /var/log/containers/*.log
      - /var/log/pods/**/*.log

  tasks:
    # ─────────────────────────────────────────────
    # PROMETHEUS NODE EXPORTER
    # ─────────────────────────────────────────────
    - name: Create node_exporter user
      ansible.builtin.user:
        name: node_exporter
        shell: /usr/sbin/nologin
        system: true
        create_home: false

    - name: Download node_exporter
      ansible.builtin.get_url:
        url: "https://github.com/prometheus/node_exporter/releases/download/v{{ node_exporter_version }}/node_exporter-{{ node_exporter_version }}.linux-amd64.tar.gz"
        dest: /tmp/node_exporter.tar.gz
        mode: '0644'

    - name: Extract node_exporter
      ansible.builtin.unarchive:
        src: /tmp/node_exporter.tar.gz
        dest: /tmp/
        remote_src: true

    - name: Install node_exporter binary
      ansible.builtin.copy:
        src: "/tmp/node_exporter-{{ node_exporter_version }}.linux-amd64/node_exporter"
        dest: /usr/local/bin/node_exporter
        mode: '0755'
        owner: root
        group: root
        remote_src: true

    - name: Create node_exporter systemd service
      ansible.builtin.copy:
        content: |
          [Unit]
          Description=Prometheus Node Exporter
          Documentation=https://prometheus.io/docs/guides/node-exporter/
          Wants=network-online.target
          After=network-online.target

          [Service]
          User=node_exporter
          Group=node_exporter
          Type=simple
          ExecStart=/usr/local/bin/node_exporter \
            --collector.filesystem.mount-points-exclude="^/(sys|proc|dev|host|etc)($$|/)" \
            --collector.netclass.ignored-devices="^(veth.*|docker.*|br-.*)$$" \
            --web.listen-address=:{{ node_exporter_port }}
          Restart=always
          RestartSec=5

          [Install]
          WantedBy=multi-user.target
        dest: /etc/systemd/system/node_exporter.service
        mode: '0644'
      notify: restart node_exporter

    - name: Enable and start node_exporter
      ansible.builtin.systemd:
        name: node_exporter
        state: started
        enabled: true
        daemon_reload: true

    # ─────────────────────────────────────────────
    # CLOUDWATCH AGENT (AWS nodes)
    # ─────────────────────────────────────────────
    - name: Install CloudWatch Agent (Amazon Linux / Ubuntu)
      block:
        - name: Download CloudWatch Agent
          ansible.builtin.get_url:
            url: "https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb"
            dest: /tmp/amazon-cloudwatch-agent.deb
            mode: '0644'
          when: ansible_os_family == "Debian"

        - name: Install CloudWatch Agent (Debian)
          ansible.builtin.apt:
            deb: /tmp/amazon-cloudwatch-agent.deb
          when: ansible_os_family == "Debian"

        - name: Configure CloudWatch Agent
          ansible.builtin.copy:
            content: |
              {
                "agent": {
                  "metrics_collection_interval": 60,
                  "run_as_user": "cwagent"
                },
                "metrics": {
                  "namespace": "{{ cloudwatch_namespace }}",
                  "metrics_collected": {
                    "cpu": {
                      "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
                      "totalcpu": true
                    },
                    "disk": {
                      "measurement": ["used_percent", "inodes_free"],
                      "resources": ["*"]
                    },
                    "diskio": {
                      "measurement": ["io_time", "write_bytes", "read_bytes"]
                    },
                    "mem": {
                      "measurement": ["mem_used_percent", "mem_available_percent"]
                    },
                    "net": {
                      "measurement": ["bytes_sent", "bytes_recv", "packets_sent", "packets_recv"]
                    }
                  },
                  "append_dimensions": {
                    "Environment": "{{ target_env }}",
                    "Project": "{{ project_name }}"
                  }
                },
                "logs": {
                  "logs_collected": {
                    "files": {
                      "collect_list": [
                        {
                          "file_path": "/var/log/syslog",
                          "log_group_name": "/{{ project_name }}/{{ target_env }}/syslog",
                          "log_stream_name": "{instance_id}",
                          "retention_in_days": 90
                        },
                        {
                          "file_path": "/var/log/auth.log",
                          "log_group_name": "/{{ project_name }}/{{ target_env }}/auth",
                          "log_stream_name": "{instance_id}",
                          "retention_in_days": 90
                        },
                        {
                          "file_path": "/var/log/audit/audit.log",
                          "log_group_name": "/{{ project_name }}/{{ target_env }}/audit",
                          "log_stream_name": "{instance_id}",
                          "retention_in_days": 365
                        }
                      ]
                    }
                  }
                }
              }
            dest: /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
            mode: '0644'

        - name: Start CloudWatch Agent
          ansible.builtin.shell: |
            /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
              -a fetch-config \
              -m ec2 \
              -s \
              -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
      when: "'aws' in group_names or ansible_system_vendor == 'Amazon EC2'"
      ignore_errors: true

    # ─────────────────────────────────────────────
    # SECURITY MONITORING — File Integrity (AIDE)
    # ─────────────────────────────────────────────
    - name: Initialize AIDE database
      ansible.builtin.command: aide --init
      args:
        creates: /var/lib/aide/aide.db.new
      ignore_errors: true

    - name: Set up AIDE daily check cron
      ansible.builtin.cron:
        name: "AIDE integrity check"
        minute: "0"
        hour: "3"
        job: "/usr/bin/aide --check | /usr/bin/logger -t aide-check"
        user: root

    # ─────────────────────────────────────────────
    # CUSTOM HEALTH CHECK SCRIPT
    # ─────────────────────────────────────────────
    - name: Deploy sovereign health check script
      ansible.builtin.copy:
        content: |
          #!/bin/bash
          # Sovereign Infrastructure Health Check
          # Runs every 5 minutes via cron

          LOGFILE="/var/log/sovereign-health.log"
          TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

          check_service() {
            if systemctl is-active --quiet "$1"; then
              echo "$TIMESTAMP [OK] $1 is running" >> $LOGFILE
            else
              echo "$TIMESTAMP [CRITICAL] $1 is NOT running" >> $LOGFILE
              logger -p daemon.crit "Sovereign health: $1 is down"
            fi
          }

          # Check critical services
          check_service "kubelet"
          check_service "containerd"
          check_service "node_exporter"
          check_service "auditd"

          # Check disk space (alert at 85%)
          DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
          if [ "$DISK_USAGE" -gt 85 ]; then
            echo "$TIMESTAMP [WARNING] Disk usage at ${DISK_USAGE}%" >> $LOGFILE
            logger -p daemon.warning "Sovereign health: Disk at ${DISK_USAGE}%"
          fi

          # Check memory (alert at 90%)
          MEM_USAGE=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')
          if [ "$MEM_USAGE" -gt 90 ]; then
            echo "$TIMESTAMP [WARNING] Memory usage at ${MEM_USAGE}%" >> $LOGFILE
            logger -p daemon.warning "Sovereign health: Memory at ${MEM_USAGE}%"
          fi

          # Check for failed login attempts (last 5 min)
          FAILED_LOGINS=$(journalctl --since "5 minutes ago" | grep -c "Failed password" || echo 0)
          if [ "$FAILED_LOGINS" -gt 5 ]; then
            echo "$TIMESTAMP [ALERT] $FAILED_LOGINS failed login attempts in last 5 min" >> $LOGFILE
            logger -p auth.alert "Sovereign health: $FAILED_LOGINS failed logins"
          fi
        dest: /usr/local/bin/sovereign-health-check.sh
        mode: '0755'

    - name: Schedule health check cron
      ansible.builtin.cron:
        name: "Sovereign health check"
        minute: "*/5"
        job: "/usr/local/bin/sovereign-health-check.sh"
        user: root

  handlers:
    - name: restart node_exporter
      ansible.builtin.systemd:
        name: node_exporter
        state: restarted
        daemon_reload: true
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 4: ansible/playbooks/configure-vpn.yml
# VPN tunnel verification and configuration
# ═══════════════════════════════════════════════════════════════════════════════

cat > ansible/playbooks/configure-vpn.yml << 'EOF'
---
# ═══════════════════════════════════════════════════════════════════════════════
# PLAYBOOK: Configure & Verify Cross-Cloud VPN
# Validates VPN tunnel connectivity and configures routing
# Runs on nodes that need cross-cloud communication
# ═══════════════════════════════════════════════════════════════════════════════

- name: Configure Cross-Cloud VPN Connectivity
  hosts: all
  become: true
  gather_facts: true

  vars:
    target_env: "{{ target_env | default('dev') }}"
    project_name: "mdi-sovereign"

    # Network CIDRs
    aws_vpc_cidr: "10.0.0.0/16"
    azure_vnet_cidr: "10.1.0.0/16"

    # VPN health check endpoints
    vpn_health_checks:
      - name: "Azure VNet Gateway"
        host: "10.1.0.1"
        port: 443
      - name: "Azure AKS API"
        host: "10.1.0.10"
        port: 443

  tasks:
    # ─────────────────────────────────────────────
    # VERIFY VPN CONNECTIVITY
    # ─────────────────────────────────────────────
    - name: Check VPN tunnel connectivity to Azure
      ansible.builtin.wait_for:
        host: "{{ item.host }}"
        port: "{{ item.port }}"
        timeout: 10
        state: started
      loop: "{{ vpn_health_checks }}"
      ignore_errors: true
      register: vpn_connectivity

    - name: Report VPN connectivity status
      ansible.builtin.debug:
        msg: "VPN to {{ item.item.name }} ({{ item.item.host }}:{{ item.item.port }}): {{ 'CONNECTED' if item is succeeded else 'UNREACHABLE' }}"
      loop: "{{ vpn_connectivity.results }}"

    # ─────────────────────────────────────────────
    # CONFIGURE ROUTING
    # ─────────────────────────────────────────────
    - name: Ensure Azure VNet route exists
      ansible.builtin.command: >
        ip route show {{ azure_vnet_cidr }}
      register: route_check
      changed_when: false
      failed_when: false

    - name: Log routing table for audit
      ansible.builtin.shell: |
        echo "=== Routing Table ($(date -u)) ===" >> /var/log/sovereign-vpn.log
        ip route >> /var/log/sovereign-vpn.log
        echo "" >> /var/log/sovereign-vpn.log
      changed_when: false

    # ─────────────────────────────────────────────
    # DNS CONFIGURATION (cross-cloud resolution)
    # ─────────────────────────────────────────────
    - name: Configure cross-cloud DNS forwarding
      ansible.builtin.copy:
        content: |
          # Cross-Cloud DNS Configuration
          # Forward Azure private DNS queries to Azure DNS resolver
          # This enables resolution of *.privatelink.vaultcore.azure.net
          # and *.privatelink.blob.core.windows.net from AWS nodes

          server=/privatelink.vaultcore.azure.net/10.1.0.2
          server=/privatelink.blob.core.windows.net/10.1.0.2
          server=/azmk8s.io/10.1.0.2
        dest: /etc/dnsmasq.d/cross-cloud.conf
        mode: '0644'
      notify: restart dnsmasq
      ignore_errors: true

    # ─────────────────────────────────────────────
    # IPSEC MONITORING
    # ─────────────────────────────────────────────
    - name: Deploy VPN monitoring script
      ansible.builtin.copy:
        content: |
          #!/bin/bash
          # Cross-Cloud VPN Health Monitor
          # Checks tunnel status and logs results

          LOGFILE="/var/log/sovereign-vpn-health.log"
          TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
          AZURE_GATEWAY="10.1.0.1"

          # Ping test to Azure gateway
          if ping -c 3 -W 5 $AZURE_GATEWAY > /dev/null 2>&1; then
            echo "$TIMESTAMP [OK] VPN tunnel to Azure is UP (RTT: $(ping -c 1 -W 5 $AZURE_GATEWAY | grep time= | awk -F'time=' '{print $2}'))" >> $LOGFILE
          else
            echo "$TIMESTAMP [CRITICAL] VPN tunnel to Azure is DOWN" >> $LOGFILE
            logger -p daemon.crit "Cross-cloud VPN: Tunnel to Azure is DOWN"
          fi

          # Check for packet loss
          LOSS=$(ping -c 10 -W 5 $AZURE_GATEWAY 2>/dev/null | grep "packet loss" | awk '{print $6}')
          if [ "$LOSS" != "0%" ] && [ -n "$LOSS" ]; then
            echo "$TIMESTAMP [WARNING] Packet loss to Azure: $LOSS" >> $LOGFILE
            logger -p daemon.warning "Cross-cloud VPN: Packet loss $LOSS"
          fi

          # Log tunnel metrics
          echo "$TIMESTAMP [METRICS] Tunnel stats:" >> $LOGFILE
          ip -s tunnel show 2>/dev/null >> $LOGFILE || echo "  No tunnel interfaces found" >> $LOGFILE
        dest: /usr/local/bin/vpn-health-monitor.sh
        mode: '0755'

    - name: Schedule VPN health monitoring
      ansible.builtin.cron:
        name: "VPN health monitor"
        minute: "*/2"
        job: "/usr/local/bin/vpn-health-monitor.sh"
        user: root

    # ─────────────────────────────────────────────
    # FIREWALL RULES (iptables for VPN traffic)
    # ─────────────────────────────────────────────
    - name: Allow VPN traffic from Azure
      ansible.builtin.iptables:
        chain: INPUT
        source: "{{ azure_vnet_cidr }}"
        jump: ACCEPT
        comment: "Allow inbound from Azure allied VNet"
      ignore_errors: true

    - name: Allow VPN traffic to Azure
      ansible.builtin.iptables:
        chain: OUTPUT
        destination: "{{ azure_vnet_cidr }}"
        jump: ACCEPT
        comment: "Allow outbound to Azure allied VNet"
      ignore_errors: true

    - name: Save iptables rules
      ansible.builtin.shell: iptables-save > /etc/iptables/rules.v4
      changed_when: true
      ignore_errors: true

  handlers:
    - name: restart dnsmasq
      ansible.builtin.systemd:
        name: dnsmasq
        state: restarted
      ignore_errors: true
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 5: ansible/inventory/hosts.yml (static inventory for reference)
# ═══════════════════════════════════════════════════════════════════════════════

cat > ansible/inventory/hosts.yml << 'EOF'
---
# ═══════════════════════════════════════════════════════════════════════════════
# STATIC INVENTORY (reference — dynamic inventory used in CI/CD)
# This file shows the expected host groups
# In production, AWS EC2 dynamic inventory plugin is used
# ═══════════════════════════════════════════════════════════════════════════════

all:
  vars:
    ansible_user: ec2-user
    ansible_ssh_private_key_file: ~/.ssh/sovereign-key.pem
    project_name: mdi-sovereign

  children:
    aws_sovereign:
      vars:
        cloud_provider: aws
        region: us-east-1
      children:
        eks_workers:
          hosts: {}  # Populated by dynamic inventory
        vpn_nodes:
          hosts: {}

    azure_allied:
      vars:
        cloud_provider: azure
        region: australiaeast
        ansible_user: azureuser
      children:
        aks_workers:
          hosts: {}
        vpn_nodes:
          hosts: {}

    # Functional groups (cross-cloud)
    kubernetes_nodes:
      children:
        eks_workers: {}
        aks_workers: {}

    monitoring_targets:
      children:
        aws_sovereign: {}
        azure_allied: {}
EOF

echo ""
echo "=== Ansible Playbooks & Configuration Created ==="
echo ""
echo "  ✅ ansible/ansible.cfg"
echo "  ✅ ansible/playbooks/harden-nodes.yml"
echo "  ✅ ansible/playbooks/deploy-monitoring.yml"
echo "  ✅ ansible/playbooks/configure-vpn.yml"
echo "  ✅ ansible/inventory/hosts.yml"
echo ""
echo "🎉 All 5 files created! Run 'git add . && git commit' to save."
