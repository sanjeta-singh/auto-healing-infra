# Azure Self-Healing Infrastructure

## Overview

An event-driven self-healing cloud architecture on Microsoft Azure that replicates Kubernetes-style pod recovery for containerized applications. The platform continuously monitors application health, detects service-level failures, and automatically restores unhealthy workloads without manual intervention.

## Key Highlights

* Built a self-healing architecture using **4 core Azure services**: Azure VM, Azure Functions, Azure Monitor, and Azure Virtual Network.
* Implemented application-aware health monitoring using **Application Insights availability tests** to detect failures beyond traditional CPU and memory metrics.
* Automated incident remediation through **Azure Functions** that restart unhealthy Docker containers upon alert triggers.
* Established deep observability with Azure Monitor alerts, Application Insights telemetry, and automated incident notifications.
* Provisioned and managed **7+ Azure infrastructure components** using **Terraform**, including VNets, Subnets, NSGs, Public IPs, NICs, and Ubuntu Virtual Machines.
* Integrated **Managed Identities** to enable secure, passwordless authentication following Zero-Trust principles.
* Achieved automated recovery of failed services to a healthy **HTTP 200** state in **under 2 minutes**, reducing Mean Time to Repair (MTTR).

## Architecture Flow

Application Failure → Application Insights Health Check → Azure Monitor Alert → Action Group → Azure Function → Docker Container Restart → Service Recovery

## Current Status

* ✅ Monitoring, alerting, notification, and self-healing workflows manually validated.
* ✅ Terraform infrastructure provisioning implemented.
* 🚧 Codifying Azure Monitor Alerts, Action Groups, and Managed Identities with Terraform.
* 🚧 Integrating GitHub Actions for automated CI/CD deployments.
