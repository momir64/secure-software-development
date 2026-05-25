# Secure Deployment Environment Audit Tool

## Overview

This directory is a modular security auditing suite. The tool automates the review of Linux system configurations and network hardening to identify common vulnerabilities before deployment.

## Project Structure

- main_audit.sh: The master orchestrator script that triggers all sub-scripts and aggregates results. When running inside Docker, it also initializes and starts all services before the audit begins.
- system_review.sh: Detailed audit of OS, logging, and time services. Details could be found in the [system_review.md file](./system_review.md).
- network_review.sh: Audit of firewall rules, DNS, and network protocols. Details could be found in the [network_review.md file](./network_review.md).
- filesystem_review.sh: Audit of mount options, sensitive file permissions, SETUID binaries, and backup exposure. Details could be found in the [filesystem_review.md file](./filesystem_review.md).
- users_review.sh: Audit of user accounts, password policies, sudo rules, and SSH access controls. Details could be found in the [users_review.md file](./users_review.md).
- services_review.sh: Audit of running processes, listening services, and daemon configurations (SSH, MySQL, Apache, PHP, Nginx, cron). Details could be found in the [services_review.md file](./services_review.md).



## How to Run

The tool is designed to run within a controlled environment (Docker) to ensure consistency across different host systems.

1. Build the Audit Image:
   Build the container using the provided Dockerfile. This will automatically configure the legacy repositories for the Debian environment.

    ```bash
    cd scripts
    docker build -t secure-audit:latest .
    ```

2. Run the Audit:
   Execute the container with administrative privileges (NET_ADMIN) to allow the tool to inspect firewall rules.

    ```bash
   docker run --rm --cap-add=NET_ADMIN secure-audit:latest
    ```

3. Review Results:
   The tool will output a detailed log. Look for [WARNING] and [CRITICAL] tags to identify areas that require hardening.
