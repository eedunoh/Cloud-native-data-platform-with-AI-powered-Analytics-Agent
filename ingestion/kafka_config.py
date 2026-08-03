import os
import boto3


class Config:

    # Store AWS region in a variable
    aws_region = "eu-north-1"


    # Streaming data set
    streaming_data_set = "https://raw.githubusercontent.com/eedunoh/Cloud-native-data-platform-with-AI-powered-Analytics-Agent/main/Sales.csv"


    # Get bucket names from SSM store
    @staticmethod
    def get_ssm_parameter(param_name, with_decryption=True):
        try:
            ssm = boto3.client("ssm", region_name=Config.aws_region)
            response = ssm.get_parameter(Name=param_name, WithDecryption=with_decryption)

                # This is what the response looks like;

                # {
                #  "Parameter": {
                #     "Name": "streaming_bucket",
                #      "Type": "String",
                #      "Value": "data-platform-streamed-data-bucket",
                #      "Version": 4,
                #      "LastModifiedDate": datetime.datetime(...),
                #      "ARN": "arn:aws:ssm:eu-north-1:123456789012:parameter/streaming_bucket",
                #      "DataType": "text"
                #     },
                #  "ResponseMetadata": { ... }
                # }

                # So we will tell python, "Inside the response, go to the "Parameter" object, then give me only the "Value" field."
            
            return response["Parameter"]["Value"]
        
        except Exception as e:
            print(f"Warning: Unable to fetch {param_name} from SSM = {e}")
            return None


    
    @classmethod
    def initialize(cls):

        # S3 buckets
        cls.streamed_data_bucket = cls.get_ssm_parameter("streaming_bucket")

        # Snowflake connection details
        cls.snowflake_account = cls.get_ssm_parameter("snowflake_account")
        cls.snowflake_database = cls.get_ssm_parameter("snowflake_database")
        cls.snowflake_streaming_pipe = cls.get_ssm_parameter("snowflake_streaming_pipe")
        cls.kafka_streamer_user = cls.get_ssm_parameter("kafka_streamer_user")
        cls.snowflake_private_key = cls.get_ssm_parameter("snowflake_private_key")

        # Others
        cls.msk_bootstrap_server = cls.get_ssm_parameter("msk_bootstrap_server")

        missing = [name for name in 
                   [
                    "streamed_data_bucket", 
       
                    "snowflake_account", 
                    "snowflake_database", 
                    "snowflake_streaming_pipe",
                    "kafka_streamer_user", 
                    "snowflake_private_key", 

                    "msk_bootstrap_server"
                    ]
                if getattr(cls, name) is None]
        
        if missing:
            raise ValueError(f"Failed to load required SSM parameters (or Secrets): {missing}")


# Explicitly initialize the class variables
Config.initialize()