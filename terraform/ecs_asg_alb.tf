

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
  image_id      = data.aws_ssm_parameter.ecs_node_ami.name
  instance_type = var.ec2_server_type

  vpc_security_group_ids = [aws_security_group.launch_template_sg.id]

  iam_instance_profile { name = aws_iam_instance_profile.data_platform_instance_profile.name }
  monitoring { enabled = true }

  key_name = var.ec2_key_name

  # In user_data you is required to pass ECS cluster name, so AWS can register EC2 instance as node of ECS cluster at boot time.
  user_data = templatefile("data_platform_user_data.sh", { ecs_cluster_name = aws_ecs_cluster.data_platform_cluster.name })
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Create the Auto Scaling Group (ASG) for the cluster and connect the launch template to it.
# The ec2 instances in the ASG will join the ECS cluster. The configuration for this is defined in the EC2 user data script as stated in the launch template resource.
resource "aws_autoscaling_group" "data_platform_asg" {
  name = var.data_platform_asg_name

  # containers will be deployed in the private subnet 
  vpc_zone_identifier = aws_subnet.private[*].id
  desired_capacity    = 1
  max_size            = 3
  min_size            = 1

  launch_template {
    id      = aws_launch_template.data_platform_lt.id
    version = "$Latest"
  }

}




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
  port        = 80
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/"
    port                = 80
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}


# Kafka UI target group
resource "aws_lb_target_group" "kafka_ui_target_group" {
  name        = var.kafka_ui_target_group_name
  vpc_id      = aws_vpc.main.id
  protocol    = "HTTP"
  port        = 80
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/"
    port                = 80
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
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
    managed_termination_protection = "ENABLED"

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


# Define the ECS TASKS

# I will store some local variables here to avoid repeatition and keep my config file clean
locals {
  # This stores Airflow cloudwatch log configurations
  airflow_log_config = {
    logDriver = "awslogs",
    options = {
      awslogs-group         = "${aws_cloudwatch_log_group.kafka_utilities_log_group.name}",
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
  airflow_rds_connection = "postgresql+psycopg2://${var.airflow_db_username}:${var.airflow_db_password}@${aws_db_instance.airflow_postgres_instance.endpoint}/${var.airflow_db_name}"

}



# AIRFLOW TASKS AND CONTAINER DEFINITIONS
resource "aws_ecs_task_definition" "airflow_init_task" {
  family             = "airflow_init"
  task_role_arn      = aws_iam_role.airflow_task_role.arn
  execution_role_arn = aws_iam_role.ecs_task_exec_role.arn
  network_mode       = "awsvpc"
  cpu                = "512"
  memory             = "1024"
  container_definitions = jsonencode([
    {
      name      = "airflow_init_task",
      image     = "${aws_ecr_repository.airflow_repository.repository_url}:latest",
      essential = false,

      # This enables cloudwatch log group  
      logConfiguration = local.airflow_log_config,
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
  memory             = "1024"
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
        { name = "AIRFLOW__CORE__LOAD_EXAMPLES", value = "false" }
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
        { name = "AIRFLOW__CORE__LOAD_EXAMPLES", value = "false" }
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
  cpu                = "512"
  memory             = "1024"
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
  cpu                = "512"
  memory             = "1024"
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
  cpu                = "512"
  memory             = "1024"
  container_definitions = jsonencode([
    {
      name      = "kafka_ui_task",
      image     = "provectuslabs/kafka-ui:latest",   #official (widely used) kafka-ui image
      essential = true,

      # This enables cloudwatch log group
      logConfiguration = local.kafka_log_config,
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


# I had defined a DEFAULT capacity_provider_strategy for the whole ECS CLUSTER (scroll up), So there is no need defining them in individual service blocks. 
# If I do, they will overwrite the default capacity_provider_strategy.


# I don't need to define launch_type = "EC2" because this service uses a capacity provider.
# launch_type and capacity_provider_strategy are mutually exclusive, you can use only one.
# By using capacity_provider_strategy, ECS can work with the Auto Scaling Group to scale EC2 capacity based on task demand, which is not available when using launch_type alone.


# ordered_placement_strategy tells the ECS scheduler how to distribute your tasks across your EC2 instances. 
# In this project, I configured tasks to be spread evenly across availability zones. This only happens if we have desired_count > 1


# In ECS, there is no native “service‑to‑service” dependency like Docker Compose’s depends_on. 
# You can’t tell ECS “start the producer service only after the consumer service is healthy”. 
# ECS services are independent; they start tasks as soon as the service is created, and tasks keep restarting on failure.


# In subsequent iterations of this project, I will add ECS Service Auto Scaling


# Define the ECS SERVICES

# AIRFLOW SERVICES
resource "aws_ecs_service" "airflow_scheduler_service" {
  name            = "airflow_scheduler_service"
  cluster         = aws_ecs_cluster.data_platform_cluster.id
  task_definition = aws_ecs_task_definition.airflow_scheduler_task.arn
  desired_count   = 1

  network_configuration {
    security_groups  = [aws_security_group.airflow_sg.id]
    subnets          = aws_subnet.private[*].id
    assign_public_ip = false
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }
}

resource "aws_ecs_service" "airflow_webserver_service" {
  name            = "airflow_webserver_service"
  cluster         = aws_ecs_cluster.data_platform_cluster.id
  task_definition = aws_ecs_task_definition.airflow_webserver_task.arn
  desired_count   = 1

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

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }
}




# KAFKA SERVICES
resource "aws_ecs_service" "kafka_producer_service" {
  name            = "kafka_producer_service"
  cluster         = aws_ecs_cluster.data_platform_cluster.id
  task_definition = aws_ecs_task_definition.kafka_producer_task.arn
  desired_count   = 1

  network_configuration {
    security_groups  = [aws_security_group.kafka_utilities_sg.id]
    subnets          = aws_subnet.private[*].id
    assign_public_ip = false
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  # Ensure MSK exists before this service is created
  depends_on = [aws_msk_cluster.data_platform_kafka]
}

resource "aws_ecs_service" "kafka_consumer_service" {
  name            = "kafka_consumer_service"
  cluster         = aws_ecs_cluster.data_platform_cluster.id
  task_definition = aws_ecs_task_definition.kafka_consumer_task.arn
  desired_count   = 1

  network_configuration {
    security_groups  = [aws_security_group.kafka_utilities_sg.id]
    subnets          = aws_subnet.private[*].id
    assign_public_ip = false
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  # Ensure MSK exists before this service is created
  depends_on = [aws_msk_cluster.data_platform_kafka]
}

resource "aws_ecs_service" "kafka_ui_service" {
  name            = "kafka_ui_service"
  cluster         = aws_ecs_cluster.data_platform_cluster.id
  task_definition = aws_ecs_task_definition.kafka_ui_task.arn
  desired_count   = 1

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

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  # Ensure MSK exists before this service is created
  depends_on = [aws_msk_cluster.data_platform_kafka]
}

