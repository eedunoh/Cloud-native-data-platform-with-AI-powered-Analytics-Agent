import os
import boto3


class Config:
    # Create a dictionary of all sheets to be batch processed
    sheets = {
        'data_platform_db.raw.stores': 'https://docs.google.com/spreadsheets/d/e/2PACX-1vQY3HBJbC64KzaBHdYRRd7nIdMxbrKPjM3jEKtXiM1VpCM9l_oVYv5WETqKx6GeUZwwaRKhLStS2t1Y/pub?gid=1732400668&single=true&output=csv'
    ,
        'data_platform_db.raw.products': 'https://docs.google.com/spreadsheets/d/e/2PACX-1vQY3HBJbC64KzaBHdYRRd7nIdMxbrKPjM3jEKtXiM1VpCM9l_oVYv5WETqKx6GeUZwwaRKhLStS2t1Y/pub?gid=1116619190&single=true&output=csv'
    ,
        'data_platform_db.raw.exchange_rates': 'https://docs.google.com/spreadsheets/d/e/2PACX-1vQY3HBJbC64KzaBHdYRRd7nIdMxbrKPjM3jEKtXiM1VpCM9l_oVYv5WETqKx6GeUZwwaRKhLStS2t1Y/pub?gid=321208867&single=true&output=csv'
    ,
        'data_platform_db.raw.customers': 'https://docs.google.com/spreadsheets/d/e/2PACX-1vQY3HBJbC64KzaBHdYRRd7nIdMxbrKPjM3jEKtXiM1VpCM9l_oVYv5WETqKx6GeUZwwaRKhLStS2t1Y/pub?gid=1182964335&single=true&output=csv'
    ,
        'data_platform_db.raw.data_dictionary': 'https://docs.google.com/spreadsheets/d/e/2PACX-1vQY3HBJbC64KzaBHdYRRd7nIdMxbrKPjM3jEKtXiM1VpCM9l_oVYv5WETqKx6GeUZwwaRKhLStS2t1Y/pub?gid=1536678535&single=true&output=csv'
    }


    # Store the AI document extract Snowflake raw table name
    ai_extract_db_raw_table = "data_platform_db.raw.ai_document_extracts"

    # Store AWS region in a variable
    aws_region = "eu-north-1"


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
        cls.batch_bucket = cls.get_ssm_parameter("batch_bucket")
        cls.policy_document_bucket = cls.get_ssm_parameter("policy_document_bucket")
        cls.document_extract_bucket = cls.get_ssm_parameter("document_extract_bucket")
        cls.dbt_docs_s3_bucket = cls.get_ssm_parameter("dbt_docs_s3_bucket")

        # Airlow Snowflake Connection details
        cls.snowflake_account = cls.get_ssm_parameter("snowflake_account")
        cls.snowflake_warehouse = cls.get_ssm_parameter("snowflake_warehouse")
        cls.snowflake_database = cls.get_ssm_parameter("snowflake_database")
        cls.airflow_data_platform_user = cls.get_ssm_parameter("airflow_data_platform_user")
        cls.airflow_data_platform_user_password = cls.get_ssm_parameter("airflow_data_platform_user_password")
        cls.airflow_data_platform_role = cls.get_ssm_parameter("airflow_data_platform_role")

        # Claude/Anthropic API key
        cls.anthropic_api_key = cls.get_ssm_parameter("anthropic_api_key")

        missing = [name for name in 
                   [
                    "batch_bucket", 
                    "policy_document_bucket", 
                    "document_extract_bucket", 
                    "dbt_docs_s3_bucket",

                    "snowflake_account",
                    "snowflake_warehouse",
                    "snowflake_database",
                    "airflow_data_platform_user",
                    "airflow_data_platform_user_password",
                    "airflow_data_platform_role",

                    "anthropic_api_key"
                    ]
                if getattr(cls, name) is None]
        
        if missing:
            raise ValueError(f"Failed to load required SSM parameters: {missing}")


# Explicitly initialize the class variables
Config.initialize()