# Cloud-Native ELT Data Platform with Autonomous AI Analytics Agent

**By: Emediong Edunoh**

## Project Publication

Read the full technical publication covering the design, architecture, and deployment of this platform:
[HERE](https://copper-apple-7ff.notion.site/Design-and-Deployment-of-a-Cloud-Native-ELT-Data-Platform-with-an-Autonomous-AI-Analytics-Agent-3c3f2b9efb1d809ea1effe13f4e0cf55?pvs=74)



## Overview

A cloud-native ELT data platform integrated with a Python-based autonomous AI Analytics Agent.

The goal of this work is to significantly reduce the time between data ingestion, analysis, and decision-making by automating data workflows from ingestion to insight generation and decision support. This enables faster, better-informed business decisions and improves operational efficiency.

The platform integrates data engineering, cloud infrastructure, workflow orchestration, and AI agent development into a unified ecosystem. 

A 12-hour cost experiment comparing self-managed and fully managed compute architectures demonstrated a **57.56% reduction in compute costs** with the self-managed approach.

<br>

## High-level Diagram

<img width="1536" height="1024" alt="image" src="https://github.com/user-attachments/assets/f1d88698-1199-4357-a3fd-640635b5fac0" />

<br>


<br>

## Technical & Detailed Architecture Diagram

<img width="4681" height="2870" alt="DataPlatform_Diagram" src="https://github.com/user-attachments/assets/890ea9dc-11ca-49ca-8086-23c25f1565ff" />


<br>

## Technology Stack

- **Cloud Infrastructure:** AWS (ECS, EC2, S3, ECR, RDS, MSK, IAM, CloudWatch)
- **Data Engineering & Orchestration:** Apache Kafka, Apache Airflow, Snowflake, dbt
- **AI & Integrations:** OpenRouter (Anthropic, OpenAI, DeepSeek LLMs), Tavily API
- **Programming:** Python, SQL
- **Infrastructure & Deployment:** Terraform, Docker, GitHub Actions
- **Communication:** Slack API and Webhook

<br>

## System Integration & Orchestration

The platform integrates multiple services into a unified, automated data ecosystem.

- **Cloud Infrastructure:** AWS provides the underlying compute, networking, storage, security, and deployment infrastructure.
- **Data Engineering:** Kafka handles event streaming, Airflow coordinates workflows, and Snowflake provides centralized data storage and analytics.
- **AI Integration:** OpenRouter connects the platform to multiple LLM providers, while Tavily enables external information retrieval.
- **Data Transformation:** dbt manages data modelling, testing, documentation, and governance.
- **Infrastructure Automation:** Terraform provisions infrastructure, while GitHub Actions automates CI/CD and deployment.
- **Communication:** Slack delivers AI-generated insights, executive summaries, and operational notifications.

<br>

## Multi-Source ELT Data Platform

The platform integrates three data ingestion workflows:

- **Streaming:** Kafka → AWS MSK → Snowpipe Streaming → Snowflake, with Parquet backups in S3.
- **Batch:** Google Sheets → Airflow → S3 → Snowpipe → Snowflake.
- **Document Processing:** PDFs → Python/LLM Extraction → S3 → Snowpipe → Snowflake.

<br>

**Data Transformation & Governance:**

- Snowflake Medallion Architecture: Bronze, Silver, and Gold.
- dbt transformations and data modelling.
- Data quality tests and data contracts.
- SCD Type 2 snapshots and historical tracking.
- Data lineage and automated documentation.

<br>

## Autonomous AI Analytics Agent

A Python-based autonomous AI Analytics Agent powered by OpenRouter, supporting multiple LLM providers, including Anthropic, OpenAI, and DeepSeek.

Unlike a conventional chatbot, the agent autonomously determines what analysis is required, selects the appropriate tools, investigates findings, and generates actionable, data-backed recommendations.

There is human in the loop to validate agent's outputs

**Agent Tools:**

1. **Query Snowflake:** Dynamically generates and executes SQL to investigate business performance, monitor data quality, identify anomalies, and perform historical comparisons.
2. **Web Search:** Uses Tavily API to retrieve external information, industry trends, competitor intelligence, and macroeconomic developments.
3. **Policy Search:** Uses Snowflake Cortex Search, with SQL fallback, to retrieve internal policies, SOPs, and operational guidelines.


### Autonomous Investigation Workflow

The agent operates through an iterative tool-calling workflow, with a maximum of 10 iterations per execution.

1. Receives an analysis or monitoring task through Airflow.
2. Evaluates the task and determines the information required.
3. Autonomously selects and invokes the appropriate tools.
4. Queries Snowflake, searches external sources, and retrieves internal policies where necessary.
5. Investigates findings, identifies anomalies, and compares results against historical summaries.
6. Generates evidence-backed insights and business recommendations.
7. Stores executive summaries in Snowflake and delivers findings to stakeholders through Slack.

<br>

## Infrastructure & Deployment

- AWS ECS on EC2 with Auto Scaling and multi-Availability Zone deployment.
- Docker containerization and Amazon ECR.
- Terraform-managed infrastructure.
- GitHub Actions CI/CD.
- IAM-based access control and secure runtime configuration.
- Amazon S3 for durable storage, recovery, and data replay.
- Amazon CloudWatch for operational monitoring.
