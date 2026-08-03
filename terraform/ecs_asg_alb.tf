

# Create the ECS cluster
resource "aws_ecs_cluster" "data_platform_cluster" {
  name = var.ecs_cluster_name
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Create a launch template. 
# But before that, we will generate the recommended Amazon ECS-optimized Linux AMI using SSM parameter which what is used in practice.
data "aws_ssm_parameter" "ecs_node_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

resource "aws_launch_template" "data_platform_lt" {
  name          = var.data_platform_lt_name
  image_id      = data.aws_ssm_parameter.ecs_node_ami.value
  instance_type = var.ec2_server_type

  vpc_security_group_ids = [aws_security_group.launch_template_sg.id]

  iam_instance_profile { name = aws_iam_instance_profile.data_platform_instance_profile.name }
  monitoring { enabled = true }

  key_name = var.ec2_key_name

  # With this configuration, the EC2 in the ASG will join the ECS cluster
  user_data = base64encode(<<-EOF
      #!/bin/bash
      echo ECS_CLUSTER=${aws_ecs_cluster.data_platform_cluster.name} >> /etc/ecs/ecs.config;
    EOF
  )

  tags = {
    Name = "ECS-Server"
  }
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Create the Auto Scaling Group (ASG) for the cluster and connect the launch template to it.
# The ec2 instances in the ASG will join the ECS cluster. The configuration for this is defined in the EC2 user data script as stated in the launch template resource.
resource "aws_autoscaling_group" "data_platform_asg" {
  name = var.data_platform_asg_name

  # containers will be deployed in the private subnet 
  vpc_zone_identifier = aws_subnet.private[*].id
  desired_capacity    = 2
  max_size            = 3
  min_size            = 2

  launch_template {
    id      = aws_launch_template.data_platform_lt.id
    version = "$Latest"
  }

  force_delete = true
}




# TROUBLESHOOTING
# The ECS capacity provider automatically created a lifecycle hook (ecs-managed-draining-termination-hook) on your Auto Scaling Group with a 1‑hour heartbeat timeout, causing every instance termination (scale‑in, destroy) to be stuck in Terminating:Wait for up to 60 minutes.
# This also caused ASG termination to take unnessary long (up to an hour)
# This happened even though managed_termination_protection was disabled; the hook persisted from the capacity provider’s association.
# The permanent fix is to manage that hook explicitly in Terraform with heartbeat_timeout = 30 seconds and default_result = "CONTINUE".
# Once applied, Terraform owns the hook and enforces the 30‑second timeout, eliminating the long termination delays permanently, with no further manual intervention needed.


resource "aws_autoscaling_lifecycle_hook" "ecs_draining" {
  name                   = "ecs-managed-draining-termination-hook"
  autoscaling_group_name = aws_autoscaling_group.data_platform_asg.name
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
  heartbeat_timeout      = 30 # 30 seconds
  default_result         = "CONTINUE"
}



# Note you can also manually delete the hook using these codes: 

# 1. First run these to check the if there are instances with Terminating:Wait
# aws autoscaling describe-auto-scaling-instances \
#   --region eu-north-1 \
#   --query 'AutoScalingInstances[?AutoScalingGroupName==`data_platform_asg`].[InstanceId,LifecycleState,ProtectedFromScaleIn]' \
#   --output table 

# 2. Run this to be sure you have an active lifecycle hook
# aws autoscaling describe-lifecycle-hooks \
#   --auto-scaling-group-name data_platform_asg \
#   --region eu-north-1

# 3. Finally, RUN this to delete the hook. This will terminate the instance immediately and free the ASG
# aws autoscaling delete-lifecycle-hook \
#   --auto-scaling-group-name data_platform_asg \
#   --lifecycle-hook-name ecs-managed-draining-termination-hook \
#   --region eu-north-1





#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Create the Target Group and Load Balancer
resource "aws_lb" "data_platform_load_balancer" {
  name               = var.load_balancer_name
  load_balancer_type = "application"
  security_groups    = [aws_security_group.load_balancer_sg.id]
  subnets            = aws_subnet.public[*].id
}



# I encountered a problem where two web UIs (Airflow webserver and Kafka UI) running on separate ECS services, both using the same container port (8080)
# I wanted to expose both through a single Application Load Balancer without path‑ or host‑based routing.

# To solve this, I will create two listeners for the load balancers on different external ports (e.g., 80 and 81). Each listener forwards traffic to its own target group, which points to the respective container's port. 
# Since each ECS task has its own private IP (awsvpc mode), both services can safely listen on 8080 internally without conflict. 
# Airflow via http://<alb-dns> (port 80) 
# Kafka UI via http://<alb-dns>:81

# This keeps the configuration simple and avoids modifying default application ports.


# Airflow webserver target group
resource "aws_lb_target_group" "airflow_webserver_target_group" {
  name        = var.airflow_webserver_target_group_name
  vpc_id      = aws_vpc.main.id
  protocol    = "HTTP"
  port        = 8080
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # This ensures alb doesn't take long to deregister targets.
  deregistration_delay = 30
}


# Kafka UI target group
resource "aws_lb_target_group" "kafka_ui_target_group" {
  name        = var.kafka_ui_target_group_name
  vpc_id      = aws_vpc.main.id
  protocol    = "HTTP"
  port        = 8080
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/"
    port                = "traffic-port"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # This ensures alb doesn't take long to deregister targets.
  deregistration_delay = 30
}


# Airflow webserver listener
resource "aws_lb_listener" "airflow_webserver_listener" {
  load_balancer_arn = aws_lb.data_platform_load_balancer.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.airflow_webserver_target_group.arn
  }
}


# Kafka UI listener
resource "aws_lb_listener" "kafka_ui_listener" {
  load_balancer_arn = aws_lb.data_platform_load_balancer.arn
  port              = 81
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kafka_ui_target_group.arn
  }
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# The "ecs_capacity_provider" resource connects an Auto Scaling Group (ASG) to ECS and allows ECS to manage the ASG’s size (scale in/out).
# It tells ECS: “Here’s an ASG. When you run out of capacity, you can increase its size. When you have too many idle instances, you can decrease it.”
# Without it, the ASG scales independently. You’d have to set up your own CloudWatch alarms or manual/generic scaling policies such as CPU utilization etc.
# The problem is that CPU utilization is not the same thing as ECS capacity. So CPU utilization rate as a metric won't work well in ECS.

# The Autoscaling Group's MIN_SIZE and MAX_SIZE define the hard boundaries within which the Capacity Provider (or any scaling policy) can adjust the desired number of EC2 instances.
# NOTE: Without a Capacity Provider, EC2 instances can still join the ECS cluster at boot time as configured in the launch template, just that you will need to configure your scaling policies.

resource "aws_ecs_capacity_provider" "capacity_provider" {
  name = "cap_provider"
  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.data_platform_asg.arn

    # It prevents the ASG from terminating EC2 instances that still have running ECS tasks.
    # ENABLED → ECS protects busy instances from scale-in (terminated by ASG)
    # DISABLED → ASG may terminate any instance during scale-in.

    # FOR NOW WE WILL DISABLE IT. If we later want managed termination protection, we will change it to "ENALBLED" and also enable instance protection in the ASG (protect_from_scale_in = true on the ASG resource)
    managed_termination_protection = "DISABLED"

    managed_scaling {
      maximum_scaling_step_size = 2
      minimum_scaling_step_size = 1
      status                    = "ENABLED"

      #target_capacity = 100 → ECS waits until existing EC2 instances are 100% utilized before adding another one.
      target_capacity = 100
    }
  }
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# This "ecs_cluster_capacity_providers" resource attaches the capacity provider (from the previous step) to your ECS cluster.
# It also sets a default capacity provider strategy: when you create a service without specifying exactly where to run it (no launch_type or custom strategy), 
# ECS will use this default strategy to pick which capacity provider to use (e.g., “use my EC2 capacity provider, try to place one task, weight 100”).
# Without it, you can still use the capacity provider by explicitly referencing it in each service’s capacity_provider_strategy.

resource "aws_ecs_cluster_capacity_providers" "cluster_capacity_provider" {
  cluster_name       = aws_ecs_cluster.data_platform_cluster.name
  capacity_providers = [aws_ecs_capacity_provider.capacity_provider.name]

  # This is a strategy for placing capacity providers on tasks. It is mostly useful when you have mulitple capacity providers.
  default_capacity_provider_strategy {

    # capacity_provider: Which Capacity Provider (and therefore which ASG) to use.
    # base = 1: Always place at least 1 task on this Capacity Provider before considering others.
    # weight = 100: After the base tasks, distribute tasks according to the weight. Since we have only one capacity provider, it will be used on 100% of tasks.
    capacity_provider = aws_ecs_capacity_provider.capacity_provider.name
    base              = 1
    weight            = 100
  }
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# IMPORTANT!

# "awsvpc" network mode gives each ECS task its own elastic network interface (ENI) with a private IP inside your VPC, separate from the EC2 host.
# ALB target type: "instance" → routes traffic to the EC2 instance’s IP + a host port (not directly to the task). Works with bridge or host network mode.
# ALB target type: "ip" → routes traffic directly to the task’s ENI private IP + container port. This is the correct choice when using awsvpc.
# With "ip" with "awsvpc" – you can run multiple tasks on the same instance without port collisions, apply security groups per task, and the ALB bypasses the host.
# Rule: With awsvpc, always set target_type = "ip" in your ALB target group.




# TROUBLESHOOTING
# Airflow tasks and services repeatedly encountered Out of Memory (OOM) errors. 
# To resolve this, I progressively increased their CPU and memory allocations until resource utilization stabilized and the tasks ran reliably.




# TROUBLESHOOTING: 
# Airflow task logs (dbt build) not visible in the web UI or CloudWatch

# Problem:
# The Airflow scheduler/worker and webserver run as separate containers/ECS tasks with no shared filesystem.
# When a task (e.g., dbt build) executes, Airflow writes detailed task logs to a file on the worker’s local disk ({AIRFLOW_HOME}/logs/{dag_id}/{task_id}/{execution_date}/{attempt}.log).
# The webserver, which serves the UI, cannot read that disk, so the log panel appears empty.
# Even though an ECS log group captures container stdout/stderr, Airflow task log files are NOT automatically streamed to stdout – they remain on disk and never reach CloudWatch.
# That’s why the logs exist on the worker but are invisible in CloudWatch and the UI.

# Solutions:
# Enable Airflow’s remote logging so that task logs are stored in a shared location (S3 or CloudWatch) that both the worker and the webserver can access.

# Solution 1: Remote logging to S3
# Set these environment variables on BOTH the webserver and the scheduler/worker tasks:
# AIRFLOW__LOGGING__REMOTE_LOGGING = True
# AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER = s3://your-bucket/airflow-logs/
# AIRFLOW__LOGGING__REMOTE_LOG_CONN_ID = aws_default


# Solution 2: Remote logging to CloudWatch
# Set these environment variables on BOTH the webserver and scheduler/worker tasks:
# AIRFLOW__LOGGING__REMOTE_LOGGING = True
# AIRFLOW__LOGGING__REMOTE_LOG_CONN_ID = aws_default
# AIRFLOW__LOGGING__REMOTE_TASK_LOG_HANDLER = cloudwatch
# AIRFLOW__LOGGING__REMOTE_LOG_GROUP = /aws/ecs/your-airflow-log-group   # must already exist
# AIRFLOW__LOGGING__REMOTE_REGION = us-east-1
# Ensure the IAM role has logs:CreateLogStream and logs:PutLogEvents for the worker, and logs:GetLogEvents / logs:DescribeLogStreams for the webserver.


# Common notes:
# Leave the aws_default connection credentials in airfow variables blank; Airflow will automatically use the IAM role attached to your EC2 instance or ECS task.
# S3: Logs are stored under a structured path: s3://bucket/airflow-logs/{dag_id}/{task_id}/{execution_date}/{attempt}.log
# CloudWatch: log group with log streams per task attempt The webserver fetches exactly the log for the current task attempt, so there’s no ambiguity.




# Define the ECS TASKS

# I will store some local variables here to avoid repeatition and keep my config file clean
locals {
  # This stores Airflow cloudwatch log configurations
  airflow_log_config = {
    logDriver = "awslogs",
    options = {
      awslogs-group         = "${aws_cloudwatch_log_group.airflow_log_group.name}",
      awslogs-region        = var.region,
      awslogs-stream-prefix = "airflow"
    }
  }

  # This stores Kafka utilities cloudwatch log configurations
  kafka_log_config = {
    logDriver = "awslogs",
    options = {
      awslogs-group         = "${aws_cloudwatch_log_group.kafka_utilities_log_group.name}",
      awslogs-region        = var.region,
      awslogs-stream-prefix = "kafka_utilities"
    }
  }

  # This stores the RDS connection string containing db_name, db_username, db_password and rds_endpoint
  airflow_rds_connection = "postgresql+psycopg2://${var.airflow_rds_username}:${var.airflow_rds_password}@${aws_db_instance.airflow_postgres_instance.endpoint}/${var.airflow_db_name}"

}



# AIRFLOW TASKS AND CONTAINER DEFINITIONS
resource "aws_ecs_task_definition" "airflow_init_task" {
  family             = "airflow_init"
  task_role_arn      = aws_iam_role.airflow_task_role.arn
  execution_role_arn = aws_iam_role.ecs_task_exec_role.arn
  network_mode       = "awsvpc"
  cpu                = "512"
  memory             = "512"
  container_definitions = jsonencode([
    {
      name      = "airflow_init_task",
      image     = "${aws_ecr_repository.airflow_repository.repository_url}:latest",
      essential = true,

      # This enables cloudwatch log group  
      logConfiguration = local.airflow_log_config,
      
      # The username and passwrod used here are for tests, in a production environment, I will conceal them
      command = [
        "bash", "-c",
        "airflow db migrate && (airflow users list | grep -q admin || airflow users create --username admin --password admin --firstname Admin --lastname User --role Admin --email admin@example.com)"
      ],
      environment = [{ name = "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN", value = local.airflow_rds_connection }]
    }
  ])
}

resource "aws_ecs_task_definition" "airflow_scheduler_task" {
  family             = "airflow_scheduler"
  task_role_arn      = aws_iam_role.airflow_task_role.arn
  execution_role_arn = aws_iam_role.ecs_task_exec_role.arn
  network_mode       = "awsvpc"
  cpu                = "512"
  memory             = "2048"
  container_definitions = jsonencode([
    {
      name             = "airflow_scheduler_task",
      image            = "${aws_ecr_repository.airflow_repository.repository_url}:latest",
      essential        = true,
      logConfiguration = local.airflow_log_config,
      command          = ["airflow", "scheduler"],
      environment = [
        { name = "AIRFLOW__CORE__EXECUTOR", value = "LocalExecutor" },
        { name = "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN", value = local.airflow_rds_connection },
        { name = "AIRFLOW__CORE__LOAD_EXAMPLES", value = "false" },

        # Explanations for these are outlined in the TROUBLESHOOTING section above
        { name = "AIRFLOW__LOGGING__REMOTE_LOGGING", value = "True" },
        { name = "AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER", value = "s3://${aws_s3_bucket.dbt_docs.bucket}/airflow-logs/" },
        { name = "AIRFLOW__LOGGING__REMOTE_LOG_CONN_ID", value = "aws_default" }
      ]
    }
  ])
}

resource "aws_ecs_task_definition" "airflow_webserver_task" {
  family             = "airflow_webserver"
  task_role_arn      = aws_iam_role.airflow_task_role.arn
  execution_role_arn = aws_iam_role.ecs_task_exec_role.arn
  network_mode       = "awsvpc"
  cpu                = "512"
  memory             = "1024"
  container_definitions = jsonencode([
    {
      name             = "airflow_webserver_task",
      image            = "${aws_ecr_repository.airflow_repository.repository_url}:latest",
      essential        = true,
      logConfiguration = local.airflow_log_config,
      command          = ["airflow", "webserver"],

      # The hostPort is however ignored because we are using "awsvpc" + "ip" connection 
      portMappings = [{ containerPort = 8080, protocol = "tcp" }],

      environment = [
        { name = "AIRFLOW__CORE__EXECUTOR", value = "LocalExecutor" },
        { name = "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN", value = local.airflow_rds_connection },
        { name = "AIRFLOW__CORE__LOAD_EXAMPLES", value = "false" },

        # I need to set this at 2 (adequate for my workload). If its more than that, I'll most likely have Out Of Memory (OOM) errors
        { name = "AIRFLOW__WEBSERVER__WORKERS", value = "2" },

        # Explanations for these are outlined in the TROUBLESHOOTING section above
        { name = "AIRFLOW__LOGGING__REMOTE_LOGGING", value = "True" },
        { name = "AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER", value = "s3://${aws_s3_bucket.dbt_docs.bucket}/airflow-logs/" },
        { name = "AIRFLOW__LOGGING__REMOTE_LOG_CONN_ID", value = "aws_default" }
      ]
    }
  ])
}



# KAFKA UTILITIES TASKS AND CONTAINER DEFINITIONS
resource "aws_ecs_task_definition" "kafka_producer_task" {
  family             = "kafka_producer"
  task_role_arn      = aws_iam_role.kafka_utilities_task_role.arn
  execution_role_arn = aws_iam_role.ecs_task_exec_role.arn
  network_mode       = "awsvpc"
  cpu                = "256"
  memory             = "512"
  container_definitions = jsonencode([
    {
      name      = "kafka_producer_task",
      image     = "${aws_ecr_repository.kafka_producer_repository.repository_url}:latest",
      essential = true,

      # This enables cloudwatch log group
      logConfiguration = local.kafka_log_config
    }
  ])
}

resource "aws_ecs_task_definition" "kafka_consumer_task" {
  family             = "kafka_consumer"
  task_role_arn      = aws_iam_role.kafka_utilities_task_role.arn
  execution_role_arn = aws_iam_role.ecs_task_exec_role.arn
  network_mode       = "awsvpc"
  cpu                = "256"
  memory             = "768"
  container_definitions = jsonencode([
    {
      name      = "kafka_consumer_task",
      image     = "${aws_ecr_repository.kafka_consumer_repository.repository_url}:latest",
      essential = true,

      # This enables cloudwatch log group
      logConfiguration = local.kafka_log_config
    }
  ])
}

resource "aws_ecs_task_definition" "kafka_ui_task" {
  family             = "kafka_ui"
  task_role_arn      = aws_iam_role.kafka_utilities_task_role.arn
  execution_role_arn = aws_iam_role.ecs_task_exec_role.arn
  network_mode       = "awsvpc"
  cpu                = "256"
  memory             = "768"
  container_definitions = jsonencode([
    {
      name      = "kafka_ui_task",
      image     = "provectuslabs/kafka-ui:latest", #official (widely used) kafka-ui image
      essential = true,

      # This enables cloudwatch log group
      logConfiguration = local.kafka_log_config,

      # The hostPort is however ignored because we are using "awsvpc" + "ip" connection 
      portMappings = [{ containerPort = 8080, protocol = "tcp" }],

      environment = [
        { name = "KAFKA_CLUSTERS_0_NAME", value = "${var.kafka_cluster_name}" },

        # kafka UI connects to MSKafka's bootsrap server
        { name = "KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS", value = "${aws_msk_cluster.data_platform_kafka.bootstrap_brokers}" }
      ]
    }
  ])
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# IMPORTANT!

# When you increase the desired_count of the webserver service, ECS launches additional tasks (each containing a webserver container) anywhere in the cluster (could be on the same EC2 instance if resources allow, or spread across instances).
# Because you use awsvpc network mode + ALB target type ip, each new task gets its own private IP address and registers itself with the ALB target group. The ALB then distributes incoming traffic across these IPs.

# The scheduler service is completely separate — the ALB never touches it. Both services can run on the same physical host(s) without interfering, because they have different IPs and no port conflicts (each task has its own ENI). 
# Scaling is based on IPs, not host ports.

# I don't need to define launch_type = "EC2" because this service uses a capacity provider.
# launch_type and capacity_provider_strategy are mutually exclusive, you can use only one.
# By using capacity_provider_strategy, ECS can work with the Auto Scaling Group to scale EC2 capacity based on task demand, which is not available when using launch_type alone.


# ordered_placement_strategy tells the ECS scheduler how to distribute your tasks across your EC2 instances. 
# In this project, I configured tasks to be spread evenly across availability zones. This only happens if we have desired_count > 1


# In ECS, there is no native “service‑to‑service” dependency like Docker Compose’s depends_on. 
# You can’t tell ECS “start the producer service only after the consumer service is healthy”. 
# ECS services are independent; they start tasks as soon as the service is created, and tasks keep restarting on failure.


# TROUBLESHOOT
# When you create a service without a launch type or service specific capacity provider strategy, the AWS API automatically copies the cluster's default capacity‑provider strategy onto that service.
# Terraform reads the service after creation, sees that the service has a capacity_provider_strategy, and saves it in the state file.
# Because your .tf file doesn't include that capacity_provider_strategy block, Terraform plans to remove it, and this change forces a destructive replace of the whole service.
# This is why we DON'T rely on the cluster default capacity strategy. ENSURE to add the strategy to each service so that terraform doesn't force replace them due to a mismatch in .tf configuration



# In subsequent iterations of this project, I will add ECS Service Auto Scaling


# Define the ECS SERVICES

# AIRFLOW SERVICES
resource "aws_ecs_service" "airflow_scheduler_service" {
  name            = "airflow_scheduler_service"
  cluster         = aws_ecs_cluster.data_platform_cluster.id
  task_definition = aws_ecs_task_definition.airflow_scheduler_task.arn
  desired_count   = 1
  force_delete    = true

  network_configuration {
    security_groups  = [aws_security_group.airflow_sg.id]
    subnets          = aws_subnet.private[*].id
    assign_public_ip = false
  }

  # RULE 1: Balance tasks across different physical AZs first
  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  # RULE 2: Inside those AZs, pack them tightly onto the fewest EC2 instances
  ordered_placement_strategy {
    type  = "binpack"
    field = "memory"
  }

  # It is important to define a service-specific capacity provider strategy instead of relying solely on the cluster's default strategy. 
  # Without it, the AWS API automatically applies the cluster's default settings, creating a mismatch with your terraform configuration file and that forces Terraform to destructively replace the service.
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.capacity_provider.name
    base              = 1
    weight            = 100
  }
}

resource "aws_ecs_service" "airflow_webserver_service" {
  name            = "airflow_webserver_service"
  cluster         = aws_ecs_cluster.data_platform_cluster.id
  task_definition = aws_ecs_task_definition.airflow_webserver_task.arn
  desired_count   = 1
  force_delete    = true

  network_configuration {
    security_groups  = [aws_security_group.airflow_sg.id]
    subnets          = aws_subnet.private[*].id
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.airflow_webserver_target_group.arn
    container_name   = "airflow_webserver_task"
    container_port   = 8080
  }

  # RULE 1: Balance tasks across different physical AZs first
  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  # RULE 2: Inside those AZs, pack them tightly onto the fewest EC2 instances
  ordered_placement_strategy {
    type  = "binpack"
    field = "memory"
  }
  # It is important to define a service-specific capacity provider strategy instead of relying solely on the cluster's default strategy. 
  # Without it, the AWS API automatically applies the cluster's default settings, creating a mismatch with your terraform configuration file and that forces Terraform to destructively replace the service.  
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.capacity_provider.name
    base              = 1
    weight            = 100
  }
}




# KAFKA SERVICES
resource "aws_ecs_service" "kafka_producer_service" {
  name            = "kafka_producer_service"
  cluster         = aws_ecs_cluster.data_platform_cluster.id
  task_definition = aws_ecs_task_definition.kafka_producer_task.arn
  desired_count   = 1
  force_delete    = true

  network_configuration {
    security_groups  = [aws_security_group.kafka_utilities_sg.id]
    subnets          = aws_subnet.private[*].id
    assign_public_ip = false
  }

  # RULE 1: Balance tasks across different physical AZs first
  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  # RULE 2: Inside those AZs, pack them tightly onto the fewest EC2 instances
  ordered_placement_strategy {
    type  = "binpack"
    field = "memory"
  }

  # It is important to define a service-specific capacity provider strategy instead of relying solely on the cluster's default strategy. 
  # Without it, the AWS API automatically applies the cluster's default settings, creating a mismatch with your terraform configuration file and that forces Terraform to destructively replace the service.
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.capacity_provider.name
    base              = 1
    weight            = 100
  }

  # Ensure MSK exists before this service is created
  depends_on = [aws_msk_cluster.data_platform_kafka]
}

resource "aws_ecs_service" "kafka_consumer_service" {
  name            = "kafka_consumer_service"
  cluster         = aws_ecs_cluster.data_platform_cluster.id
  task_definition = aws_ecs_task_definition.kafka_consumer_task.arn
  desired_count   = 1
  force_delete    = true

  network_configuration {
    security_groups  = [aws_security_group.kafka_utilities_sg.id]
    subnets          = aws_subnet.private[*].id
    assign_public_ip = false
  }

  # RULE 1: Balance tasks across different physical AZs first
  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  # RULE 2: Inside those AZs, pack them tightly onto the fewest EC2 instances
  ordered_placement_strategy {
    type  = "binpack"
    field = "memory"
  }

  # It is important to define a service-specific capacity provider strategy instead of relying solely on the cluster's default strategy. 
  # Without it, the AWS API automatically applies the cluster's default settings, creating a mismatch with your terraform configuration file and that forces Terraform to destructively replace the service.
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.capacity_provider.name
    base              = 1
    weight            = 100
  }

  # Ensure MSK exists before this service is created
  depends_on = [aws_msk_cluster.data_platform_kafka]
}

resource "aws_ecs_service" "kafka_ui_service" {
  name            = "kafka_ui_service"
  cluster         = aws_ecs_cluster.data_platform_cluster.id
  task_definition = aws_ecs_task_definition.kafka_ui_task.arn
  desired_count   = 1
  force_delete    = true

  network_configuration {
    security_groups  = [aws_security_group.kafka_utilities_sg.id]
    subnets          = aws_subnet.private[*].id
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.kafka_ui_target_group.arn
    container_name   = "kafka_ui_task"
    container_port   = 8080
  }

  # RULE 1: Balance tasks across different physical AZs first
  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  # RULE 2: Inside those AZs, pack them tightly onto the fewest EC2 instances
  ordered_placement_strategy {
    type  = "binpack"
    field = "memory"
  }

  # It is important to define a service-specific capacity provider strategy instead of relying solely on the cluster's default strategy. 
  # Without it, the AWS API automatically applies the cluster's default settings, creating a mismatch with your terraform configuration file and that forces Terraform to destructively replace the service.
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.capacity_provider.name
    base              = 1
    weight            = 100
  }

  # Ensure MSK exists before this service is created
  depends_on = [aws_msk_cluster.data_platform_kafka]
}





# Output
output "ecs_cluster_name" {
  value = aws_ecs_cluster.data_platform_cluster.name
}

output "autoscaling_group_name" {
  value = aws_autoscaling_group.data_platform_asg.name
}