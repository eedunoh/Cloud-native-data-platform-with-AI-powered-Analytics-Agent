
# IMPORTANT!

# Amazon MSK provides the Kafka broker infrastructure — you get the bootstrap servers and that's it. It does not include a web interface to browse topics, view messages, or manage consumer groups.
# provectuslabs/kafka-ui is a popular open‑source web UI that you run yourself (as a container) and point to your MSK cluster. It's optional.
# For production, many teams don't run a permanent UI; they rely on monitoring tools and CLI when needed. For learning, having the UI can be helpful, but it's not required.

# By default Kafka uses PLAINTEXT to communicate on port 9092. 

resource "aws_msk_cluster" "data_platform_kafka" {
  cluster_name           = var.kafka_cluster_name
  kafka_version          = "3.9.2"
  number_of_broker_nodes = var.az_count

  broker_node_group_info {
    instance_type   = "kafka.t3.small" # smallest/cheapest instance type. I will use this for this project
    client_subnets  = aws_subnet.private[*].id
    security_groups = [aws_security_group.mskafka_sg.id]

    storage_info {
      ebs_storage_info {
        volume_size = 20 # This is quite small but I will use this for the project
      }
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.mskafka_log_group.name
      }
    }
  }

  tags = { Name = "data-platform-msk" }
}


#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

output "msk_bootstrap_brokers_server" {
  value = aws_msk_cluster.data_platform_kafka.bootstrap_brokers
}